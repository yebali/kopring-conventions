#!/usr/bin/env bash
# STY-10 — blank line before a block-body function's final top-level `return`.
#
# ktlint has no rule for this, so the convention is otherwise unenforceable unless
# detekt is wired in. Used by coding-workflow (done gate) and check-conventions
# (Check D). Run from anywhere inside the repo; file arguments may be relative to
# the current directory or absolute, and hits are reported relative to the repo root.
#
#   bash blank-line-before-return.sh                  # report over the whole tree (prints file:line, exits 1 if any)
#   bash blank-line-before-return.sh a.kt b.kt        # report over these files only
#   bash blank-line-before-return.sh --fix a.kt b.kt  # insert the missing blank lines in these files
#   bash blank-line-before-return.sh --fix            # … in the whole tree
#   → exits 2 when no Kotlin source file was scanned
#
# Detection: a `return` that (a) is the last statement of its block (the next
# line at or below its indent is the block's closing brace), (b) sits in a `fun`
# body (walking up to the line at the brace's indent, and past a multi-line
# signature's `): T {`, reaches a `fun` declaration with no `=` outside its
# parameter lists; an expression body's lambda is not a function body), and (c) is
# preceded by a statement line that is not blank, not a block opener, and not a
# comment. A `return` closing an inner block (if/when branch/for/try/lambda) is an
# early return and out of scope.
# Multi-line `return` expressions are included; a naive "next line is the closing
# brace" check undercounts them roughly 4x. Blind spots: property accessors
# (`get() { … }`), and a body containing a line indented left of the function
# (a raw string at column 0).
#
# Project exceptions: `.convention-lint-ignore` at the repository root (see
# convention-lint.sh); entries whose ID is `STY-10` or `*` drop the hits on their paths.
set -euo pipefail

MODE=report
if [ "${1:-}" = "--fix" ]; then MODE=--fix; shift; fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
FILES=$(mktemp)
trap 'rm -f "$FILES"' EXIT
# every argument becomes a ROOT-relative path, whatever the current directory
for f in "$@"; do
    case "$f" in *.kt) [ -f "$f" ] || continue ;; *) continue ;; esac
    case "$f" in */*) d=${f%/*} ;; *) d=. ;; esac
    f=$(cd "$d" && pwd -P)/${f##*/}
    printf '%s\n' "${f#"$ROOT"/}"
done > "$FILES"
cd "$ROOT"
if [ "$#" -eq 0 ]; then
    find . \( -path "*/src/main/kotlin/*" -o -path "*/src/test/kotlin/*" \) -name "*.kt" -not -path "*/build/*" |
        sed 's#^\./##' | sort > "$FILES"
fi
if [ ! -s "$FILES" ]; then
    echo "blank-line-before-return: no Kotlin source file was scanned" >&2
    exit 2
fi

# One awk process for all files — a per-file loop costs one fork per file.
# BSD awk has no ENDFILE, so each file is flushed when the next one starts.
detect() {
    tr '\n' '\0' < "$FILES" |
        xargs -0 awk '
            # Is the block whose opener sits at indent oi, above line i, a function body?
            function fun_body(i, oi,   k, o, h) {
                for (k = i - 1; k > 0; k--) {
                    if (line[k] ~ /^[ ]*$/) continue
                    match(line[k], /^[ ]*/)
                    if (RLENGTH < oi) return 0
                    if (RLENGTH > oi) continue
                    if (!o) o = k                             # the line holding the `{`
                    if (line[k] !~ /^[ ]*[)}\]>]/) break        # not a `): T {` / `} else {` continuation
                }
                if (k < 1 || line[k] !~ /^[ ]*([A-Za-z@][^ ]*[ ]+)*fun[ (<]/) return 0
                for (h = ""; k <= o; k++) h = h " " line[k]
                while (gsub(/\([^()]*\)/, "", h)) ;            # drop parameter lists (default values hold `=`)
                return h !~ /=/
            }
            function flush(   i, j, ci, closer) {
                for (i = 2; i <= n; i++) {
                    if (line[i] !~ /^[ ]+return[ (]/) continue
                    if (line[i-1] ~ /^[ ]*$/) continue        # already separated
                    # first statement in its block — `{`, a lambda opener (`{ it ->`),
                    # or a `when` branch arrow all open a block whose first statement
                    # must NOT be preceded by a blank line (STY-10 "적용 안 함").
                    if (line[i-1] ~ /(\{|->)[ ]*$/) continue
                    if (line[i-1] ~ /^[ ]*\/\//) continue     # comment directly above
                    match(line[i], /^[ ]*/); ci = RLENGTH
                    if (!fun_body(i, ci - 4)) continue        # early return out of an inner block
                    closer = sprintf("%*s}", ci - 4, "")
                    for (j = i + 1; j <= n; j++) {
                        if (line[j] == closer) { print f ":" i; break }
                        if (line[j] ~ /^[ ]*$/) continue
                        match(line[j], /^[ ]*/)
                        # a sibling statement means the return was not last; continuation
                        # lines are indented deeper or start with a closing bracket
                        if (RLENGTH <= ci && line[j] !~ /^[ ]*[)}\]]/) break
                    }
                }
            }
            FNR == 1 && NR > 1 { flush(); n = 0; delete line }
            FNR == 1 { f = FILENAME }
            { line[FNR] = $0; n = FNR }
            END { flush() }
        '
}

# Drop the hits `.convention-lint-ignore` exempts (entry ID `STY-10` or `*`).
unignored() {
    local hit path entry pat drop
    while IFS= read -r hit; do
        path=${hit%%:*}; drop=0
        if [ -f .convention-lint-ignore ]; then
            while IFS= read -r entry || [ -n "$entry" ]; do
                case "$entry" in ''|'#'*) continue ;; esac
                case "${entry##*:}" in STY-10|'*') ;; *) continue ;; esac
                pat=${entry%:*}; pat=${pat#./}
                # shellcheck disable=SC2254
                case "$path" in $pat) drop=1; break ;; esac
            done < .convention-lint-ignore
        fi
        if [ "$drop" -eq 0 ]; then printf '%s\n' "$hit"; fi
    done
}

hits=$(detect | unignored)
total=$([ -z "$hits" ] && echo 0 || printf '%s\n' "$hits" | wc -l | tr -d ' ')

if [ "$MODE" != "--fix" ]; then
    [ -n "$hits" ] && printf '%s\n' "$hits"
    echo "---"
    echo "total: $total"
    [ "$total" -gt 0 ] && exit 1
    exit 0
fi

# Fix mode: one awk rewrite per affected file, not per scanned file.
printf '%s\n' "$hits" | awk -F: 'NF==2 {a[$1] = a[$1] " " $2} END {for (f in a) print f a[f]}' |
    while read -r file lines; do
        marks=$(printf '%s' "$lines" | tr ' ' ',')
        tmp="$file.tmp$$"
        awk -v marks="$marks" '
            BEGIN { split(marks, m, ","); for (i in m) if (m[i] != "") want[m[i] + 0] = 1 }
            { if (FNR in want) print ""; print }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
        echo "fixed $(printf '%s' "$lines" | wc -w | tr -d ' ')  $file"
    done

echo "---"
echo "inserted $total blank line(s)"
