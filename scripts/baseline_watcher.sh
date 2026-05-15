#!/usr/bin/env bash
# Baseline benchmarking watcher — autonomous cascade.
#
# Polls every 60s. Launches next pending bench when a slot opens.
# Max 2 concurrent Isabelle-heavy processes (RAM-bound).
#
# Phase order:
#   1. B2 smoke (lists) — wait if running
#   2. B0 sledge HOL {easy, mid, hard} — serial
#   3. B1 prover HOL {easy, mid, hard} — serial (separate from B0)
#   4. B2 planner HOL {easy, mid, hard} — serial
#   5. Aggregate + tag baseline-v0
#
# Use:
#   nohup bash scripts/baseline_watcher.sh > logs/baseline/watcher.log 2>&1 &

set -o pipefail
cd /Users/will/CS/2026/3806/Assignment2/llm-isabelle

# Source zshrc only if it doesn't break under bash; fall back to direct key read
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  GEMINI_API_KEY="$(grep '^export GEMINI_API_KEY' ~/.zshrc 2>/dev/null | head -1 | sed -E 's/.*=//' | tr -d '"' | tr -d "'")"
  export GEMINI_API_KEY
fi
source .venv/bin/activate
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "[watcher] FATAL: GEMINI_API_KEY missing" >&2
  exit 1
fi
export PATH="/Applications/Isabelle2025-2.app/bin:$PATH"
export PYTHONUNBUFFERED=1

OUT="datasets/results/baseline"
LOG="logs/baseline"
mkdir -p "$OUT"/{sledge,prover,planner} "$LOG"

MODEL="gemini:gemini-3-flash-preview"
SEED=42
SLEDGE_PROVERS="e z3 vampire cvc5"

# Tier params (bash 3.2 — no assoc arrays)
tier_to() { case "$1" in easy) echo 60;; mid) echo 120;; hard) echo 200;; esac; }
tier_bm() { case "$1" in easy) echo 3;;  mid) echo 4;;   hard) echo 5;;  esac; }
tier_dp() { case "$1" in easy) echo 6;;  mid) echo 8;;   hard) echo 10;; esac; }
tier_fl() { case "$1" in easy) echo 6;;  mid) echo 6;;   hard) echo 8;;  esac; }

log() { echo "[watcher $(date '+%H:%M:%S')] $*"; }

# Number of heavy bench processes currently running
running_count() {
  local n=0
  pgrep -fl "planner.experiments bench" >/dev/null 2>&1 && n=$((n+1))
  pgrep -fl "prover.experiments bench" >/dev/null 2>&1 && n=$((n+1))
  pgrep -fl "sledge_only.py" >/dev/null 2>&1 && n=$((n+1))
  echo $n
}

# Pipeline X tier done check
b0_done() { local t="$1"; grep -q "Summary" "$OUT/sledge/hol_${t}_test.log" 2>/dev/null; }
b1_done() { local t="$1"; [[ -s "$OUT/prover/hol_${t}.csv" ]]; }
b2_done() { local t="$1"; [[ -s "$OUT/planner/hol_${t}.csv" ]]; }
b2_smoke_done() { [[ -s "$OUT/planner/smoke_lists.csv" ]]; }

# Move latest non-baseline prover CSV into target
mv_prover_csv() {
  local target="$1"
  local latest
  latest="$(find datasets/results -maxdepth 1 -name '*.csv' -type f 2>/dev/null | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -1 | awk '{print $2}')"
  if [[ -n "$latest" && -f "$latest" ]]; then
    mv "$latest" "$target"
    log "moved $latest -> $target"
  fi
}
mv_planner_csv() {
  local target="$1"
  local latest
  latest="$(find datasets/planner_results -maxdepth 1 -name '*.csv' -type f 2>/dev/null | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -1 | awk '{print $2}')"
  if [[ -n "$latest" && -f "$latest" ]]; then
    mv "$latest" "$target"
    log "moved $latest -> $target"
  fi
}

launch_b0() {
  local t="$1"
  local to=$(tier_to "$t")
  if pgrep -fl "sledge_only.py" >/dev/null 2>&1; then return 1; fi
  log "launching B0 sledge HOL $t"
  # B0 sledge_only.py needs Isabelle2025 (2025-2 removed `isabelle process`)
  PATH="/Applications/Isabelle2025.app/bin:$PATH" \
    nohup python baselines/sledge_only.py \
    --file "datasets/hol_main_${t}_goals_test.txt" --imports Main \
    --provers "$SLEDGE_PROVERS" \
    --sledge-timeout 60 --goal-timeout "$((to + 30))" \
    --print-logs > "$OUT/sledge/hol_${t}_test.log" 2>&1 &
  log "B0 $t pid=$!"
  return 0
}

launch_b1() {
  local t="$1"
  local to=$(tier_to "$t")
  local bm=$(tier_bm "$t")
  local dp=$(tier_dp "$t")
  local fl=$(tier_fl "$t")
  if pgrep -fl "prover.experiments bench" >/dev/null 2>&1; then return 1; fi
  log "launching B1 prover HOL $t"
  nohup python -m prover.experiments bench \
    --file "datasets/hol_main_${t}_goals_test.txt" \
    --beam "$bm" --max-depth "$dp" --timeout "$to" \
    --facts-limit "$fl" --quickcheck --nitpick --sledge --variants \
    --no-minimize --model "$MODEL" \
    --shuffle --seed "$SEED" \
    > "$LOG/prover_hol_${t}.log" 2>&1 &
  log "B1 $t pid=$!"
  return 0
}

launch_b2() {
  local t="$1"
  local to=$(tier_to "$t")
  if pgrep -fl "planner.experiments bench" >/dev/null 2>&1; then return 1; fi
  log "launching B2 planner HOL $t"
  nohup python -m planner.experiments bench \
    --file "datasets/hol_main_${t}_goals_test.txt" \
    --mode auto --diverse --k 3 --temps "0.35,0.55,0.85" \
    --timeout "$to" --strict-no-sorry --verify \
    --model "$MODEL" \
    --shuffle --seed "$SEED" \
    > "$LOG/planner_hol_${t}.log" 2>&1 &
  log "B2 $t pid=$!"
  return 0
}

# Cleanup post-launch — find new CSVs and move them
sweep_results() {
  for t in easy mid hard; do
    if b0_done "$t" && [[ "$(tail -1 "$OUT/sledge/hol_${t}_test.log" 2>/dev/null)" == "===" ]]; then
      : # already in place
    fi
    if ! b1_done "$t" && grep -q "CSV →" "$LOG/prover_hol_${t}.log" 2>/dev/null; then
      mv_prover_csv "$OUT/prover/hol_${t}.csv"
    fi
    if ! b2_done "$t" && grep -q "CSV →\|=== Bench" "$LOG/planner_hol_${t}.log" 2>/dev/null; then
      mv_planner_csv "$OUT/planner/hol_${t}.csv"
    fi
  done

  # smoke
  if ! b2_smoke_done && [[ -f logs/planner.log.jsonl ]]; then
    local lines; lines="$(wc -l < logs/planner.log.jsonl 2>/dev/null || echo 0)"
    if [[ "$lines" -ge 22 ]] && ! pgrep -fl "planner.experiments bench.*lists.txt" >/dev/null 2>&1; then
      mv_planner_csv "$OUT/planner/smoke_lists.csv"
    fi
  fi
}

# Determine next thing to launch
next_action() {
  sweep_results

  # B0 cascade: easy → mid → hard
  for t in easy mid hard; do
    if ! b0_done "$t" && ! pgrep -fl "sledge_only.py.*${t}_goals_test" >/dev/null 2>&1; then
      launch_b0 "$t" && return 0
      break
    fi
  done

  # B1 cascade after B0 tier done
  for t in easy mid hard; do
    if b0_done "$t" && ! b1_done "$t" && ! pgrep -fl "prover.experiments.*${t}_goals_test" >/dev/null 2>&1; then
      launch_b1 "$t" && return 0
      break
    fi
  done

  # B2 cascade: only after smoke done + all B0/B1 done (quota concern)
  if b2_smoke_done && b0_done easy && b0_done mid && b0_done hard \
                   && b1_done easy && b1_done mid && b1_done hard; then
    for t in easy mid hard; do
      if ! b2_done "$t" && ! pgrep -fl "planner.experiments.*${t}_goals_test" >/dev/null 2>&1; then
        launch_b2 "$t" && return 0
        break
      fi
    done
  fi

  return 1
}

all_done() {
  b2_smoke_done && \
  b0_done easy && b0_done mid && b0_done hard && \
  b1_done easy && b1_done mid && b1_done hard && \
  b2_done easy && b2_done mid && b2_done hard
}

log "=== watcher start ==="

while true; do
  if all_done; then
    log "all phases done — aggregating + tagging"
    python scripts/make_master_table.py
    if git diff --quiet HEAD 2>/dev/null && [[ -z "$(git status --porcelain)" ]]; then
      git tag -f baseline-v0 && log "tagged baseline-v0" || log "tag failed"
    else
      log "working tree dirty, skipping tag"
    fi
    log "=== watcher complete ==="
    break
  fi

  if [[ "$(running_count)" -lt 2 ]]; then
    if ! next_action; then
      log "nothing to launch but not all done — likely blocked by B2 ordering (waiting B0+B1 cascade)"
    fi
  fi
  sleep 60
done
