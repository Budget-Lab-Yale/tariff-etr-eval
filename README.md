# Tariff ETR Evaluation

Comparing actual vs. statutory effective tariff rates during the 2025-2026 US tariff escalation.

## Overview

This project evaluates the gap between **statutory** tariff rates (what the Harmonized Tariff Schedule says importers should pay) and **actual** collection rates (customs duties actually collected as a share of import value). The gap is decomposed into trade diversion, USMCA surge, all-other preferences, residual, and timing/enforcement channels using a **six-tier framework** (S0 → S1 → S2 → S3 → S4 → T). See `docs/six_tier_framework_plan.md` for the math (per-authority applicability matrix, sign-bearing channel discussion).

## Pipeline

The pipeline has two stages: R assembles raw data from external APIs and sibling repos; Stata cleans, merges, and runs all analysis.

| Step | Script | What |
|------|--------|------|
| 0 | `code/R/00_pull_raw_data.R` | IMDB bulk (HS10 detail), tracker snapshots, Treasury revenue, USMCA + non-USMCA preference share files (Census HS2 API opt-in via `--with-census`) |
| 1 | `code/01_etr_clean.do` | Import CSVs, clean, merge Census × tracker at HS10 × country × month; merge in three rate panels (rate_2024, rate_usmca_monthly, rate_all_pref) onto `merged_analysis.dta` |
| 2 | `code/02_counterfactual_ladder.do` | Six-tier waterfall (S0→S1→S2→S3→T) — canonical tier values |
| 3 | `code/03_etr_analysis.do` + `code/03b_baseline_figures.do` | 03: six-tier ETR decomposition + figures 1–6 + S0→S1 trade-diversion decomp (figs D1/D2/D3) + product-group gap figs (P1/P2/P3) + diagnostic tables; 03b: paper §4.1 baseline figure + §4.5 daily overlay + supplementary monthly summary table (TBL-judgment economic portrayal, separate methodology) |
| 4 | `code/04_fta_decomposition.do` | Preference channel decomposition (USMCA, KORUS, GSP, duty-free, etc.) |
| 5 | `code/05_max_district_crosscheck.do` | Validate tracker rates vs. max observed across customs districts |
| 6 | `code/06_baseline_etr_diagnostic.do` | Tracker total_rate vs S0-reconstruction at 2024 weights (figure 7) |

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
| S1 | Statutory @ USMCA H2-2025 baseline shares × 2024 import weights (= the paper's headline statutory line) |
| S2 | Statutory @ USMCA H2-2025 baseline shares × monthly weights |
| S3 | + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs), monthly IMDB-derived shares |
| S4 | Census collected ETR (cal_dut / con_val at HS10 × cty, summed) |
| T | Treasury actual ETR |

**Gap channels**:
- **S0 → S1**: USMCA adjustment (claim-rate normalization 2024 → H2-2025; weights frozen). Mostly retrospective — firms filed USMCA claims late, and a July 2025 reporting change made the utilization visible. Shown as backstory in 03b's USMCA explainer figures, not part of the main analytic waterfall.
- **S1 → S2**: trade diversion (composition shift in monthly weights with USMCA stable at h2avg). Main analysis channel.
- **S2 → S3**: all-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / other FTAs).
- **S3 → S4**: residual (specific-duty AVE failures, AD/CVD, tracker error, behavioral noise).
- **S4 → T**: timing / enforcement (Treasury vs Census aggregation).

`gap_adjustment` is mostly one-signed; `gap_diversion` is bidirectional (negative country-period averages = "reverse diversion" for CA/MX whose imports concentrate in inelastic high-tariff categories). The all-other-preferences rung is structurally non-negative. See `docs/six_tier_framework_plan.md` §5a for the bidirectional channel discussion.

The framework's S1 panel equals the tracker's daily ETR collapsed to monthly by construction, so the paper's headline §4.1 "baseline statutory" line is also S1 — the framework backbone aligns with the headline figure.

## Output

**Figures** (`results/figures/`):
- Figure 1: Actual vs. statutory ETR comparison (monthly line chart)
- Figure 2: Gap decomposition (grouped and stacked bar charts)

**Tables** (`results/tables/`):
- `decomp_monthly.csv` — monthly six-tier decomposition (S0–S4–T) + channel gaps
- `decomp_by_country.csv` — Shapley between/within by partner group (legacy h2avg basis)
- `fta_decomp_monthly.csv` — preference channel breakdown
- `fta_utilization_rates.csv` — USMCA/KORUS utilization rates
- `max_district_summary.csv` — tracker validation statistics
- `counterfactual_ladder.csv` — six-tier waterfall (S0–S3–T) with country-level
- `tracker_miss_*.csv` / `tracker_over_*.csv` — diagnostic deliverables for the tracker maintainer (false-negative and false-positive directions)

## Requirements

**R** (step 0 only): `httr`, `jsonlite`, `dplyr`, `readr`, `here`, `stringi`, `yaml`

**Stata 17+**: `ftools`, `reghdfe`, `gtools`, `estout`, `plotplainblind`

Set `CENSUS_API_KEY` in `~/.Renviron` for Census API access.

## Methodology

- `docs/six_tier_framework_plan.md` — six-tier framework derivation, per-authority applicability matrix, sign-bearing channels, implementation scope.
- `docs/methodology_outline.md` — paper outline mapping framework to results sections.
- `docs/weighting_note.md` — value-weighted aggregation, importance of including zero-tariff products.
- `docs/etr-literature-review.md` — context on the statutory-actual ETR gap literature.
- `docs/tracker_miss_report.md` / `docs/tracker_over_report.md` — diagnostic handoffs to the `tariff-rate-tracker` maintainer (false-negative and false-positive rate-parsing errors).
