#!/usr/bin/env bash
# Run baseline (B0 sledge, B1 prover, B2 planner) on HOL synthetic test tiers.
#
# Usage:
#   scripts/run_baseline_hol.sh easy        # one tier
#   scripts/run_baseline_hol.sh easy mid    # multiple
#   scripts/run_baseline_hol.sh all         # easy + mid + hard
#
# Tier config (from issue #2):
#   easy : 60s  beam 3 depth 6 facts 6
#   mid  : 120s beam 4 depth 8 facts 6
#   hard : 200s beam 5 depth 10 facts 8
#
# Pinned across all:
#   model gemini:gemini-3-flash-preview  seed 42  k 3  temps 0.35,0.55,0.85
#   ATPs in sledge: e z3 vampire cvc5

set -uo pipefail

cd "$(dirname "$0")/.."

: "${GEMINI_API_KEY:?GEMINI_API_KEY not exported. source ~/.zshrc or export manually.}"

source .venv/bin/activate

ISABELLE_BIN="/Applications/Isabelle2025.app/bin/isabelle"
export PATH="/Applications/Isabelle2025.app/bin:$PATH"

MODEL="gemini:gemini-3-flash-preview"
SEED=42
SLEDGE_PROVERS="e z3 vampire cvc5"

OUT_BASE="datasets/results/baseline"
LOG_BASE="logs/baseline"
mkdir -p "$OUT_BASE"/{sledge,prover,planner} "$LOG_BASE"

tier_for() {
  case "$1" in
    easy) echo "60 3 6 6" ;;
    mid)  echo "120 4 8 6" ;;
    hard) echo "200 5 10 8" ;;
    *) echo "" ;;
  esac
}

run_tier() {
  local tier="$1"
  local goalfile="datasets/hol_main_${tier}_goals_test.txt"
  local stamp; stamp="$(date -u +%Y%m%dT%H%M%SZ)"

  read -r TIMEOUT BEAM DEPTH FACTS <<<"$(tier_for "$tier")"
  if [[ -z "${TIMEOUT:-}" ]]; then
    echo "[skip] unknown tier: $tier"; return 1
  fi

  echo "=== HOL $tier  ($(date -u)) goals=$(wc -l <"$goalfile") timeout=${TIMEOUT}s beam=${BEAM} depth=${DEPTH} facts=${FACTS} ==="

  # B0 sledge-only ------------------------------------------------------------
  echo "--- B0 sledge-only ---"
  python baselines/sledge_only.py \
    --file "$goalfile" --imports Main \
    --provers "$SLEDGE_PROVERS" \
    --sledge-timeout 60 --goal-timeout "$((TIMEOUT + 30))" \
    --print-logs \
    > "$OUT_BASE/sledge/hol_${tier}_test.log" 2>&1
  echo "  -> $OUT_BASE/sledge/hol_${tier}_test.log"

  # B1 prover bench -----------------------------------------------------------
  echo "--- B1 prover bench ---"
  python -m prover.experiments bench \
    --file "$goalfile" \
    --beam "$BEAM" --max-depth "$DEPTH" --timeout "$TIMEOUT" \
    --facts-limit "$FACTS" --quickcheck --nitpick --sledge --variants \
    --no-minimize --model "$MODEL" \
    --shuffle --seed "$SEED" \
    > "$LOG_BASE/${stamp}_prover_hol_${tier}.log" 2>&1
  # Latest prover CSV for this tier --> baseline/prover/
  latest_p="$(ls -t datasets/results/*.csv 2>/dev/null | head -1)"
  if [[ -n "$latest_p" && "$latest_p" != "$OUT_BASE/prover/"* ]]; then
    mv "$latest_p" "$OUT_BASE/prover/hol_${tier}.csv"
  fi
  echo "  -> $OUT_BASE/prover/hol_${tier}.csv"

  # B2 planner bench ----------------------------------------------------------
  echo "--- B2 planner bench ---"
  python -m planner.experiments bench \
    --file "$goalfile" \
    --mode auto --diverse --k 3 --temps "0.35,0.55,0.85" \
    --timeout "$TIMEOUT" --strict-no-sorry --verify \
    --model "$MODEL" \
    --shuffle --seed "$SEED" \
    > "$LOG_BASE/${stamp}_planner_hol_${tier}.log" 2>&1
  latest_pl="$(ls -t datasets/planner_results/*.csv 2>/dev/null | head -1)"
  if [[ -n "$latest_pl" && "$latest_pl" != "$OUT_BASE/planner/"* ]]; then
    mv "$latest_pl" "$OUT_BASE/planner/hol_${tier}.csv"
  fi
  echo "  -> $OUT_BASE/planner/hol_${tier}.csv"

  echo "=== HOL $tier done ($(date -u)) ==="
}

main() {
  local tiers=()
  for arg in "$@"; do
    case "$arg" in
      all) tiers+=(easy mid hard) ;;
      easy|mid|hard) tiers+=("$arg") ;;
      *) echo "unknown tier: $arg"; exit 2 ;;
    esac
  done
  if [[ ${#tiers[@]} -eq 0 ]]; then
    echo "usage: $0 {easy|mid|hard|all} ..."; exit 2
  fi

  for t in "${tiers[@]}"; do
    run_tier "$t"
  done
}

main "$@"
