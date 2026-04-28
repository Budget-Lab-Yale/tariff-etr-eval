# Diagnostic Refresh Plan — consolidating tracker checking in `tariff-etr-eval`

**Date**: 2026-04-28
**Status**: draft for review
**Goal**: consolidate the cross-repo tracker checking workflow into this repo so analysis, benchmarks, and refresh orchestration live alongside the four-tier ETR decomposition.

## Why

Today the tracker checking machinery is split across two repos:

| Function | Lives in | Notes |
|---|---|---|
| Rate engine | `tariff-rate-tracker/src/06_calculate_rates.R` | Owns the truth — must stay there. |
| Annex II / product-list config | `tariff-rate-tracker/resources/*.csv` | Owns the truth. |
| Trackermiss / trackerover diagnostics | `tariff-etr-eval/code/05a_*.do`, `05b_*.do` | Already here. |
| TPC benchmark comparison | `tariff-rate-tracker/tests/test_tpc_comparison.R` | Should move — it's a comparison artifact, not a rate-engine artifact. |
| Tariff-ETRs benchmark comparison | `tariff-rate-tracker/src/compare_etrs.R` | Should move — same reason. |
| Internal validation hooks | `tariff-rate-tracker/src/07_validate_tpc.R` | Stays — runs during build for sanity. |
| Audit / handoff write-ups | `tariff-rate-tracker/docs/ieepa_exempt_audit_*.md`, `tariff-etr-eval/docs/tracker_*_report.md` | Mixed today; should consolidate in this repo. |
| Refresh orchestrator | (does not exist) | New, lives here. |

The pattern: the *rate engine* (and the things it directly needs to compute correctly) stays in the tracker. *Comparing the rate engine against external truth* (Census IMDB, TPC, Tariff-ETRs) moves here.

## Target structure (in this repo)

```
tariff-etr-eval/
├── code/
│   ├── 00_etr_eval.do                    # existing orchestrator
│   ├── 01_etr_clean.do                   # existing
│   ├── 02_etr_analysis.do                # existing
│   ├── 03_fta_decomposition.do           # existing
│   ├── 04_max_district_crosscheck.do     # existing
│   ├── 05_counterfactual_ladder.do       # existing
│   ├── 05a_tracker_miss_diagnostic.do    # existing
│   ├── 05b_tracker_over_diagnostic.do    # existing
│   ├── 06_baseline_etr_diagnostic.do     # existing
│   ├── 07_compare_tpc.R                  # NEW — moved from tracker/tests
│   ├── 08_compare_tariff_etrs.R          # NEW — moved from tracker/src
│   ├── 09_diagnostic_refresh.do          # NEW — orchestrator for periodic refresh
│   ├── R/
│   │   └── 00_pull_raw_data.R            # existing — extend with tracker-rebuild option
│   └── utils/
│       ├── globals.do                    # existing
│       └── programs.do                   # existing — add diagnostic helper programs
├── docs/
│   ├── tracker_miss_report.md            # existing
│   ├── tracker_over_report.md            # existing
│   ├── diagnostic_refresh_plan.md        # this file
│   ├── diagnostic_refresh_runbook.md     # NEW — operator guide
│   └── tracker_audits/                   # NEW — relocated audit memos
│       └── ieepa_exempt_audit_2026-04-28.md
├── results/
│   ├── figures/                          # existing
│   ├── tables/                           # existing — diagnostic CSVs
│   └── benchmarks/                       # NEW — TPC + Tariff-ETRs comparison outputs
└── data/
    ├── raw/                              # existing
    └── benchmarks/                       # NEW — cached TPC + Tariff-ETRs benchmark inputs
        ├── tpc/tariff_by_flow_day.csv
        └── tariff_etrs/levels_by_census_country.csv
```

The benchmark CSVs are *inputs* to comparisons we own here — duplicating them locally avoids hardcoded `../tariff-rate-tracker/...` paths and keeps the eval repo self-contained for analysis. They refresh on the same cadence as the rest of the diagnostic.

## Component-by-component migration

### 1. TPC benchmark comparison

**From**: `tariff-rate-tracker/tests/test_tpc_comparison.R`
**To**: `tariff-etr-eval/code/07_compare_tpc.R`

Refactor:

- Reads `data/benchmarks/tpc/tariff_by_flow_day.csv` (local copy).
- Reads tracker rate snapshots from `../tariff-rate-tracker/data/timeseries/snapshot_<rev>.rds` via `local_paths.yaml`.
- No longer recomputes rates per revision (current TPC test re-parses HTS JSON each time, which is slow). Reads pre-built snapshots instead — a 5-revision comparison drops from ~15 min to ~30 s.
- Emits comparison CSVs to `results/benchmarks/tpc/`.

The tracker keeps `src/07_validate_tpc.R` for in-build sanity checks (small, fast, asserts on a known-good revision). The full 5-revision benchmark moves here.

### 2. Tariff-ETRs benchmark comparison

**From**: `tariff-rate-tracker/src/compare_etrs.R`
**To**: `tariff-etr-eval/code/08_compare_tariff_etrs.R`

Same shape: reads tracker snapshots + locally-cached `levels_by_census_country.csv`, emits to `results/benchmarks/tariff_etrs/`.

### 3. Audit memos

Audit / handoff write-ups belong with the analyst who reasons about discrepancies — i.e., here. Relocate:

- `tariff-rate-tracker/docs/ieepa_exempt_audit_2026-04-28.md` → `tariff-etr-eval/docs/tracker_audits/ieepa_exempt_audit_2026-04-28.md`
- (future) any new tracker audit memos likewise

The tracker keeps **operational** docs (`methodology.md`, `policy_timing.md`, etc.). It does not keep retrospective audit memos.

### 4. Refresh orchestrator (NEW)

**File**: `tariff-etr-eval/code/09_diagnostic_refresh.do`

Drives the end-to-end refresh whenever new Census IMDB data lands. Mostly composition of existing scripts:

```stata
* 09_diagnostic_refresh.do — periodic tracker-vs-Census refresh

include "code/utils/globals.do"

* 1. Pull fresh inputs (R-side; idempotent — skips if already current)
shell Rscript code/R/00_pull_raw_data.R --skip-tracker
shell Rscript code/R/00_pull_raw_data.R --only-tracker  // refresh tracker outputs

* 2. Optionally trigger a tracker rebuild if a new HTS revision was released
*    (controlled via $auto_rebuild_tracker global; default 0 — manual oversight)

* 3. Rebuild merged_analysis.dta
do code/01_etr_clean.do

* 4. Re-run diagnostics
do code/05a_tracker_miss_diagnostic.do
do code/05b_tracker_over_diagnostic.do

* 5. Re-run benchmark comparisons
shell Rscript code/07_compare_tpc.R
shell Rscript code/08_compare_tariff_etrs.R

* 6. Emit delta report — new/resolved cells, total $ trend, threshold alerts
do code/utils/diagnostic_delta.do
```

### 5. Delta report

**File**: `tariff-etr-eval/code/utils/diagnostic_delta.do` (program), `results/benchmarks/delta_<YYYY-MM-DD>.md` (output)

For each diagnostic CSV (`tracker_miss_*.csv`, `tracker_over_*.csv`, `etrs_comparison_*.csv`, `tpc_*.csv`):

- Compare against the prior run (cached in `results/benchmarks/_history/`).
- Emit:
  - **New cells** entering top-200 BUG-LIKELY (most actionable — signals new tracker errors).
  - **Resolved cells** dropping out (signals fixes landed — sanity-check).
  - **Total $ trend**: trackermiss total, trackerover BUG-LIKELY total, ETRs gap (3 dates), TPC match rates (5 revisions). One-line metric per axis.
  - **Threshold alerts**: e.g., > $500 M new BUG-LIKELY in a single month, > 2 pp drop in TPC within-2pp match rate.
- Persist current run to `_history/<YYYY-MM-DD>/` for next-cycle comparison.

The delta report is a Markdown summary, ~1 page, suitable for routine review without re-reading the full diagnostic outputs.

### 6. Trigger / scheduling

**Phase 1 (manual)**: operator runs `do code/09_diagnostic_refresh.do` after each Census IMDB release. Documented in `docs/diagnostic_refresh_runbook.md`.

**Phase 2 (semi-automated)**: cron / scheduled task on a workstation, or a `/schedule` agent, fires weekly through the typical Census release window (1st-7th of each month). Idempotent: skips if no new IMDB month since last run.

**Phase 3 (CI)**: GitHub Actions workflow on this repo that runs the diagnostic and posts the delta report as an issue or commit comment. Requires the tracker repo to be available either as a submodule or a stable artifact location.

We start at Phase 1 — the orchestrator + delta report alone solves the "bouncing back and forth" problem. Phase 2/3 is opportunistic.

## What stays in `tariff-rate-tracker`

| Component | Reason |
|---|---|
| `src/06_calculate_rates.R` | Rate engine |
| `src/07_validate_tpc.R` | In-build assertion (fast, small) — separate from the full TPC comparison |
| `src/expand_ieepa_exempt.R` | Generates a tracker config file from tracker source data |
| `resources/*.csv` (exempt lists, product lists) | Rate-engine inputs |
| `docs/methodology.md`, `policy_timing.md`, `architecture.md`, `assumptions.md` | Operational tracker documentation |
| `data/timeseries/` outputs | Rate engine outputs (eval reads these) |

The tracker remains the source of truth for *what the tariff structure is*. The eval repo owns *whether the tracker matches reality*.

## Read interface from eval to tracker

The eval repo accesses tracker outputs via these stable artifacts (no internal tracker imports):

- `tariff-rate-tracker/data/timeseries/rate_timeseries.rds` — primary, long-format rates
- `tariff-rate-tracker/data/timeseries/snapshot_<rev>.rds` — per-revision snapshot
- `tariff-rate-tracker/data/timeseries/usmca_monthly/*.rds` — monthly USMCA-adjusted scenarios
- `tariff-rate-tracker/data/timeseries/daily_by_country.csv` — daily ETR by country
- `tariff-rate-tracker/config/revision_dates.csv` — revision → policy-date mapping

Path resolution lives in `config/local_paths.yaml` (already exists, currently has `tariff_etrs_repo`; extend with `tariff_rate_tracker_repo`).

## Findings → tracker fixes loop

Audits performed here produce fixes applied there. The hand-off is:

1. Audit memo authored in `tariff-etr-eval/docs/tracker_audits/<name>.md`.
2. Memo includes: literal source authority (EO text / HTSUS Note / proclamation), expected behavior, concrete diff against tracker resources or code.
3. Patch applied to tracker repo with a commit message linking the memo URL.
4. Eval refresh re-runs to verify the fix landed and quantify the residual.

The trackermiss Round 1/2/3 + Round 3 audit doc + this Round audit (post-fix) is the canonical example of this loop.

## Migration order

| Step | Action | Effort |
|---|---|---|
| **1** | Add `tariff_rate_tracker_repo` to `config/local_paths.yaml`; resolve from there in existing R/Stata scripts. | small |
| **2** | Copy `data/tpc/tariff_by_flow_day.csv` and `Tariff-ETRs/output/2-21_temp/levels_by_census_country.csv` into `data/benchmarks/`. Update consumers. | small |
| **3** | Port `test_tpc_comparison.R` → `code/07_compare_tpc.R`. Refactor to read snapshots instead of re-parsing HTS JSON. | medium |
| **4** | Port `compare_etrs.R` → `code/08_compare_tariff_etrs.R`. Same refactor. | medium |
| **5** | Move audit memos under `docs/tracker_audits/`. Update cross-references. | small |
| **6** | Write `code/utils/diagnostic_delta.do` + first-run baseline cache. | medium |
| **7** | Write `code/09_diagnostic_refresh.do` orchestrator. | small |
| **8** | Author `docs/diagnostic_refresh_runbook.md` (manual operator guide). | small |
| **9** | Phase 2: schedule a weekly cron / `/schedule` agent. | small (deferred) |

Steps 1–5 are mechanical relocations. Steps 6–7 are the actual new capability. Step 8 documents it. Steps 1–8 should be doable in a focused day; Step 9 is a separate session once Phase 1 has been exercised once or twice.

## Open questions

- **Tracker rebuild trigger**: when a new HTS revision lands, should the eval orchestrator auto-trigger a tracker rebuild, or page the operator? Probably page-the-operator initially — tracker rebuilds occasionally need policy curation (revision dates, new authorities) that benefits from human review. Documented in the runbook.
- **`expand_ieepa_exempt.R` ownership**: the script lives in tracker, but its inputs are governed by audit memos owned here. We could move the script too, but it operates on `data/processed/products_*.rds` which is a tracker artifact. Cleaner to leave the script in tracker and document the audit-driven update procedure in `docs/diagnostic_refresh_runbook.md`.
- **Benchmark-data refresh cadence**: TPC and Tariff-ETRs publish on their own schedules. Local copies in `data/benchmarks/` should be refreshed *before* a comparison run, with a manifest noting source-repo version / date.

## Non-goals

- Reimplementing the rate engine here. The tracker is the single source of truth for rates.
- Forking the audit ownership. Audits are authored in this repo; tracker remains a downstream consumer of audit-derived patches.
- Real-time alerting. Monthly cadence aligned with IMDB release is plenty.
