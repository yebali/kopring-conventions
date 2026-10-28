#!/usr/bin/env bash
# STY-10 — blank line before a block-body function's final top-level `return`.
#
# ktlint has no rule for this, so the convention is otherwise unenforceable unless
# detekt is wired in. Invoked from convention-check Phase 2 (Check D). Run from
# anywhere inside the repo.
#
#   bash blank-line-before-return.sh          # report  (prints file:line, exits 1 if any)
#   bash blank-line-before-return.sh --fix    # insert the missing blank lines
#
# Detection: a `return` that (a) is the last statement of its block — the next
# line at or below its indent is the block's closing brace — and (b) is preceded
# by a statement line that is not blank, not a block opener, and not a comment.
# Multi-line `return` expressions are included; a naive "next line is the
# closing brace" check undercounts them roughly 4x.
set -euo pipefail

MODE="${1:-report}"
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# One awk process for the whole tree — a per-file loop costs one fork per file.
# BSD awk has no ENDFILE, so each file is flushed when the next one starts.
detect() {
    find . \( -path "*/src/main/kotlin/*" -o -path "*/src/test/kotlin/*" \) -name "*.kt" -not -path "*/build/*" -print0 |
        sort -z |
        xargs -0 awk '
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

hits=$(detect)
total=$([ -z "$hits" ] && echo 0 || printf '%s\n' "$hits" | wc -l | tr -d ' ')

if [ "$MODE" != "--fix" ]; then
    [ -n "$hits" ] && printf '%s\n' "$hits"
    echo "---"
    echo "total: $total"
    [ "$total" -gt 0 ] && exit 1
    exit 0
fi

# Fix mode: one awk rewrite per affected file per affected file, not per scanned file.
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
