#!/usr/bin/env bash
# The current branch's changed files that the conventions cover — the default scope of check-conventions,
# test-code and the lint runs. Run from anywhere inside the repo.
#
#   bash changed-files.sh
#   → stdout: repo-relative paths, one per line — `*/src/(main|test)/kotlin/*.kt` and
#     `*/src/main/resources/application*.yml|yaml` that are committed since the base branch, modified in
#     the working tree (staged or not) or untracked; deletions are left out. Empty = nothing changed.
#   → stderr: `base: <branch>` (`base: none` when no integration branch exists; then only the working
#     tree and untracked files count). Always exits 0.
#
# Base: of develop, main, master and their origin/ copies, the one whose merge-base with HEAD has the
# fewest commits ahead — the branch this one forked from. Paths a `.convention-lint-ignore` entry with
# the ID `*` matches (a whole exempt tree) are dropped.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 0

cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); base=""; basemb=""; best=-1
for c in develop main master origin/develop origin/main origin/master; do
  git rev-parse --verify --quiet "$c" >/dev/null 2>&1 || continue
  [ "$c" = "$cur" ] && continue
  mb=$(git merge-base "$c" HEAD) || continue
  ahead=$(git rev-list --count "$mb..HEAD")
  if [ "$best" -lt 0 ] || [ "$ahead" -lt "$best" ]; then best=$ahead; base=$c; basemb=$mb; fi
done
echo "base: ${base:-none}" >&2

{ [ -n "$basemb" ] && git diff --diff-filter=d --name-only "$basemb..HEAD"
  git diff --diff-filter=d --name-only HEAD
  git ls-files --others --exclude-standard; } |
  sort -u | grep -E '/src/(main|test)/kotlin/.*\.kt$|/src/main/resources/application[^/]*\.ya?ml$' |
  while IFS= read -r path; do
    if [ -f .convention-lint-ignore ]; then
      while IFS= read -r entry || [ -n "$entry" ]; do
        case "$entry" in '#'*) continue ;; *:'*') ;; *) continue ;; esac
        pat=${entry%:*}; pat=${pat#./}
        # shellcheck disable=SC2254
        case "$path" in $pat) continue 2 ;; esac
      done < .convention-lint-ignore
    fi
    printf '%s\n' "$path"
  done
exit 0
