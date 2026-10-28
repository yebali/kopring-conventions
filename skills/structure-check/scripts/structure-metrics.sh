#!/usr/bin/env bash
# Deterministic structural-hotspot ranking for structure-check Phase 0.
# Report-only — never edits. Invoked from structure-check Phase 0; also usable
# standalone from anywhere inside the repo.
#
#   bash structure-metrics.sh                 # full TSV, every module's src/main
#   bash structure-metrics.sh orders          # full TSV, that module only
#   bash structure-metrics.sh --top           # per-metric leaderboards (what Phase 0 reads)
#   bash structure-metrics.sh --top orders
#
# Environment (all optional):
#   BASE_PACKAGE      root package, default: first two segments of the first `package` line found
#                     (e.g. com.acme)
#   DOMAIN_SEGMENTS   package segments below BASE_PACKAGE that identify a domain, default 2
#                     (com.acme.shop.order → domain `com.acme.shop.order`)
#   SHARED_RE         extended regex; imports whose domain prefix matches it are infrastructure,
#                     not coupling. Default: (^|\.)(common|core|shared|util|config|client|infra)(\.|$)
#
# WHY THIS EXISTS: structure-check scans whole modules (thousands of production
# files in a large one). Dispatching scan agents over a blind glob is slow and noisy.
# This script ranks candidates FIRST so each agent gets a short list of real
# outliers instead of a directory. It computes NO composite "complexity score" on
# purpose — a file can be an outlier on exactly one axis (a service with 49
# deps but only 7 functions is a cohesion outlier, not a size one), and a weighted
# sum would bury exactly that signal.
#
# Metric inventory (definition · exemptions · blind spots) lives HERE — the single
# source of truth. structure-check's Phase 0 just runs this script.
#
#   loc      Total lines in the file. Weakest signal, kept for context only: a
#            550-line generated-shaped Response DTO is long, not complex.
#
#   deps     Injection fan-out: `private val` lines in the TOP-LEVEL class's primary
#            constructor. Two deliberate narrowings:
#              - the class declaration must start at column 0. Without this, the
#                inner Command/Result data classes that SVC-6 mandates inside
#                every service file re-open the counter and report DTO property
#                counts as fan-out.
#              - only `private val` counts, which is the constructor-injection
#                idiom — a plain `val` in a constructor is a DTO property.
#            Blind spot: a single-line constructor (`class Foo(private val a: A)`)
#            counts 0 — deliberate, a one-line constructor is never an outlier.
#            Secondary constructors and `init` blocks are not counted.
#
#   funs     Function declarations, any visibility, including local `fun` inside a
#            body (rare in this tree). Paired with `deps` it separates a god
#            service (high both) from a wiring hub (high deps, low funs).
#
#   xdomain  Distinct OTHER domain packages imported, by prefix of BASE_PACKAGE plus
#            DOMAIN_SEGMENTS segments (`com.acme.shop.order`, `com.acme.shop.user`).
#            The file's own prefix is excluded. EXCLUDED BY DESIGN (SHARED_RE), so
#            they never inflate the count: shared and infrastructure packages
#            (common, core, shared, util, config, client, infra by default) — every
#            domain imports them; that is the layering, not coupling.
#            Blind spot: a cross-domain reach via a fully-qualified name instead of
#            an import is invisible here (STY-2 bans FQNs, so this is thin).
#
#   depth    Max indentation depth (leading spaces / 4; ktlint pins 4-space indent).
#            Blind spots, both inflating: a wrapped multi-line annotation argument
#            (`@Schema(...)` across several lines) and a long builder/DSL chain
#            indent like nested control flow. So treat depth as a read-this-file
#            hint, never as evidence on its own. Deflating: a flat `when` with 30
#            branches scores low — correct, a flat table is the shape we WANT.
#
#   cfg      Hits for the configuration-entanglement tokens: @ConditionalOn,
#            @Profile, @Qualifier, ObjectProvider, @Async, Propagation., inNewTx.
#            Not violations — each may be justified. A non-zero cfg means the
#            file's effective behaviour depends on something other than its own
#            source, which is what makes it worth a human read.
#
# Scope: production sources only (`*/src/main/**`). Tests are deliberately out —
# test structure is owned by the testing / test-coverage references.

set -uo pipefail

# repo root, so the script works from any cwd inside the repository
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

mode="full"
module=""
for arg in "$@"; do
  case "$arg" in
    --top) mode="top" ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) module="$arg" ;;
  esac
done

# validate the module against settings.gradle(.kts) — never against a hardcoded list,
# so a newly added module is accepted the day it is added.
if [ -n "$module" ]; then
  valid=$(grep -hoE "include\(?[[:space:]]*[\"'][^\"']+[\"']" settings.gradle.kts settings.gradle 2>/dev/null |
    sed -E "s/include\(?[[:space:]]*[\"']:?([^\"']+)[\"']/\1/")
  if ! printf '%s\n' "$valid" | grep -qx "$module"; then
    echo "unknown module: $module" >&2
    echo "valid modules:" >&2
    printf '  %s\n' $valid >&2
    exit 2
  fi
  search_root="$module/src/main"
  [ -d "$search_root" ] || { echo "no src/main in $module" >&2; exit 2; }
else
  search_root=""
fi

if [ -n "$search_root" ]; then
  files=$(find "$search_root" -name '*.kt' -type f | sort)
else
  files=$(find . -path '*/src/main/*' -name '*.kt' -type f -not -path './build/*' | sed 's#^\./##' | sort)
fi

[ -n "$files" ] || { echo "no production Kotlin files found" >&2; exit 2; }

BASE_PACKAGE=${BASE_PACKAGE:-}
if [ -z "$BASE_PACKAGE" ]; then
  BASE_PACKAGE=$(printf '%s\n' "$files" | head -50 | tr '\n' '\0' | xargs -0 grep -h -m1 '^package ' 2>/dev/null | head -1 |
    sed -E 's/^package[[:space:]]+([A-Za-z0-9_]+(\.[A-Za-z0-9_]+)?).*/\1/')
fi
bp_re=$(printf '%s' "$BASE_PACKAGE" | sed 's/\./\\./g')
dom_cut=$(( $(printf '%s' "$BASE_PACKAGE" | tr -cd . | wc -c) + 1 + ${DOMAIN_SEGMENTS:-2} ))
shared_re=${SHARED_RE:-'(^|\.)(common|core|shared|util|config|client|infra)(\.|$)'}

emit_rows() {
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -n "$f" ] || continue

    loc=$(wc -l < "$f" | tr -d ' ')

    # primary-constructor property count; stops at the line closing the ctor
    deps=$(awk '
      /^(class |internal class |abstract class |open class |sealed class )/ && /\($/ && !done { inctor=1; next }
      inctor && /^[[:space:]]*\)/ { inctor=0; done=1 }
      inctor && /private val / { c++ }
      END { print c+0 }
    ' "$f")

    funs=$(grep -cE '^[[:space:]]*(private |internal |protected |public |suspend |override |open |abstract |inline |operator )*fun ' "$f")

    # own 3-segment package prefix, then distinct other domain prefixes imported
    own=$(grep -m1 -E "^package ${bp_re}\." "$f" | awk '{print $2}' | cut -d. -f1-"$dom_cut")
    xdomain=$(grep -E "^import ${bp_re}\." "$f" \
      | awk '{print $2}' | cut -d. -f1-"$dom_cut" \
      | grep -vE "$shared_re" \
      | grep -vx "$own" | sort -u | wc -l | tr -d ' ')

    depth=$(awk '
      /^[[:space:]]*$/ { next }
      { match($0, /^[ ]*/); d = RLENGTH / 4; if (d > m) m = d }
      END { print int(m)+0 }
    ' "$f")

    cfg=$(grep -cE '@ConditionalOn|@Profile|@Qualifier|ObjectProvider|@Async|Propagation\.|inNewTx' "$f")

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$loc" "$deps" "$funs" "$xdomain" "$depth" "$cfg" "$f"
  done
}

rows=$(emit_rows)

if [ "$mode" = "full" ]; then
  printf 'loc\tdeps\tfuns\txdomain\tdepth\tcfg\tpath\n'
  printf '%s\n' "$rows" | sort -t"$(printf '\t')" -k1,1rn
  exit 0
fi

# --top: per-metric leaderboards. Phase 0 reads these; the union of the lists is
# the hotspot set handed to the scan agents.
top_by() {
  local col=$1 label=$2 n=${3:-15}
  echo "## top $n by $label"
  printf '%s\n' "$rows" \
    | sort -t"$(printf '\t')" -k"$col","$col"rn \
    | head -"$n" \
    | awk -F'\t' -v c="$col" '$c+0 > 0 { printf "  %-6s %s\n", $c, $7 }'
  echo
}

echo "# structure-metrics — scope: ${module:-all modules} — $(printf '%s\n' "$rows" | grep -c . ) production files"
echo
top_by 2 "deps (injection fan-out)"
top_by 4 "xdomain (other domain packages imported)"
top_by 3 "funs (function count)"
top_by 5 "depth (max nesting)"
top_by 6 "cfg (configuration-entanglement tokens)"
top_by 1 "loc (file length — context only)"
