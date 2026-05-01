# Tariff ETR Evaluation

Comparing actual vs. statutory effective tariff rates during the 2025-2026 US tariff escalation.

## Overview

This project evaluates the gap between **statutory** tariff rates (what the Harmonized Tariff Schedule says importers should pay) and **actual** collection rates (customs duties actually collected as a share of import value). The gap is decomposed into USMCA adjustment, trade diversion, all-other preferences, residual, and timing/enforcement channels using a **six-tier framework** (S0 → S1 → S2 → S3 → S4 → T). See the "Six-tier framework" section in `CLAUDE.md` for the canonical math (tier definitions, channel directions, per-authority applicability).

## Pipeline

The pipeline has two stages: R assembles raw data from external APIs and sibling repos; Stata cleans, merges, and runs all analysis.

| Step | Script | What |
|------|--------|------|
| 0 | `code/R/00_pull_raw_data.R` | IMDB bulk (HS10 detail), tracker snapshots (incl.\ `total_rate` ≡ `rate_h2avg`), Treasury revenue, USMCA + non-USMCA preference share files (Census HS2 API opt-in via `--with-census`) |
| 1 | `code/01_etr_clean.do` | Import CSVs, clean, merge Census × tracker at HS10 × country × month; carry the three counterfactual rate panels (`rate_2024` for S0, `rate_h2avg` for S1/S2 — the framework anchor — and `rate_all_pref` for S3) onto `merged_analysis.dta` |
| 2 | `code/02_counterfactual_ladder.do` | Six-tier waterfall (S0→S1→S2→S3, joined to T) — canonical tier values |
| 3 | `code/03_etr_analysis.do` + `code/03b_baseline_figures.do` | 03: six-tier ETR decomposition + ladder/channel figures + S1→S2 trade-diversion Shapley decomp (country and product partitions) + S2→S3, S3→S4 per-group attributions + 4-panel attribution facets + diagnostic tables; 03b: paper §4.1 baseline figure + §4.5 daily overlay + USMCA adjustment explainer + supplementary monthly summary table |
| 4 | `code/04_fta_decomposition.do` | Preference channel decomposition (USMCA, KORUS, GSP, duty-free, etc.) |
| 5 | `code/05_max_district_crosscheck.do` | Validate tracker rates vs. max observed across customs districts |
| 6 | `code/06_baseline_etr_diagnostic.do` | Tracker `total_rate` (= `rate_h2avg`, S1) vs `rate_2024`-reconstruction at 2024 weights (`figure_diagnostic`) |
| 7 | `code/07_cumulative_duty_gap.do` | Standalone (not in orchestrator): cumulative Census IMDB vs Treasury monthly customs duties — dollar-level analogue of `gap_timing` (S4→T) |

### Usage

```
Rscript code/R/00_pull_raw_data.R                    # Step 0 (~30-60 min default)
cd "C:/Users/ji252/Documents/GitHub/tariff-etr-eval"  # Stata
do 00_etr_eval.do                                     # Steps 1-6
```

Step 0 flags: `--refresh-tracker` (rebuild sibling tracker first), `--with-census` (also pull Census HS2 API, hours-long, optional), `--only-tracker`, `--only-counterfactual`, `--skip-imdb`. Toggle Stata steps via `$run_*` flags in `code/utils/globals.do`.

## Data Sources

| Source | Repo/API | What |
|--------|----------|------|
| Census IMDB bulk | `census.gov/trade/downloads/` | HS10 x country x district x preference detail (primary monthly source; HS2 rollups derived from this) |
| Census Bureau API | `api.census.gov` | HS2 x country monthly trade — opt-in via `--with-census`; not consumed by the Stata pipeline |
| Tariff Rate Tracker | `tariff-rate-tracker` (sibling) | HTS10 x country statutory rates, daily ETR, import weights |
| Tariff Impact Tracker | `tariff-impact-tracker` (sibling) | Monthly actual ETR (Treasury customs duties / imports) |

Both sibling repos must be at the same directory level as this repo.

## Six-Tier Decomposition

| Tier | Definition |
|------|------------|
| S0 | Statutory @ USMCA 2024 baseline shares × 2024 import weights |
| S1 | Statutory @ Post-July 2025 USMCA baseline shares × 2024 import weights (= the paper's headline statutory line) |
| S2 | Statutory @ Post-July 2025 USMCA baseline shares × monthly weights |
| S3 | + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs), monthly IMDB-derived shares |
| S4 | Census collected ETR (cal_dut / con_val at HS10 × cty, summed) |
| T | Treasury actual ETR |

**Gap channels**:
- **S0 → S1**: USMCA adjustment (claim-rate normalization 2024 → post-July 2025; weights frozen). Mostly retrospective — firms filed USMCA claims late, and a July 2025 reporting change made the utilization visible. Shown as backstory in 03b's USMCA explainer figures, not part of the main analytic waterfall.
- **S1 → S2**: trade diversion (composition shift in monthly weights with USMCA stable at h2avg). Main analysis channel.
- **S2 → S3**: all-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / other FTAs).
- **S3 → S4**: residual (specific-duty AVE failures, AD/CVD, tracker error, behavioral noise).
- **S4 → T**: timing / enforcement (Treasury vs Census aggregation).

`gap_adjustment` is mostly one-signed; `gap_diversion` is bidirectional (negative country-period averages = "reverse diversion" for CA/MX whose imports concentrate in inelastic high-tariff categories). The all-other-preferences rung is structurally non-negative. `gap_residual` is structurally positive (Census-declared duties undershoot the cell-level reconstruction); `gap_timing` is bidirectional and has trended strongly negative since mid-2025 (Treasury cash receipts now exceed Census-declared duties by a widening cumulative margin).

The framework's S1 panel equals the tracker's daily ETR collapsed to monthly by construction, so the paper's headline §4.1 "baseline statutory" line is also S1 — the framework backbone aligns with the headline figure.

## Output

Every figure is exported in two versions: `figure_X.png` (no titles/subtitles, default for slides) and `figure_X_titled.png` (with titles/subtitles, for the paper draft). The dual-export pattern is documented in `CLAUDE.md`.

**Figures** (`results/figures/`):
- `figure_baseline.png` — paper §4.1 headline: monthly statutory (= S1) vs Treasury-actual ETR
- `figure_ladder.png` — five-line ladder: S0, S1, S2, S3, Treasury actual
- `figure_gap_stacked.png` — USMCA-adjustment vs main-analytic gap, stacked monthly
- `figure_channel_stacked.png` — S1→Treasury split into diversion / others / residual+timing
- `figure_diversion_{decomp,country,product}.png` — S1→S2 Shapley two-way (aggregate and partitions)
- `figure_s1s2_facets_{country,product}.png` — S1 vs S2 group-level ETR facets
- `figure_others_{country,product,channel_stack}.png` — S2→S3 attribution
- `figure_residual_{country,product}.png` — S3→S4 per-group residuals
- `figure_s2s4_{overall,gap_country,gap_product,facets_country,facets_product,heatmap}.png` — S2 vs S4 vs T comparison
- `figure_attribution_{country,product}.png` — 4-panel attribution facets across all decomposable channels
- `figure_adjustment_{explainer,country}.png` — S0→S1 USMCA explainer (paper §3, 03b)
- `figure_diagnostic.png` — self-consistency check at 2024 weights (06)
- `figure_cumulative_duty_gap.png` — cumulative Census-vs-Treasury duty gap (07, standalone)

**Tables** (`results/tables/`):
- `decomp_monthly.csv` — monthly six-tier decomposition (S0–S4–T) + channel gaps (`gap_adjustment`, `gap_diversion`, `gap_others`, `gap_residual`, `gap_timing`)
- `counterfactual_ladder.csv` — overall ladder (S0/S1/S2/S3 + T)
- `counterfactual_by_country.csv` — country-level ladder for Shapley input
- `diversion_by_country_avg.csv` / `diversion_by_product_avg.csv` — period-mean Shapley contributions
- `attribution_by_country.csv` / `attribution_by_product.csv` — per-group monthly contributions across the four decomposable channels
- `cumulative_duty_gap.csv` — monthly Census vs Treasury duties + cumulative diff (from 07)
- `fta_decomp_monthly.csv` / `fta_utilization_rates.csv` — preference channel breakdown
- `cmp_overall_monthly.csv` / `cmp_partner_monthly.csv` / `cmp_product_monthly.csv` — S2 vs S4 vs T tables
- `max_district_summary.csv` — tracker validation statistics
- `tracker_miss_*.csv` / `tracker_over_*.csv` — diagnostic deliverables for the tracker maintainer (false-negative and false-positive directions)

## Requirements

**R** (step 0 only): `httr`, `jsonlite`, `dplyr`, `readr`, `here`, `stringi`, `yaml`

**Stata 17+**: `ftools`, `reghdfe`, `gtools`, `estout`, `plotplainblind`

Set `CENSUS_API_KEY` in `~/.Renviron` for Census API access.

## Methodology

- `CLAUDE.md` — canonical six-tier framework definitions, channel directions, and per-authority applicability (the docs below pre-date the April 2026 framework restructure; CLAUDE.md is the source of truth).
- `docs/paper_outline_v2.md` — current paper outline, with figure-name map, Shapley derivation, and Eck et al.\ (2026) cross-validation.
- `docs/weighting_note.md` — value-weighted aggregation, importance of including zero-tariff products.
- `docs/etr-literature-review.md` — context on the statutory-actual ETR gap literature.
- `docs/tracker_miss_report.md` / `docs/tracker_over_report.md` — diagnostic handoffs to the `tariff-rate-tracker` maintainer (false-negative and false-positive rate-parsing errors).
