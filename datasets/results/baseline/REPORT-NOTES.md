# Baseline benchmarking notes — for report

Generated during baseline benchmarking run (Phase C–F of issue #2).

## Pinned configuration

| Knob | Value |
|---|---|
| Backend | `gemini:gemini-3-flash-preview` |
| Seed | `42` |
| Sledgehammer ATPs (B0) | `e z3 vampire cvc5` |
| B0 sledge-timeout | 60s |
| B1 internal sledge-timeout | repo default 10s (not patched) |
| B2 outline diversity | k=3, temps `0.35,0.55,0.85` |
| B2 strict/verify | `--strict-no-sorry --verify` |
| Isabelle (B0) | Isabelle2025 (sledge works) |
| Isabelle (B1/B2) | Isabelle2025-2 (server API) |
| isabelle-client | 1.0.2 (pinned, pre-Pydantic) |

## Tier budgets

| Tier | Timeout | Beam (B1) | Max-depth (B1) | Facts-limit (B1) |
|---|---|---|---|---|
| smoke | 30s | 3 | 6 | 6 |
| easy | 60s | 3 | 6 | 6 |
| mid | 120s | 4 | 8 | 6 |
| hard / miniF2F | 200s | 5 | 10 | 8 |

## Datasets

| File | n | Tier | Use |
|---|---|---|---|
| `lists.txt` | 18 | smoke | sanity |
| `logic.txt` | 5 | smoke | sanity |
| `nat.txt` | 9 | smoke | sanity |
| `sets.txt` | 8 | smoke | sanity |
| `hol_main_easy_goals_test.txt` | 100 | easy | held-out |
| `hol_main_mid_goals_test.txt` | 100 | mid | held-out |
| `hol_main_hard_goals_test.txt` | 100 | hard | held-out |
| `mini_f2f/mini_f2f_test.txt` | 244 | external | requires MiniF2F_Base session (AFP `Symmetric_Polynomials`) |

## Findings to highlight in report

### 1. Out-of-the-box infra bugs we fixed (env-only, not algorithmic)
- isabelle-client 1.1.0+ changed `session_start` return shape to Pydantic list — breaks `prover/cli.py`, `prover/isabelle_api.py`, `prover/experiments.py`. Pinned to 1.0.2.
- Isabelle2025-2 changed sledge plumbing (`isabelle process` removed, build_log SQLite schema change) — `baselines/sledge_only.py` broken. Pinned B0 path to Isabelle2025.
- These are environment compat fixes, NOT algorithmic changes. Baseline remains "as-is".

### 2. Smoke-suite signal (toys)
Sledge-only on toy goals:
- `logic` (5/5): 100% — trivial propositional
- `sets` (8/8): 100% — set algebra
- `nat` (4/9): 44% — fails on commutativity / associativity (needs induction)
- `lists` (17/18): 94% — fails 1 hard map-filter goal

This already tells us: **sledgehammer alone closes ~70%+ of toy goals**. The remaining ~30% require induction/structure — that's where LLM guidance helps.

### 3. Baseline planner Fill/Repair is broken (expected, WIP)
From `logs/planner.log.jsonl` smoke run:
- Goal 1 (`x ∈ set xs ⟹ x ∈ set (xs @ ys)`): outline produced 379 chars, contains `sorry`, Fill did not close it, strict-no-sorry → fail.
- Same pattern through goals 2–7: `success=False, had_sorry=True, verified_ok=True`.

This confirms the assignment-spec gap: **Fill currently extracts subgoals at `sorry` but the stepwise prover call returns nothing usable**, so the outline stays unfilled. Our Tier S #1 task closes this.

## Comparison framework for "ours vs baseline"

After improvements land, re-run each variant with same flags + dataset to populate:

| Variant | Fill | Repair | Pool | RAG | Pass% (easy/mid/hard) |
|---|---|---|---|---|---|
| baseline-as-is | broken | broken | no | micro | tbd / tbd / tbd |
| ours-fill | ✓ | broken | no | micro | tbd / tbd / tbd |
| ours-fill+repair | ✓ | ✓ | no | micro | tbd / tbd / tbd |
| ours-+pool | ✓ | ✓ | ✓ | micro | tbd / tbd / tbd |
| ours-+RAG | ✓ | ✓ | ✓ | vector | tbd / tbd / tbd |
| ours-full | ✓ | ✓ | ✓ | vector+rerank | tbd / tbd / tbd |

McNemar test (paired) vs baseline for each variant. Bootstrap 95% CI on pass rate.

## File locations after run

```
datasets/results/baseline/
├── ENV.txt
├── REPORT-NOTES.md            <- this file
├── MASTER.csv                 <- aggregate
├── MASTER.tex                 <- LaTeX table
├── sledge/
│   ├── smoke_{logic,sets,nat,lists}.log
│   ├── hol_{easy,mid,hard}_test.log
│   └── minif2f_test.log       (optional)
├── prover/
│   ├── lists.csv (smoke)
│   ├── hol_{easy,mid,hard}.csv
│   └── minif2f_test.csv       (optional)
└── planner/
    ├── smoke_lists.csv
    ├── hol_{easy,mid,hard}.csv
    └── minif2f_test.csv       (optional)
```

## miniF2F status

AFP downloaded (`external/afp.tar.gz`, 96MB compressed). To enable miniF2F:
1. Unpack: `tar xzf external/afp.tar.gz -C external/`
2. Register: `isabelle components -u external/afp-*/thys`
3. Build session: `isabelle build -d datasets/mini_f2f -v MiniF2F_Base` (~30min one-time)
4. Then run `scripts/run_baseline_minif2f.sh`

If not enabled by deadline: document as future work, validate against HOL tiers only.

## Smoke baseline numbers (final)

Computed after Phase C complete (2026-05-15 23:34):

| Pipeline | Suite | n | Pass | Pass% | Median (s) |
|---|---|---|---|---|---|
| B0 sledge | logic | 5 | 5 | 100.0% | 8.84 |
| B0 sledge | sets | 8 | 8 | 100.0% | 9.25 |
| B0 sledge | nat | 9 | 4 | 44.4% | 22.80 |
| B0 sledge | lists | 18 | 17 | 94.4% | 9.18 |
| B1 prover | lists | 18 | 10 | 55.6% | 28.29 |
| B2 planner | lists | 18 | **2** | **11.1%** | 120.53 |

**Headline finding**: baseline planner (B2) is **dramatically worse than sledge-only** (B0) on lists smoke. B2 hits 2/18 vs B0's 17/18.

Cause confirmed from CSV:
- 16/18 outlines contained `sorry` (had_sorry=True)
- `fills=0` and `failed_holes=0` across all goals → Fill code is NOT EVEN ATTEMPTING to close the `sorry`s

The 2 B2 passes were both outline-only (had_sorry=False): `xs @ [] = xs` and `drop (length xs) (xs @ ys) = ys`. Trivial enough that LLM produced complete proof without holes.

This is the assignment-graded WIP gap. Tier S #1 (Fix Fill) is the dominant lever — closing those 16 holes lifts B2 from 11% → potentially ~89% on lists alone.

## Sledge-timeout asymmetry caveat (for report Experiment Setup)

B0 uses `--sledge-timeout 60`. B1 uses repo-default `sledge_timeout=10` internal to prover.experiments. Pinned, not patched — these methods measure different things:
- B0 = "what can a 60-second sledge close?" → upper bound on sledge alone
- B1 = "what can a 10-second sledge + LLM-guided tactics close in 60s budget?" → realistic mid-call use

Document side-by-side. Don't claim B0 vs B1 head-to-head — they're different "compute budgets".
