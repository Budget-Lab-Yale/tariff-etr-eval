# Tariff ETR Evaluation

Comparing actual vs. statutory effective tariff rates during the 2025–2026 US tariff escalation.

## Overview

This project evaluates the gap between **statutory** tariff rates (what the Harmonized Tariff Schedule says importers should pay) and **actual** collection rates (customs duties collected as a share of import value). The gap is decomposed into USMCA adjustment, trade diversion, all-other preferences, residual, and timing/enforcement channels using a **six-tier framework** (S0 → S1 → S2 → S3 → S4 → T). See [Six-tier framework](#six-tier-framework) below for definitions, channel directions, and sign properties; `docs/six_tier_framework_plan.md` carries the full math derivation and per-authority applicability matrix.

## Pipeline

The pipeline has two stages: R assembles raw data from external APIs and sibling repos; Stata cleans, merges, and runs all analysis.

| Step | Script | What |
|------|--------|------|
| 0 | `code/R/00_pull_raw_data.R` | IMDB bulk (HS10 detail), tracker snapshots (incl. `total_rate` ≡ `rate_h2avg`), Treasury revenue, USMCA + non-USMCA preference share files (Census HS2 API opt-in via `--with-census`) |
| 1 | `code/01_etr_clean.do` | Import CSVs, clean, merge Census × tracker at HS10 × country × month; carry the three counterfactual rate panels (`rate_2024` for S0, `rate_h2avg` for S1/S2 — the framework anchor — and `rate_all_pref` for S3) onto `merged_analysis.dta` |
| 2 | `code/02_counterfactual_ladder.do` | Six-tier waterfall (S0→S1→S2→S3, joined to T) — canonical tier values |
| 3 | `code/03_etr_analysis.do` + `code/03b_baseline_figures.do` | 03: six-tier ETR decomposition + ladder/channel figures + S1→S2 trade-diversion Shapley decomp (country and product partitions) + S2→S3, S3→S4 per-group attributions + 4-panel attribution facets + diagnostic tables; 03b: paper §4.1 baseline figure + §4.5 daily overlay + USMCA adjustment explainer + supplementary monthly summary table |
| 4 | `code/04_fta_decomposition.do` | Preference channel decomposition (USMCA, KORUS, GSP, duty-free, etc.) |
| 5 | `code/05_max_district_crosscheck.do` | Validate tracker rates vs. max observed across customs districts |
| 5a | `code/05a_tracker_miss_diagnostic.do` | Standalone (not in orchestrator): false-negative diagnostic for `tariff-rate-tracker` — surfaces (HS10, country, month) cells where the tracker rate is zero but Census collected positive duty. Output: `tracker_miss_*.csv`. |
| 5b | `code/05b_tracker_over_diagnostic.do` | Standalone (not in orchestrator): false-positive companion to 5a — surfaces cells where the tracker rate over-states the Census-collected duty, attributed by preference / rate-provision channel. Output: `tracker_over_*.csv`. |
| 6 | `code/06_baseline_etr_diagnostic.do` | Tracker `total_rate` (= `rate_h2avg`, S1) vs `rate_2024`-reconstruction at 2024 weights (`figure_diagnostic`) |
| 7 | `code/07_cumulative_duty_gap.do` | Standalone (not in orchestrator): cumulative Census IMDB vs Treasury monthly customs duties — dollar-level analogue of `gap_timing` (S4→T) |

### Step 0 — R data assembly (`code/R/00_pull_raw_data.R`)

Pulls from four sources and writes CSVs to `data/raw/`. Sections can be toggled via command-line flags (see [Running the pipeline](#running-the-pipeline)).

- **Section 1 — Census API** (HS2 × country × month, *opt-in via `--with-census`*): consumption value, calculated duty, dutiable value. Output is no longer consumed by the Stata pipeline — HS2-level rollups aggregate IMDB HS10 data instead. Section is retained for ad-hoc use and to seed the Section 2b HS10 fallback.
- **Section 2 — Census IMDB bulk ZIPs** — two outputs:
  - `imdb_detail.csv`: HS10 × country × district × preference × rate_prov × month (for FTA decomposition, district crosscheck)
  - `imdb_hs10_country_monthly.csv`: aggregated to HS10 × country × month (for main pipeline)
  - Census API HS10 fallback: fills months not yet available in IMDB bulk (auto-detected)
- **Section 3a–3c — `tariff-rate-tracker`** (sibling): converts RDS snapshots to CSV (including `statutory_rate_*` pre-USMCA components), copies daily ETRs, revision dates, 2024 import weights.
- **Section 3d–3e — USMCA counterfactual rate reconstruction**: copies USMCA product-level utilization shares from the tracker (2024 annual + monthly 2025–2026 from USITC DataWeb SPI data), then reconstructs HS10 × country × month rates by applying shares to pre-USMCA statutory components and day-weighting across revisions within months. Output: `counterfactual_usmca2024.csv` and `counterfactual_usmca_monthly.csv`.
- **Section 3f — Non-USMCA preference shares from IMDB**: aggregates `imdb_detail.csv` by (HS10, country, month) and classifies into 9 preference channels (USMCA, KORUS, other_fta, GSP/AGOA, duty_free, ch99_dutiable, mfn_dutiable, ftz_bonded, other) via `classify_pref_channel`. Output: `imdb_other_pref_shares_monthly.csv`.
- **Section 3g — S2 → S3 preference-delta file**: per-cell rate reduction `delta_base + delta_recip` from non-USMCA preference shares × pre-preference component rates. Output: `counterfactual_other_pref_delta_monthly.csv` (sparse — only cells with positive non-USMCA preference share). See `docs/six_tier_framework_plan.md` §6.6 for derivation.
- **Section 4 — `tariff-impact-tracker`** (sibling): Treasury revenue (actual ETR).

### Step 1 — Clean & merge (`code/01_etr_clean.do`)

Imports all CSVs, assigns partner groups, maps months to HTS revisions, merges Census HS10 trade data with tracker snapshot rates on `(hs10, country, revision)`, and merges in three counterfactual rate panels (B6 `cf_usmca_monthly.dta` → `rate_usmca_monthly` for the USMCA explainer; B7 `cf_usmca2024.dta` → `rate_2024` for S0; B7b `cf_h2avg.dta` → `rate_h2avg` for S1/S2; B8 `cf_pref_delta.dta` → `rate_all_pref` for S3). Computes 2024 fixed weights and monthly weights. Output: `data/working/merged_analysis.dta` carrying `total_rate`, `rate_2024`, `rate_h2avg`, `rate_usmca_monthly`, `rate_all_pref`, `imports`, `con_val_mo` on every row.

### Step 2 — Counterfactual ladder (`code/02_counterfactual_ladder.do`)

Thin script. Loads `merged_analysis.dta` and calls `compute_tier` 4× for the aggregate ladder (S0/S1/S2/S3) and 4× for the country ladder, joins T from `revenue_monthly.dta`. Single source of truth for ladder values consumed by Step 3.

- S0: `rate_2024 × imports` (USMCA frozen 2024 × 2024 wts)
- S1: `rate_h2avg × imports` (Post-July 2025 USMCA × 2024 wts)
- S2: `rate_h2avg × con_val_mo` (Post-July 2025 USMCA × monthly wts)
- S3: `rate_all_pref × con_val_mo` (S2 minus non-USMCA preference delta × monthly wts)
- T:  Treasury actual

Output: `counterfactual_ladder.dta` (overall) + `counterfactual_by_country.dta` (by `partner_group`).

### Step 3 — Analysis & figures (`code/03_etr_analysis.do` + `code/03b_baseline_figures.do`)

Step 3 runs two scripts back-to-back. **03** is the framework decomposition; **03b** is paper-output figures using a separate methodology.

**`03_etr_analysis.do`** — Six-tier decomposition. Section A reads S0/S1/S2/S3 + T from `counterfactual_ladder.dta` and adds S4 (Census collected ETR). Section B does the Shapley two-way decomposition of **S1→S2** (trade diversion) into between-group + within-group, twice — once partitioning by `partner_group` (country lens), once by `product_group` (product lens). Both lenses sum to the same `gap_diversion`. Outputs `diversion_by_country.dta`, `diversion_by_product.dta`, and `_avg.csv` summaries; figs D1 (aggregate decomp time series), D2 (country stacked-bar contributions), D3 (product stacked-bar contributions). Section D (figs 4–6) uses `compute_tier` on `rate_h2avg` so its statutory line is identical-by-construction to S2. Section D7 mirrors D2 with `product_group` and adds a `heatplot`-based figure P3 (S2−S4 gap on the product × partner grid).

The framework's S1 panel (`rate_h2avg × imports`) **equals the tracker's daily ETR collapsed to monthly** by construction — so the paper's headline §4.1 "baseline statutory" line in `figure_baseline.png` is also S1. Framework backbone aligns with the headline figure.

**`03b_baseline_figures.do`** — paper figures: §4.1 baseline (= framework S1), §4.5 daily overlay, supplementary monthly summary table, **§3 USMCA adjustment explainer**. Section D produces `figure_adjustment_explainer.png` (CA + MX statutory ETR under three USMCA scenarios — 2024 baseline, monthly empirical, post-July 2025 baseline; the empirical line moves between the two reference lines mid-2025) and `figure_adjustment_country.png` (period-averaged S0−S1 gap by partner group, dominated by CA and MX). Plus `adjustment_by_country.csv`.

**Figure naming convention.** Every `figure_*.png` is exported in two versions — `figure_X.png` (no titles/subtitles, default for slides) and `figure_X_titled.png` (with titles/subtitles, for the paper draft). Every figure site uses the inline `foreach v in titled clean { ... }` pattern: define `local opt_title` and `local sfx` conditionally on `v`, then build the graph with `\`opt_title'` and export with `\`sfx'`. (`graph display, title("")` is not valid Stata syntax, so post-hoc title clearing isn't an option.)

### Step 4 — FTA decomposition (`code/04_fta_decomposition.do`)

Decomposes the S2→S3 exemptions gap into preference channels using IMDB detail data (`cty_subco`, `rate_prov`): USMCA, KORUS, other FTAs, GSP/AGOA, duty-free entries, ch99 dutiable, MFN dutiable. Also computes USMCA/KORUS utilization rates. Requires `imdb_detail.csv`.

### Step 5 — Max-district crosscheck (`code/05_max_district_crosscheck.do`)

Validates tracker statutory rates against max observed ETR across customs districts per HS10 × country. Classifies into match / tracker_higher / observed_higher. Tracker-higher = universal preference use; observed-higher = possible tracker parsing error. Requires `imdb_detail.csv`.

### Step 6 — Baseline ETR diagnostic (`code/06_baseline_etr_diagnostic.do`)

Diagnostic at 2024 weights comparing tracker `total_rate` (baseline USMCA already applied) vs the `rate_2024` reconstruction (`cf_usmca2024`). Both use 2024 baseline USMCA assumptions, so any gap between them isolates reconstruction methodology; matched/nonzero universe slices isolate zero-rate-dropping and unmatched-product effects. Builds its own panel from `weights_2024.dta` (different universe from `merged_analysis.dta`). Output: `figure_diagnostic` + diagnostic table.

## Running the pipeline

### R data pull (Step 0)

```bash
Rscript code/R/00_pull_raw_data.R                       # IMDB + tracker + impacts (~30–60 min)
Rscript code/R/00_pull_raw_data.R --with-census         # also pull Census HS2 API (hours)
Rscript code/R/00_pull_raw_data.R --skip-imdb           # skip IMDB bulk downloads
Rscript code/R/00_pull_raw_data.R --only-tracker        # sections 3a–3e only (~15 min)
Rscript code/R/00_pull_raw_data.R --only-counterfactual # sections 3d–3g only (~10 min)
Rscript code/R/00_pull_raw_data.R --refresh-tracker     # rebuild tracker first (~hours)
```

Use `--only-tracker` after updating the tracker repo to regenerate snapshot CSVs, USMCA shares, and counterfactual rate files. Use `--refresh-tracker` to rebuild the tracker end-to-end (revision dates, HTS JSON, DataWeb USMCA shares, top-level + per-scenario snapshots, daily ETRs) before the export steps; requires `DATAWEB_API_TOKEN` in `tariff-rate-tracker/.env` and may halt at `01_scrape_revision_dates.R` if a new HTS revision needs manual policy-date curation. Composes with the other flags.

### Stata pipeline (Steps 1–6)

```stata
cd <repo-root>
do 00_etr_eval.do
```

Toggle steps via globals in `code/utils/globals.do` (execution order):

- `$run_pull` (Step 0): R data pulls (hours-long; off by default)
- `$run_clean` (Step 1): import, clean, merge → `merged_analysis.dta`
- `$run_ladder` (Step 2): counterfactual ladder → `counterfactual_ladder.dta`
- `$run_analysis` (Step 3): six-tier decomposition and figures (consumes ladder)
- `$run_fta` (Step 4): FTA/preference decomposition (needs `imdb_detail.csv`)
- `$run_crosscheck` (Step 5): max-district validation (needs `imdb_detail.csv`)
- `$run_baseline` (Step 6): baseline ETR diagnostic

## Sibling repo dependencies

Both must be cloned at the same directory level as this repo. Step 0 reads RDS snapshots, daily ETR CSVs, and Treasury revenue from those checkouts; if either is missing, the script aborts with a clear error pointing at the expected path.

- [`Budget-Lab-Yale/tariff-rate-tracker`](https://github.com/Budget-Lab-Yale/tariff-rate-tracker) — statutory rates, daily ETR, import weights, revision dates, USMCA product shares (from USITC DataWeb SPI data).
- [`Budget-Lab-Yale/tariff-impact-tracker`](https://github.com/Budget-Lab-Yale/tariff-impact-tracker) — Treasury revenue (actual ETR).

Suggested layout:

```
GitHub/
├── tariff-etr-eval/         # this repo
├── tariff-rate-tracker/     # https://github.com/Budget-Lab-Yale/tariff-rate-tracker
└── tariff-impact-tracker/   # https://github.com/Budget-Lab-Yale/tariff-impact-tracker
```

## Six-tier framework

| Tier | Definition |
|------|------------|
| S0 | Statutory @ USMCA 2024 baseline shares × 2024 import weights |
| S1 | Statutory @ Post-July 2025 USMCA baseline shares × 2024 import weights (= the paper's headline statutory line) |
| S2 | Statutory @ Post-July 2025 USMCA baseline shares × monthly weights |
| S3 | + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs), monthly IMDB-derived shares |
| S4 | Census collected ETR (cal_dut / con_val at HS10 × cty, summed) |
| T  | Treasury actual ETR |

The waterfall decomposes the statutory–actual ETR gap into five sequential channels. The S0→S1 step is treated as "explainable backstory" and shown via the USMCA adjustment explainer figures in `03b`; main analysis lives between S1 and T.

1. **USMCA adjustment (S0 → S1)** — hold weights at 2024, shift USMCA from 2024 baseline (~38% CA / ~50% MX) to post-July 2025 baseline (~89% both). Mostly retrospective: firms filed USMCA claims late, and a July 2025 reporting change made the underlying utilization visible. `gap_adjustment` is mostly one-signed.
2. **Trade diversion (S1 → S2)** — hold post-July 2025 USMCA, shift weights from 2024 to actual monthly. Composition shift in trade flows. Sign-bearing — negative ("reverse diversion") for CA/MX/China/ROW because their imports are concentrated in inelastic high-tariff categories. Decomposed Shapley two-way in 03 Section B (figs D1–D3).
3. **All-other preferences (S2 → S3)** — apply non-USMCA preference claim shares (Annex II / ITA / Ch98 / KORUS / GSP / other_fta) from IMDB. Per-authority math: `delta_base = (s_duty_free + s_korus + s_gsp + s_other_fta) × base_rate_pre`, `delta_recip = s_duty_free × recip_rate_pre`. Structurally non-negative.
4. **Residual (S3 → S4)** — remaining gap between statutory (with all preferences applied) and Census collected. Captures specific-duty AVE failures, AD/CVD, tracker error not yet corrected, behavioral noise within HS10 × cty cells. Structurally positive (Census-declared duties undershoot the cell-level reconstruction).
5. **Timing / enforcement (S4 → T)** — Treasury vs Census aggregation. Refunds, post-entry adjustments, FTZ deferrals, cash-vs-accrual timing. Bidirectional; has trended strongly negative since mid-2025 (Treasury cash receipts now exceed Census-declared duties by a widening cumulative margin).

USMCA shares are product-level (HS10 × country) from USITC DataWeb SPI program codes (S/S+). Non-USMCA preference shares come from IMDB importer-declared `cty_subco` and `rate_prov` fields, classified via `classify_pref_channel`. The applicability matrix encoded in tracker steps 6c (FTA/GSP for `base`) and 7 (USMCA for `base`/`recip`/`fent`/`232`/`s122` with `0.40` content rule for auto/MHD) is preserved by the R reconstruction logic. See `docs/six_tier_framework_plan.md` §6 for the full math, including the per-preference applicability matrix and sign-reversal explanation.

The framework's S1 panel equals the tracker's daily ETR collapsed to monthly by construction, so the paper's headline §4.1 "baseline statutory" line is also S1 — the framework backbone aligns with the headline figure.

## Aggregation methodology

All ETR tiers are computed via single-stage row-level value-weighted averages over the (HS10 × country × month) cells of `merged_analysis.dta`: `Sum(rate × weight) / Sum(weight)`. Rate columns (`rate_2024`, `rate_h2avg` ≡ `total_rate`, `rate_usmca_monthly`, `rate_all_pref`) and weight columns (`imports` for 2024, `con_val_mo` for monthly) sit on the same row, so `compute_tier` collapses are uniform across tiers and figures. No HS2 bridging.

Zero-tariff products **must be included** in the denominator. Dropping them inflates the ETR from ~3.4% to ~27%. See `docs/weighting_note.md`.

`rate_h2avg` is the framework alias for the tracker's production `total_rate` column — built in the `tariff-rate-tracker` sibling at `src/06_calculate_rates.R` with USMCA scaled by **post-July 2025 average claim rates** (~89% for CA/MX). `rate_2024` swaps that to **2024-baseline claim rates** (~38% CA / ~50% MX); `rate_usmca_monthly` swaps to **monthly empirical rates** (USITC DataWeb). Same authority stacking, MFN exemptions, and IEEPA floor logic in all three; only the USMCA layer differs.

## Reusable Stata programs (`code/utils/programs.do`)

- `assign_partner_group <varname>` — maps Census country codes to 8 partner groups (China, CA, MX, EU, JP, KR, UK, ROW).
- `safe_divide <num> <den> <newvar> [default]` — handles zero-denominator division.
- `report_merge "<label>"` — reports match / master-only / using-only counts after `merge`.
- `build_month_rev_map, saving(...)` — produces ym → revision crosswalk.
- `compute_tier, ratevar() weightvar() outfile() outvar() [byvar() percent]` — tier ETR aggregation; operates on the in-memory dataset (caller `preserve`s/`restore`s). Used by 02's ladder, 03 Section D, and 06.
- `compute_diversion_decomp, ratevar() byvar() outfile() outvar_prefix()` — Shapley two-way decomposition of a fixed-rate-weights-shift gap into between-group + within-group components. Called against `rate_h2avg` to decompose S1→S2 trade diversion. Group is `partner_group` (country lens) or `product_group` (product lens). Both lenses sum to the same `gap_diversion`. Used by 03 Section B and 03b's USMCA adjustment explainer.
- `compute_per_group_attribution, ratevar_left() ratevar_right() weightvar() byvar() outfile() outvar()` — per-group dollar attribution under fixed weights: `(Σ_g rate_left × w − Σ_g rate_right × w) / Σ_total w`. Used for S2→S3 (`rate_h2avg` vs `rate_all_pref`) and S3→S4 (`rate_all_pref` vs `census_etr`) per-group breakdowns. Distinct from `compute_diversion_decomp` because the weights-fixed case is mechanically zero on the between-group Shapley term.
- `classify_pref_channel <subco> <rateprov> <cty>` — bins IMDB entries into 9 preference / rate-provision channels (mirrored in R section 3f). Used by 04 and 05a/05b.
- `export_fig <stub> [, width(N)]` — graph export to `${figures}<stub>.png` at 2400 px width by default.
- HS2 chapter labels (`hs2_lbl`, 99 chapters).

## Data sources

| Source | Repo / API | What |
|--------|------------|------|
| Census IMDB bulk | `census.gov/trade/downloads/` | HS10 × country × district × preference detail (primary monthly source; HS2 rollups derived from this) |
| Census Bureau API | `api.census.gov` | HS2 × country monthly trade — opt-in via `--with-census`; not consumed by the Stata pipeline |
| Tariff Rate Tracker | [`Budget-Lab-Yale/tariff-rate-tracker`](https://github.com/Budget-Lab-Yale/tariff-rate-tracker) | HTS10 × country statutory rates, daily ETR, import weights |
| Tariff Impact Tracker | [`Budget-Lab-Yale/tariff-impact-tracker`](https://github.com/Budget-Lab-Yale/tariff-impact-tracker) | Monthly actual ETR (Treasury customs duties / imports) |

`--refresh-tracker` shells out to the tracker repo and rebuilds its outputs end-to-end before the export step; this requires `DATAWEB_API_TOKEN` set in `tariff-rate-tracker/.env` (free token from <https://dataweb.usitc.gov>) and ~60–90 minutes. Both sibling repos publish their own setup instructions.

## Output

Every figure is exported in two versions: `figure_X.png` (no titles/subtitles, default for slides) and `figure_X_titled.png` (with titles/subtitles, for the paper draft).

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

**R** (Step 0 only): `httr`, `jsonlite`, `dplyr`, `readr`, `here`, `stringi`, `yaml`.

**Stata 17+**: `ftools`, `reghdfe`, `gtools`, `estout`, `coefplot`, `plotplainblind`, `heatplot` (with deps `palettes`, `colrspace`). Install with:

```stata
ssc install ftools, replace
ssc install reghdfe, replace
ssc install gtools, replace
ssc install estout, replace
ssc install coefplot, replace
ssc install plotplainblind, replace
ssc install heatplot, replace
ssc install palettes, replace
ssc install colrspace, replace
```

Set `CENSUS_API_KEY` in `~/.Renviron` for Census API access.

## Key configuration (`code/utils/globals.do`)

- Path globals: `$dir`, `$code`, `$data`, `$raw`, `$working`, `$results`, `$figures`, `$tables`.
- Analysis window: `$start_ym` to `$end_ym` (Jan 2025 – Feb 2026).
- Partner groups: China, Canada, Mexico, EU, Japan, S. Korea, UK, ROW.
- Product groups (9, defined in `resources/product_groups.csv`, merged into `merged_analysis.dta` in 01): Steel & Aluminum, Autos & Auto Parts, Electronics & Machinery, Pharmaceuticals, Energy & Minerals, Chemicals & Plastics, Apparel & Textiles, Food & Agriculture, Other Manufactured.
- Policy event dates: `$event_fentanyl`, `$event_liberation`, etc. (for figure reference lines).
- Color palette: `$color_actual` (red), `$color_statutory` (navy), `$color_gap` (green); partner-specific colors `$color_china/canada/mexico/...`; product-specific colors `$color_steel/autos/elec/pharma/energy/chem/apparel/food/other`.
- Graph scheme: `plotplainblind` (colorblind-friendly).

## Conventions

- Orchestrator naming: `00_etr_eval.do` (numeric prefix `00_` signals top-level runner).
- Stata globals defined centrally in `globals.do`, never hardcoded in analysis scripts.
- All raw data written to `data/raw/`, intermediate `.dta` to `data/working/`, final output to `results/`.
- R uses `here::i_am()` for path resolution; Stata uses `$dir` auto-detected from `c(pwd)`.
- Census country codes are strings (e.g., "5700" = China), mapped via `assign_partner_group`.

## Further reading

- `docs/six_tier_framework_plan.md` — math derivation (Shapley two-way, applicability matrix, sign-bearing channel discussion).
- `docs/paper_outline_v2.md` — current paper outline, with figure-name map, Shapley derivation, and Eck et al. (2026) cross-validation.
- `docs/weighting_note.md` — value-weighted aggregation, importance of including zero-tariff products.
- `docs/etr-literature-review.md` — context on the statutory-actual ETR gap literature.
- `docs/tracker_miss_report.md` / `docs/tracker_over_report.md` — diagnostic handoffs to the `tariff-rate-tracker` maintainer (false-negative and false-positive rate-parsing errors).
- `docs/tracker_audits/` — audit memos resolving specific tracker bug findings.

## License

MIT — see `LICENSE`. Copyright © 2026 The Budget Lab at Yale.
