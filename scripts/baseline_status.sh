#!/usr/bin/env bash
# At-a-glance status of baseline benchmarking. Read-only.

cd /Users/will/CS/2026/3806/Assignment2/llm-isabelle

OUT="datasets/results/baseline"
LOG="logs/baseline"

echo "===================================================="
echo " baseline benchmarking status  $(date '+%Y-%m-%d %H:%M:%S')"
echo "===================================================="

# ---- procs ----
echo
echo "ACTIVE PROCESSES:"
pgrep -fl "baseline_watcher" | awk '{printf "  watcher pid=%s\n", $1}'
pgrep -fl "sledge_only.py" | awk '{printf "  B0 sledge pid=%s\n", $1}'
pgrep -fl "prover.experiments bench" | awk '{printf "  B1 prover pid=%s\n", $1}'
pgrep -fl "planner.experiments bench" | awk '{printf "  B2 planner pid=%s\n", $1}'

# ---- artefact inventory ----
echo
echo "ARTEFACTS:"
printf "  sledge/   "; ls "$OUT/sledge/"   2>/dev/null | tr '\n' ' '; echo
printf "  prover/   "; ls "$OUT/prover/"   2>/dev/null | tr '\n' ' '; echo
printf "  planner/  "; ls "$OUT/planner/"  2>/dev/null | tr '\n' ' '; echo
printf "  master    "; ls "$OUT/"MASTER.* 2>/dev/null | xargs -n1 basename | tr '\n' ' '; echo

# ---- B0/B1/B2 per-tier checks ----
echo
echo "PIPELINE PROGRESS:"
for tier in smoke hol_easy hol_mid hol_hard minif2f; do
  case "$tier" in
    smoke)     b0_log="$OUT/sledge/smoke_lists.log"; b1_csv="$OUT/prover/lists.csv";        b2_csv="$OUT/planner/smoke_lists.csv" ;;
    hol_easy)  b0_log="$OUT/sledge/hol_easy_test.log";  b1_csv="$OUT/prover/hol_easy.csv";  b2_csv="$OUT/planner/hol_easy.csv" ;;
    hol_mid)   b0_log="$OUT/sledge/hol_mid_test.log";   b1_csv="$OUT/prover/hol_mid.csv";   b2_csv="$OUT/planner/hol_mid.csv" ;;
    hol_hard)  b0_log="$OUT/sledge/hol_hard_test.log";  b1_csv="$OUT/prover/hol_hard.csv";  b2_csv="$OUT/planner/hol_hard.csv" ;;
    minif2f)   b0_log="$OUT/sledge/minif2f_test.log";   b1_csv="$OUT/prover/minif2f_test.csv"; b2_csv="$OUT/planner/minif2f_test.csv" ;;
  esac

  b0_status="—"
  if grep -q "Summary" "$b0_log" 2>/dev/null; then
    b0_status="$(grep 'Success:' "$b0_log" | tail -1 | awk '{print $2}')"
  elif [[ -f "$b0_log" ]]; then
    n_ok="$(grep -c '^  -> OK' "$b0_log" 2>/dev/null)"
    n_fail="$(grep -c '^  -> FAIL' "$b0_log" 2>/dev/null)"
    n_total="$((n_ok + n_fail))"
    b0_status="running ${n_total}/? (${n_ok}ok/${n_fail}fail)"
  fi

  b1_status="—"
  [[ -s "$b1_csv" ]] && b1_status="done ($(($(wc -l <"$b1_csv") - 1)) rows)"

  b2_status="—"
  [[ -s "$b2_csv" ]] && b2_status="done ($(($(wc -l <"$b2_csv") - 1)) rows)"

  printf "  %-10s  B0=%-22s  B1=%-22s  B2=%-22s\n" "$tier" "$b0_status" "$b1_status" "$b2_status"
done

# ---- live tmp goal ----
echo
echo "LIVE STATE:"
tmp_thy="$(ls /var/folders/t5/j6r05lvs5452qx8c3tkqwn7c0000gn/T/sledge_only_*/SledgeOnly.thy 2>/dev/null | head -1)"
if [[ -n "$tmp_thy" ]]; then
  cur_goal="$(grep '^lemma' "$tmp_thy" 2>/dev/null | head -1 | sed 's/lemma "//; s/" *$//')"
  echo "  B0 current goal: $cur_goal"
fi

if [[ -f logs/planner.log.jsonl ]]; then
  jsonl_n=$(wc -l < logs/planner.log.jsonl)
  echo "  planner.log.jsonl lines: $jsonl_n"
fi

# ---- git tag check ----
echo
echo "GIT:"
echo "  HEAD: $(git rev-parse --short HEAD 2>/dev/null)"
echo "  tags: $(git tag -l 2>/dev/null | tr '\n' ' ')"

echo
echo "===================================================="
