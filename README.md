# Tariff ETR Evaluation

Comparing actual vs. statutory effective tariff rates during the 2025-2026 US tariff escalation.

## Overview

This project evaluates the gap between **statutory** tariff rates (what the Harmonized Tariff Schedule says importers should pay) and **actual** collection rates (customs duties actually collected as a share of import value). The gap is decomposed into behavioral (trade diversion), exemptions (USMCA/FTA utilization), and timing/enforcement channels using a four-tier framework.

## Pipeline

The pipeline has two stages: R assembles raw data from external APIs and sibling repos; Stata cleans, merges, and runs all analysis.

| Step | Script | What |
|------|--------|------|
| 0 | `code/R/00_pull_raw_data.R` | IMDB bulk (HS10 detail), tracker snapshots, Treasury revenue (Census HS2 API opt-in via `--with-census`) |
| 1 | `code/01_etr_clean.do` | Import CSVs, clean, merge Census x tracker at HS10 x country x month |
| 2 | `code/02_etr_analysis.do` | Four-tier ETR decomposition, Shapley by country, figures |
| 3 | `code/03_fta_decomposition.do` | Preference channel decomposition (USMCA, KORUS, GSP, duty-free, etc.) |
| 4 | `code/04_max_district_crosscheck.do` | Validate tracker rates vs. max observed across customs districts |
| 5 | `code/05_counterfactual_ladder.do` | Gopinath-Neiman waterfall (USMCA baseline/surge, behavioral, residual) |

### Usage

```
Rscript code/R/00_pull_raw_data.R                    # Step 0 (~30-60 min default)
cd "C:/Users/ji252/Documents/GitHub/tariff-etr-eval"  # Stata
do 00_etr_eval.do                                     # Steps 1-5
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

## Four-Tier Decomposition

| Tier | Definition | Weights |
|------|------------|---------|
| 1 | Statutory ETR (tracker rates) | 2024 annual |
| 2 | Statutory ETR (tracker rates) | Actual monthly |
| 3 | Census calculated ETR (duty / value) | Actual monthly |
| 4 | Treasury actual ETR | Aggregate |

**Gap channels**: T1->T2 = behavioral (trade diversion + product substitution); T2->T3 = exemptions (USMCA, FTA, specific-rate effects); T3->T4 = timing, enforcement, evasion.

## Output

**Figures** (`results/figures/`):
- Figure 1: Actual vs. statutory ETR comparison (monthly line chart)
- Figure 2: Gap decomposition (grouped and stacked bar charts)

**Tables** (`results/tables/`):
- `decomp_monthly.csv` -- monthly four-tier decomposition
- `decomp_by_country.csv` -- Shapley between/within by partner group
- `fta_decomp_monthly.csv` -- preference channel breakdown
- `fta_utilization_rates.csv` -- USMCA/KORUS utilization rates
- `max_district_summary.csv` -- tracker validation statistics
- `counterfactual_ladder.csv` -- waterfall decomposition

## Requirements

**R** (step 0 only): `httr`, `jsonlite`, `dplyr`, `readr`, `here`, `stringi`, `yaml`

**Stata 17+**: `ftools`, `reghdfe`, `gtools`, `estout`, `plotplainblind`

Set `CENSUS_API_KEY` in `~/.Renviron` for Census API access.

## Methodology

See `docs/weighting_note.md` for the two-stage aggregation approach (HTS10 -> HS2 x country -> overall) and `docs/etr-literature-review.md` for context on the statutory-actual ETR gap literature.
