# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Evaluates the gap between **statutory** U.S. tariff rates (from the Harmonized Tariff Schedule) and **actual** collected rates (customs duties / import value) during the 2025-2026 tariff escalation. Decomposes the gap into behavioral (trade diversion), exemptions (USMCA/FTA), and timing/enforcement channels using a four-tier framework.

## Pipeline

The pipeline has two stages. R assembles raw data; Stata cleans, merges, and analyzes.

```
Rscript code/R/00_pull_raw_data.R     # Step 0: populate data/raw/ from APIs + sibling repos
do 00_etr_eval.do                      # Steps 1-2: clean, merge, decompose, figures
```

### Step 0 — R data assembly (`code/R/00_pull_raw_data.R`)

Pulls from four sources and writes CSVs to `data/raw/`:
- **Census API** (HS2 x country x month): consumption value, calculated duty, dutiable value
- **Census IMDB bulk ZIPs** — two outputs:
  - `imdb_detail.csv`: HS10 x country x district x preference x rate_prov x month (for FTA decomposition, district crosscheck)
  - `imdb_hs10_country_monthly.csv`: aggregated to HS10 x country x month (for main pipeline)
- **Census API HS10 fallback**: fills months not yet available in IMDB bulk (auto-detected)
- **tariff-rate-tracker** (sibling repo): converts RDS snapshots to CSV, copies daily ETRs, revision dates, 2024 import weights
- **tariff-impact-tracker** (sibling repo): Treasury revenue (actual ETR)

### Step 1 — Stata clean & merge (`code/01_etr_clean.do`)

Imports all CSVs, assigns partner groups, maps months to HTS revisions, merges Census HS10 trade data with tracker snapshot rates on `(hs10, country, revision)`. Computes 2024 fixed weights and monthly weights. Output: `data/working/merged_analysis.dta`.

### Step 2 — Stata analysis (`code/02_etr_analysis.do`)

Four-tier decomposition:
- **Tier 1**: Statutory ETR x 2024 weights
- **Tier 2**: Statutory ETR x actual monthly weights
- **Tier 3**: Census calculated ETR (duty / value at HS10 x country)
- **Tier 4**: Treasury actual ETR (aggregate customs duties / imports)

Gap channels: T1->T2 = behavioral, T2->T3 = exemptions, T3->T4 = timing/enforcement/evasion. Also runs Shapley decomposition by country.

## Running the pipeline

```stata
cd "C:/Users/ji252/Documents/GitHub/tariff-etr-eval"
do 00_etr_eval.do
```

Toggle steps via globals in `code/utils/globals.do`:
- `$run_clean` (default 1): skip Step 1 if data is already built
- `$run_analysis` (default 1): skip Step 2

The R step must be run separately first (or is called via `shell Rscript` in the orchestrator).

## Sibling repo dependencies

Both must be at the same directory level as this repo:
- `tariff-rate-tracker` — statutory rates, daily ETR, import weights, revision dates
- `tariff-impact-tracker` — Treasury revenue (actual ETR)

## Key configuration (`code/utils/globals.do`)

- Path globals: `$dir`, `$code`, `$data`, `$raw`, `$working`, `$results`, `$figures`, `$tables`
- Analysis window: `$start_ym` to `$end_ym` (Jan 2025 -- Feb 2026)
- Partner groups: China, Canada, Mexico, EU, Japan, S. Korea, UK, ROW
- Policy event dates: `$event_fentanyl`, `$event_liberation`, etc. (for figure reference lines)
- Color palette: `$color_actual` (red), `$color_statutory` (navy), `$color_gap` (green), partner-specific colors
- Graph scheme: `plotplainblind` (colorblind-friendly)

## Reusable Stata programs (`code/utils/programs.do`)

- `assign_partner_group <varname>` — maps Census country codes to 8 partner groups (China, CA, MX, EU, JP, KR, UK, ROW)
- `safe_divide` — handles zero-denominator division
- HS2 chapter labels (99 chapters)

## Two-stage weighting (critical methodology)

HTS10 rates are available only with 2024 annual weights. Monthly trade data from Census is at HS2 x country. The decomposition bridges these via two stages:
1. Collapse HTS10 rates to HS2 x country using HTS10 weights
2. Aggregate HS2 x country to overall using Census monthly weights

Zero-tariff products **must be included** in the denominator. Dropping them inflates the ETR from ~3.4% to ~27%. See `docs/weighting_note.md`.

## R_archive/

Contains the original R-based pipeline (pre-Stata refactor). No longer in the critical path, but includes analyses not yet ported:
- `02b_fta_decomposition.R` — USMCA/FTA utilization detail using IMDB preference codes
- `03_counterfactual_ladder.R` — Gopinath-Neiman-style waterfall decomposition
- `02c_max_district_crosscheck.R` — validates tracker rates against max observed across customs districts

## Conventions

- Orchestrator naming: `00_etr_eval.do` (numeric prefix `00_` signals top-level runner)
- Stata globals defined centrally in `globals.do`, never hardcoded in analysis scripts
- All raw data written to `data/raw/`, intermediate .dta to `data/working/`, final output to `results/`
- R uses `here::i_am()` for path resolution; Stata uses `$dir` auto-detected from `c(pwd)`
- Census country codes are strings (e.g., "5700" = China), mapped via `assign_partner_group`
- User frequently edits files externally; always re-read before editing
