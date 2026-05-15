#!/usr/bin/env bash
# Cascade-launch all baseline benches in sequence.
# Designed to be re-runnable: skips tiers already complete.
#
# Order (max 2 concurrent procs to respect 24GB RAM):
#   1. B2 planner smoke lists  (if not done)        --> blocks
#   2. B0 sledge HOL easy + B1 prover HOL easy      (concurrent)
#   3. B0 sledge HOL mid + B1 prover HOL mid        (concurrent, after #2)
#   4. B0 sledge HOL hard + B1 prover HOL hard      (concurrent, after #3)
#   5. B2 planner HOL easy (serial)                 (after #2 done)
#   6. B2 planner HOL mid (serial)                  (after #5)
#   7. B2 planner HOL hard (serial)                 (after #6)
#   8. make_master_table.py + git tag baseline-v0
#
# Total wallclock: ~25-40h. Run via nohup, monitor with `tail -f`.

set -uo pipefail
cd "$(dirname "$0")/.."

: "${GEMINI_API_KEY:?GEMINI_API_KEY not set}"

source .venv/bin/activate
export PATH="/Applications/Isabelle2025.app/bin:$PATH"

MODEL="gemini:gemini-3-flash-preview"
SEED=42
SLEDGE_PROVERS="e z3 vampire cvc5"

OUT="datasets/results/baseline"
LOG="logs/baseline"
mkdir -p "$OUT"/{sledge,prover,planner} "$LOG"

# ------------------ tier config ------------------
declare -A TO=( [easy]=60   [mid]=120  [hard]=200 )
declare -A BM=( [easy]=3    [mid]=4    [hard]=5   )
declare -A DP=( [easy]=6    [mid]=8    [hard]=10  )
declare -A FL=( [easy]=6    [mid]=6    [hard]=8   )

# ------------------ functions --------------------
done_file() { [[ -s "$1" ]] && grep -q "Summary\|=== Bench" "$1" 2>/dev/null; }

mv_prover_csv() {
  local target="$1"
  local latest; latest="$(ls -t datasets/results/*.csv 2>/dev/null | grep -v baseline/ | head -1)"
  [[ -n "$latest" ]] && mv "$latest" "$target"
}
mv_planner_csv() {
  local target="$1"
  local latest; latest="$(ls -t datasets/planner_results/*.csv 2>/dev/null | head -1)"
  [[ -n "$latest" ]] && mv "$latest" "$target"
}

run_sledge() {
  local tier="$1"
  local out="$OUT/sledge/hol_${tier}_test.log"
  local goalfile="datasets/hol_main_${tier}_goals_test.txt"
  if done_file "$out"; then echo "[skip] B0 $tier (have $out)"; return; fi
  echo "[run] B0 sledge $tier  -> $out  ($(date -u))"
  python baselines/sledge_only.py \
    --file "$goalfile" --imports Main \
    --provers "$SLEDGE_PROVERS" \
    --sledge-timeout 60 --goal-timeout "$((TO[$tier] + 30))" \
    --print-logs > "$out" 2>&1
  echo "[done] B0 $tier  ($(date -u))"
}

run_prover() {
  local tier="$1"
  local csv="$OUT/prover/hol_${tier}.csv"
  local log="$LOG/prover_hol_${tier}.log"
  local goalfile="datasets/hol_main_${tier}_goals_test.txt"
  if [[ -s "$csv" ]]; then echo "[skip] B1 $tier (have $csv)"; return; fi
  echo "[run] B1 prover $tier  -> $csv  ($(date -u))"
  python -m prover.experiments bench \
    --file "$goalfile" \
    --beam "${BM[$tier]}" --max-depth "${DP[$tier]}" --timeout "${TO[$tier]}" \
    --facts-limit "${FL[$tier]}" --quickcheck --nitpick --sledge --variants \
    --no-minimize --model "$MODEL" \
    --shuffle --seed "$SEED" > "$log" 2>&1
  mv_prover_csv "$csv"
  echo "[done] B1 $tier  ($(date -u))"
}

run_planner() {
  local tier="$1"
  local csv="$OUT/planner/hol_${tier}.csv"
  local log="$LOG/planner_hol_${tier}.log"
  local goalfile="datasets/hol_main_${tier}_goals_test.txt"
  if [[ -s "$csv" ]]; then echo "[skip] B2 $tier (have $csv)"; return; fi
  echo "[run] B2 planner $tier  -> $csv  ($(date -u))"
  python -m planner.experiments bench \
    --file "$goalfile" \
    --mode auto --diverse --k 3 --temps "0.35,0.55,0.85" \
    --timeout "${TO[$tier]}" --strict-no-sorry --verify \
    --model "$MODEL" \
    --shuffle --seed "$SEED" > "$log" 2>&1
  mv_planner_csv "$csv"
  echo "[done] B2 $tier  ($(date -u))"
}

# ------------------ cascade ----------------------
echo "=== cascade start $(date -u) ==="

# Pair B0 + B1 per tier (different machines wise: B0 spawns isabelle build,
# B1 uses isabelle-client server — independent). Run sequentially per tier
# to limit RAM. B2 then runs serially afterwards.

for tier in easy mid hard; do
  run_sledge "$tier"
  run_prover "$tier"
done

for tier in easy mid hard; do
  run_planner "$tier"
done

# ------------------ aggregate --------------------
echo "[aggregate] $(date -u)"
python scripts/make_master_table.py

# ------------------ tag --------------------------
if git -C . diff --quiet HEAD 2>/dev/null; then
  git tag -f baseline-v0
  echo "[tag] baseline-v0 set"
else
  echo "[warn] working tree dirty — not tagging; commit results then tag"
fi

echo "=== cascade end $(date -u) ==="
