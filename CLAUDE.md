# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Evaluates the gap between **statutory** U.S. tariff rates (from the Harmonized Tariff Schedule) and **actual** collected rates (customs duties / import value) during the 2025-2026 tariff escalation. Decomposes the gap into trade diversion, USMCA surge, all-other preferences, residual, and timing/enforcement channels using a **six-tier framework** (S0 → S1 → S2 → S3 → S4 → T). See `docs/six_tier_framework_plan.md` for derivation and the per-authority applicability matrix.

## Pipeline

The pipeline has two stages. R assembles raw data; Stata cleans, merges, and analyzes.

```
Rscript code/R/00_pull_raw_data.R     # Step 0: populate data/raw/ from APIs + sibling repos
do 00_etr_eval.do                      # Steps 1-6: clean → ladder → analysis → fta → crosscheck → diagnostic
```

### Step 0 — R data assembly (`code/R/00_pull_raw_data.R`)

Pulls from four sources and writes CSVs to `data/raw/`. Sections can be toggled via command-line flags (see "Running the pipeline").

- **Section 1 — Census API** (HS2 x country x month, *opt-in via `--with-census`*): consumption value, calculated duty, dutiable value. Output is no longer consumed by the Stata pipeline — HS2-level rollups aggregate IMDB HS10 data instead. Section is retained for ad-hoc use and to seed the Section 2b HS10 fallback.
- **Section 2 — Census IMDB bulk ZIPs** — two outputs:
  - `imdb_detail.csv`: HS10 x country x district x preference x rate_prov x month (for FTA decomposition, district crosscheck)
  - `imdb_hs10_country_monthly.csv`: aggregated to HS10 x country x month (for main pipeline)
  - Census API HS10 fallback: fills months not yet available in IMDB bulk (auto-detected)
- **Section 3a-3c — tariff-rate-tracker** (sibling repo): converts RDS snapshots to CSV (including `statutory_rate_*` pre-USMCA components), copies daily ETRs, revision dates, 2024 import weights
- **Section 3d-3e — USMCA counterfactual rate reconstruction**: copies USMCA product-level utilization shares from tracker (2024 annual + monthly 2025-2026 from USITC DataWeb SPI data), then reconstructs HS10 x country x month rates by applying shares to pre-USMCA statutory components and day-weighting across revisions within months. Output: `counterfactual_usmca2024.csv` and `counterfactual_usmca_monthly.csv`
- **Section 3f — Non-USMCA preference shares from IMDB**: aggregates `imdb_detail.csv` by (HS10, country, month) and classifies into 9 preference channels (USMCA, KORUS, other_fta, GSP/AGOA, duty_free, ch99_dutiable, mfn_dutiable, ftz_bonded, other) via `classify_pref_channel`. Output: `imdb_other_pref_shares_monthly.csv` with per-channel shares per cell.
- **Section 3g — S2 → S3 preference-delta file**: computes the per-cell rate reduction `delta_base + delta_recip` from non-USMCA preference shares × pre-preference component rates. Output: `counterfactual_other_pref_delta_monthly.csv` (sparse, only cells with positive non-USMCA preference share). See `docs/six_tier_framework_plan.md` §6.6 for derivation.
- **Section 4 — tariff-impact-tracker** (sibling repo): Treasury revenue (actual ETR)

### Step 1 — Stata clean & merge (`code/01_etr_clean.do`)

Imports all CSVs, assigns partner groups, maps months to HTS revisions, merges Census HS10 trade data with tracker snapshot rates on `(hs10, country, revision)`, and merges in three counterfactual rate panels (B6 `cf_usmca_monthly.dta` → `rate_usmca_monthly` for S2; B7 `cf_usmca2024.dta` → `rate_2024` for S0/S1; B8 `cf_pref_delta.dta` → `rate_all_pref` for S3). Computes 2024 fixed weights and monthly weights. Output: `data/working/merged_analysis.dta` carrying `total_rate`, `rate_2024`, `rate_usmca_monthly`, `rate_all_pref`, `imports`, `con_val_mo` on every row.

### Step 2 — Counterfactual ladder (`code/02_counterfactual_ladder.do`)

Thin script. Loads `merged_analysis.dta` and calls `compute_tier` 4× for the aggregate ladder (S0/S1/S2/S3) and 4× for the country ladder, joins T from `revenue_monthly.dta`. Single source of truth for ladder values consumed by Step 3.
- S0: `rate_2024 × imports` (USMCA frozen 2024 × 2024 wts)
- S1: `rate_2024 × con_val_mo` (USMCA frozen 2024 × monthly wts)
- S2: `rate_usmca_monthly × con_val_mo` (USMCA monthly × monthly wts)
- S3: `rate_all_pref × con_val_mo` (S2 minus non-USMCA preference delta × monthly wts)
- T:  Treasury actual

Output: `counterfactual_ladder.dta` (overall) + `counterfactual_by_country.dta` (by partner_group).

### Step 3 — Stata analysis (`code/03_etr_analysis.do` + `code/03b_baseline_figures.do`)

Step 3 runs two scripts back-to-back. **03** is the framework decomposition; **03b** is the TBL-judgment paper-output figures using a separate methodology.

**`03_etr_analysis.do`** — Six-tier decomposition. Section A reads S0/S1/S2/S3 + T from `counterfactual_ladder.dta` and adds S4 (Census collected ETR):
- **S0**: Statutory @ 2024 USMCA shares × 2024 weights
- **S1**: Statutory @ 2024 USMCA shares × monthly weights
- **S2**: Statutory @ monthly USMCA shares × monthly weights
- **S3**: + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
- **S4**: Census collected ETR (cal_dut / con_val at HS10 × country, summed)
- **T**: Treasury actual ETR

Gap channels: S0→S1 = trade diversion, S1→S2 = USMCA surge, S2→S3 = all-other preferences, S3→S4 = residual, S4→T = timing/enforcement. **`gap_diversion` and `gap_usmca` are bidirectional** (negative country-period averages for CA/MX = "reverse diversion"; negative early-period months for USMCA = pre-ramp claim-rate dip). `gap_others` is structurally non-negative by the delta math. See `docs/six_tier_framework_plan.md` §5a. Section B (Shapley between/within) still uses h2avg `total_rate` — legacy, conceptually a different question. Section D (figs 4–6) uses `compute_tier` on `rate_usmca_monthly` so its statutory line is identical-by-construction to S2.

**`03b_baseline_figures.do`** — TBL-judgment paper figures using a separate aggregation methodology (tracker daily series, h2avg USMCA, 2024 weights). These are intended for ECONOMIC portrayal of the statutory schedule — they are NOT framework tiers and should not be conflated with S0–S3. Outputs: `figure_baseline_etr.png` (paper §4.1), `figure_daily_overlay.png` (paper §4.5), and `monthly_summary.xlsx` (supplementary table that gathers all six statutory ETRs × {2024, monthly} weights alongside T3/T4/S3 in one sheet).

### Step 4 — FTA decomposition (`code/04_fta_decomposition.do`)

Decomposes the T2->T3 exemptions gap into preference channels using IMDB detail data (`cty_subco`, `rate_prov`): USMCA, KORUS, other FTAs, GSP/AGOA, duty-free entries, ch99 dutiable, MFN dutiable. Also computes USMCA/KORUS utilization rates. Requires `imdb_detail.csv`.

### Step 5 — Max-district crosscheck (`code/05_max_district_crosscheck.do`)

Validates tracker statutory rates against max observed ETR across customs districts per HS10 x country. Classifies into match/tracker_higher/observed_higher. Tracker-higher = universal preference use; observed-higher = possible tracker parsing error. Requires `imdb_detail.csv`.

### Step 6 — Baseline ETR diagnostic (`code/06_baseline_etr_diagnostic.do`)

Diagnostic at 2024 weights comparing tracker `total_rate` (baseline USMCA already applied) vs the `rate_2024` reconstruction (cf_usmca2024). Both use 2024 baseline USMCA assumptions, so any gap between them isolates reconstruction methodology; matched/nonzero universe slices isolate zero-rate-dropping and unmatched-product effects. Builds its own panel from `weights_2024.dta` (different universe from `merged_analysis.dta`). Output: figure 7 + diagnostic table.

## Running the pipeline

### R data pull (Step 0)

```bash
Rscript code/R/00_pull_raw_data.R                       # IMDB + tracker + impacts (~30-60 min)
Rscript code/R/00_pull_raw_data.R --with-census          # also pull Census HS2 API (hours)
Rscript code/R/00_pull_raw_data.R --skip-imdb            # skip IMDB bulk downloads
Rscript code/R/00_pull_raw_data.R --only-tracker         # sections 3-3e only (~15 min)
Rscript code/R/00_pull_raw_data.R --only-counterfactual  # sections 3d-3g only (~10 min)
Rscript code/R/00_pull_raw_data.R --refresh-tracker      # rebuild tracker first (~hours)
```

Use `--only-tracker` after updating the tracker repo to regenerate snapshot CSVs, USMCA shares, and counterfactual rate files. Use `--refresh-tracker` to rebuild the tracker end-to-end (revision dates, HTS JSON, DataWeb USMCA shares, top-level + per-scenario snapshots, daily ETRs) before the export steps; requires `DATAWEB_API_TOKEN` in `tariff-rate-tracker/.env` and may halt at `01_scrape_revision_dates.R` if a new HTS revision needs manual policy-date curation. Composes with the other flags.

### Stata pipeline (Steps 1-6)

```stata
cd "C:/Users/ji252/Documents/GitHub/tariff-etr-eval"
do 00_etr_eval.do
```

Toggle steps via globals in `code/utils/globals.do` (execution order):
- `$run_pull` (Step 0): R data pulls (hours-long)
- `$run_clean` (Step 1): import, clean, merge → `merged_analysis.dta`
- `$run_ladder` (Step 2): counterfactual ladder → `counterfactual_ladder.dta`
- `$run_analysis` (Step 3): six-tier decomposition and figures (consumes ladder)
- `$run_fta` (Step 4): FTA/preference decomposition (needs `imdb_detail.csv`)
- `$run_crosscheck` (Step 5): max-district validation (needs `imdb_detail.csv`)
- `$run_baseline` (Step 6): baseline ETR diagnostic

## Sibling repo dependencies

Both must be at the same directory level as this repo:
- `tariff-rate-tracker` — statutory rates, daily ETR, import weights, revision dates, USMCA product shares (from USITC DataWeb SPI data)
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
- `report_merge "<label>"` — reports match / master-only / using-only counts after `merge`
- `build_month_rev_map, saving(...)` — produces ym → revision crosswalk
- `compute_tier, ratevar() weightvar() outfile() outvar() [byvar() percent]` — tier ETR aggregation; operates on the in-memory dataset (caller `preserve`s/`restore`s). Used by 02's ladder, 03 Section D, and 06.
- `classify_pref_channel <subco> <rateprov> <cty>` — bins IMDB entries into 9 preference / rate-provision channels (mirrored in R section 3f). Used by 04 and 05a/05b.
- HS2 chapter labels (99 chapters)

## Aggregation methodology

All ETR tiers are computed via single-stage row-level value-weighted averages over the (HS10 × country × month) cells of `merged_analysis.dta`: `Sum(rate × weight) / Sum(weight)`. Rate columns (`rate_2024`, `rate_usmca_monthly`, `rate_all_pref`, `total_rate`) and weight columns (`imports` for 2024, `con_val_mo` for monthly) sit on the same row, so `compute_tier` collapses are uniform across tiers and figures. No HS2 bridging — that older description was inaccurate.

Zero-tariff products **must be included** in the denominator. Dropping them inflates the ETR from ~3.4% to ~27%. See `docs/weighting_note.md`.

## Six-tier framework (Steps 2 + 3)

The waterfall decomposes the statutory-actual ETR gap into five sequential channels:

1. **Trade diversion (S0 → S1)**: hold USMCA at 2024 baseline, shift from 2024 to actual monthly import weights. Composition shift in trade flows. Sign-bearing — negative ("reverse diversion") for CA/MX/China/ROW because their imports are concentrated in inelastic high-tariff categories.
2. **USMCA surge (S1 → S2)**: hold monthly weights fixed, shift USMCA from 2024 shares to actual monthly shares. CA/MX claim-rate dynamics (~38% → ~89% for CA, ~50% → ~89% for MX by late 2025). Sign-bearing — negative in 2025m1–m2 (claim rates briefly below baseline before the ramp).
3. **All-other preferences (S2 → S3)**: apply non-USMCA preference claim shares (Annex II / ITA / Ch98 / KORUS / GSP / other_fta) from IMDB. Per-authority math: `delta_base = (s_duty_free + s_korus + s_gsp + s_other_fta) × base_rate_pre`, `delta_recip = s_duty_free × recip_rate_pre`. Structurally non-negative.
4. **Residual (S3 → S4)**: remaining gap between statutory (with all preferences applied) and Census collected. Captures specific-duty AVE failures, AD/CVD, tracker error not yet corrected, behavioral noise within HS10 × cty cells.
5. **Timing/enforcement (S4 → T)**: Treasury vs Census aggregation. Refunds, post-entry adjustments, FTZ deferrals, cash-vs-accrual timing.

USMCA shares are product-level (HS10 × country) from USITC DataWeb SPI program codes (S/S+). Non-USMCA preference shares come from IMDB importer-declared `cty_subco` and `rate_prov` fields, classified via `classify_pref_channel`. The applicability matrix encoded in tracker steps 6c (FTA/GSP for `base`) and 7 (USMCA for `base`/`recip`/`fent`/`232`/`s122` with `0.40` content rule for auto/MHD) is preserved by the R reconstruction logic. See `docs/six_tier_framework_plan.md` §6 for the full math, including the per-preference applicability matrix and sign-reversal explanation.

## Conventions

- Orchestrator naming: `00_etr_eval.do` (numeric prefix `00_` signals top-level runner)
- Stata globals defined centrally in `globals.do`, never hardcoded in analysis scripts
- All raw data written to `data/raw/`, intermediate .dta to `data/working/`, final output to `results/`
- R uses `here::i_am()` for path resolution; Stata uses `$dir` auto-detected from `c(pwd)`
- Census country codes are strings (e.g., "5700" = China), mapped via `assign_partner_group`
- User frequently edits files externally; always re-read before editing
