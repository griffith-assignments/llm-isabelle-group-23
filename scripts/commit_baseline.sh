#!/usr/bin/env bash
# Commit baseline benchmarking results + tag baseline-v0.
# Run only when ALL 9 HOL files + smoke + MASTER.csv are present.

set -euo pipefail
cd /Users/will/CS/2026/3806/Assignment2/llm-isabelle

# ---- Preflight: verify all required artefacts exist ----
required=(
  "datasets/results/baseline/ENV.txt"
  "datasets/results/baseline/REPORT-NOTES.md"
  "datasets/results/baseline/MASTER.csv"
  "datasets/results/baseline/MASTER.tex"

  "datasets/results/baseline/sledge/smoke_lists.log"
  "datasets/results/baseline/sledge/smoke_logic.log"
  "datasets/results/baseline/sledge/smoke_nat.log"
  "datasets/results/baseline/sledge/smoke_sets.log"
  "datasets/results/baseline/sledge/hol_easy_test.log"
  "datasets/results/baseline/sledge/hol_mid_test.log"
  "datasets/results/baseline/sledge/hol_hard_test.log"

  "datasets/results/baseline/prover/lists.csv"
  "datasets/results/baseline/prover/hol_easy.csv"
  "datasets/results/baseline/prover/hol_mid.csv"
  "datasets/results/baseline/prover/hol_hard.csv"

  "datasets/results/baseline/planner/smoke_lists.csv"
  "datasets/results/baseline/planner/hol_easy.csv"
  "datasets/results/baseline/planner/hol_mid.csv"
  "datasets/results/baseline/planner/hol_hard.csv"
)

missing=()
for f in "${required[@]}"; do
  [[ -s "$f" ]] || missing+=("$f")
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "[fail] missing required artefacts:"
  printf '  %s\n' "${missing[@]}"
  echo
  echo "Run \`bash scripts/baseline_status.sh\` for current state."
  exit 1
fi

# ---- Re-aggregate to ensure MASTER is current ----
python scripts/make_master_table.py

# ---- Stage and commit ----
git add datasets/results/baseline/ \
        scripts/ \
        logs/baseline/ 2>/dev/null || true

if git diff --cached --quiet; then
  echo "[info] no staged changes; assuming results already committed"
else
  git commit -m "$(cat <<'EOF'
baseline: complete B0/B1/B2 × smoke/HOL benchmarking

Phase C–F of issue #2. Includes:
- B0 sledge-only on smoke (logic/sets/nat/lists) + HOL easy/mid/hard test
- B1 prover bench on lists smoke + HOL easy/mid/hard test
- B2 planner bench on lists smoke + HOL easy/mid/hard test
- Aggregated MASTER.csv + MASTER.tex
- Watcher + status scripts

Pinned config:
- model: gemini:gemini-3-flash-preview
- seed: 42
- ATPs: e z3 vampire cvc5
- Isabelle: 2025 (B0), 2025-2 (B1/B2)
- isabelle-client: 1.0.2

miniF2F deferred (AFP installed but session build not run).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
fi

# ---- Tag ----
git tag -f baseline-v0
echo "[ok] tagged baseline-v0"

echo
echo "=== Summary ==="
python scripts/make_master_table.py 2>&1 | tail -5
echo
echo "Push when ready:  git push origin main && git push origin baseline-v0"
