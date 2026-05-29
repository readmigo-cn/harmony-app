#!/usr/bin/env bash
# check-bundle-size.sh
#
# Verifies per-HSP build output sizes against the budgets defined in
# docs/bundle-strategy.md §3.
#
# Usage:
#   ./scripts/check-bundle-size.sh [BUILD_ROOT]
#
# BUILD_ROOT defaults to "./build/default/outputs/release" (hvigorw assembleHap output).
# Each HSP outputs a .hsp file; entry outputs a .hap file.
#
# Exit codes:
#   0 — all modules within budget
#   1 — one or more modules over budget (details printed to stderr)
#
# Hookable into hvigor pre-pack stage by adding to hvigorfile.ts:
#   taskPath: './scripts/check-bundle-size.sh'

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${1:-${PROJECT_ROOT}/build/default/outputs/release}"

# Budget table (KB) — must stay in sync with docs/bundle-strategy.md §3
declare -A BUDGET_KB=(
  ["entry"]=4500
  ["reader"]=2500
  ["vocab"]=1000
  ["paywall"]=700
  ["tablet"]=800
  ["tv"]=900
  ["car"]=600
  ["watch"]=500
  ["widget"]=400
)

# File extension per module type
declare -A MODULE_EXT=(
  ["entry"]="hap"
  ["reader"]="hsp"
  ["vocab"]="hsp"
  ["paywall"]="hsp"
  ["tablet"]="hsp"
  ["tv"]="hsp"
  ["car"]="hsp"
  ["watch"]="hsp"
  ["widget"]="hsp"
)

FAIL=0
PASS=0
SKIP=0

printf "%-12s %10s %10s %6s\n" "MODULE" "SIZE(KB)" "BUDGET(KB)" "STATUS"
printf "%-12s %10s %10s %6s\n" "------" "--------" "----------" "------"

for module in entry reader vocab paywall tablet tv car watch widget; do
  ext="${MODULE_EXT[$module]}"
  budget="${BUDGET_KB[$module]}"

  # Try to locate the output artifact. hvigor may nest it differently per SDK version.
  artifact=""
  for candidate in \
    "${BUILD_ROOT}/${module}/${module}.${ext}" \
    "${BUILD_ROOT}/${module}.${ext}" \
    "${PROJECT_ROOT}/${module}/build/default/outputs/release/${module}.${ext}"; do
    if [[ -f "$candidate" ]]; then
      artifact="$candidate"
      break
    fi
  done

  if [[ -z "$artifact" ]]; then
    printf "%-12s %10s %10s %6s\n" "$module" "N/A" "${budget}" "SKIP"
    SKIP=$((SKIP + 1))
    continue
  fi

  # du -k gives size in 1K blocks (rounds up); matches DevEco Build Report behaviour
  size_kb=$(du -k "$artifact" | awk '{print $1}')

  if (( size_kb > budget )); then
    printf "%-12s %10s %10s %6s\n" "$module" "${size_kb}" "${budget}" "OVER"
    echo "  OVER BUDGET: ${artifact}" >&2
    FAIL=$((FAIL + 1))
  else
    printf "%-12s %10s %10s %6s\n" "$module" "${size_kb}" "${budget}" "OK"
    PASS=$((PASS + 1))
  fi
done

echo ""
echo "Results: ${PASS} ok, ${FAIL} over budget, ${SKIP} skipped (artifact not found)"

if (( SKIP > 0 )); then
  echo "WARN: ${SKIP} module(s) had no build artifact — run 'hvigorw assembleHap --mode product=release' first."
fi

if (( FAIL > 0 )); then
  echo "ERROR: ${FAIL} module(s) exceed size budget. See docs/bundle-strategy.md §3 for budgets." >&2
  exit 1
fi

exit 0
