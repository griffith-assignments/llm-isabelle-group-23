#!/usr/bin/env bash
# Run baseline (B0 sledge, B1 prover, B2 planner) on mini_f2f_test (244 goals).
# Requires MiniF2F_Base session built (needs AFP Symmetric_Polynomials entry).
#
# Prereq:
#   isabelle components -u external/afp/thys     # one-time
#   isabelle build -d datasets/mini_f2f -v MiniF2F_Base
#
# Tier: miniF2F == hard (200s, beam 5, depth 10, facts 8) per issue #2.

set -uo pipefail

cd "$(dirname "$0")/.."

: "${GEMINI_API_KEY:?GEMINI_API_KEY not exported.}"

source .venv/bin/activate

export PATH="/Applications/Isabelle2025.app/bin:$PATH"

MODEL="gemini:gemini-3-flash-preview"
SEED=42
TIMEOUT=200
BEAM=5
DEPTH=10
FACTS=8
SLEDGE_PROVERS="e z3 vampire cvc5"

OUT_BASE="datasets/results/baseline"
LOG_BASE="logs/baseline"
mkdir -p "$OUT_BASE"/{sledge,prover,planner} "$LOG_BASE"

goalfile="datasets/mini_f2f/mini_f2f_test.txt"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

# Use MiniF2F_Base if built. Falls back to HOL Main if not (some goals fail).
if isabelle build -d datasets/mini_f2f -n MiniF2F_Base >/dev/null 2>&1; then
  export ISABELLE_LOGIC=MiniF2F_Base
  IMPORTS="MiniF2F_Base"
  echo "[ok] using MiniF2F_Base session"
else
  IMPORTS="Main"
  echo "[warn] MiniF2F_Base not built — using Main, expect typecheck failures"
fi

echo "=== miniF2F test ($(date -u)) goals=$(wc -l <"$goalfile") imports=$IMPORTS ==="

# B0 sledge-only --------------------------------------------------------------
echo "--- B0 sledge-only ---"
python baselines/sledge_only.py \
  --file "$goalfile" --imports "$IMPORTS" \
  --provers "$SLEDGE_PROVERS" \
  --sledge-timeout 60 --goal-timeout 230 \
  --print-logs \
  > "$OUT_BASE/sledge/minif2f_test.log" 2>&1
echo "  -> $OUT_BASE/sledge/minif2f_test.log"

# B1 prover bench -------------------------------------------------------------
echo "--- B1 prover bench ---"
python -m prover.experiments bench \
  --file "$goalfile" \
  --beam "$BEAM" --max-depth "$DEPTH" --timeout "$TIMEOUT" \
  --facts-limit "$FACTS" --quickcheck --nitpick --sledge --variants \
  --no-minimize --model "$MODEL" \
  --shuffle --seed "$SEED" \
  > "$LOG_BASE/${stamp}_prover_minif2f.log" 2>&1
latest_p="$(ls -t datasets/results/*.csv 2>/dev/null | head -1)"
if [[ -n "$latest_p" && "$latest_p" != "$OUT_BASE/prover/"* ]]; then
  mv "$latest_p" "$OUT_BASE/prover/minif2f_test.csv"
fi
echo "  -> $OUT_BASE/prover/minif2f_test.csv"

# B2 planner bench ------------------------------------------------------------
echo "--- B2 planner bench ---"
python -m planner.experiments bench \
  --file "$goalfile" \
  --mode auto --diverse --k 3 --temps "0.35,0.55,0.85" \
  --timeout "$TIMEOUT" --strict-no-sorry --verify \
  --model "$MODEL" \
  --shuffle --seed "$SEED" \
  > "$LOG_BASE/${stamp}_planner_minif2f.log" 2>&1
latest_pl="$(ls -t datasets/planner_results/*.csv 2>/dev/null | head -1)"
if [[ -n "$latest_pl" && "$latest_pl" != "$OUT_BASE/planner/"* ]]; then
  mv "$latest_pl" "$OUT_BASE/planner/minif2f_test.csv"
fi
echo "  -> $OUT_BASE/planner/minif2f_test.csv"

echo "=== miniF2F test done ($(date -u)) ==="
