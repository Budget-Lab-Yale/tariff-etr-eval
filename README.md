# Tariff ETR Evaluation

Comparing actual vs. statutory effective tariff rates during the 2025–2026 US tariff escalation.

## Overview

This project evaluates the gap between **statutory** tariff rates (what the Harmonized Tariff Schedule says importers should pay) and **actual** collection rates (customs duties collected as a share of import value). The gap is decomposed into USMCA adjustment, trade diversion, all-other preferences, residual, and timing/enforcement channels using a **six-tier framework** (S0 → S1 → S2 → S3 → S4 → T). See [Six-tier framework](#six-tier-framework) below; `docs/six_tier_framework_plan.md` carries the full math derivation and per-authority applicability matrix.

The pipeline is **pure R**, structured like the sibling production repo [`tariff-etr-adj`](../tariff-etr-adj) (data → analysis → figures, with figures reading only CSV outputs). The original Stata pipeline is preserved in `archive/stata/` and was used as the numerical golden reference for the port (`scripts/verify_r_port.R`).

## Pipeline

```
00_run_all.R                      orchestrator (logs to logs/run_all_*.log)
├── 01a  code/01a_pull_raw_data.R       raw data pull (on demand; ~30–60 min)
├── 01b  code/01b_build_panel.R         data/raw CSVs -> data/processed/panel.rds
├── 02a  code/02a_ladder.R              tiers S0–S4 + T, channel gaps, strips
├── 02b  code/02b_decomposition.R       Shapley diversion + attributions + cmp_*
├── 02c  code/02c_vmr.R                 value-misreporting decomposition
├── 03a  code/03a_figures_framework.R   framework + VMR figures
└── 03b  code/03b_figures_baseline.R    paper baseline figures
```

| Layer | Inputs | Outputs |
|---|---|---|
| 01 (data) | Census IMDB bulk, tracker publish/checkout, Treasury snapshot | `data/raw/*.csv`, `data/processed/panel.rds` |
| 02 (analysis) | `panel.rds`, `data/raw` | `results/tables/*.csv` only |
| 03 (figures) | `results/tables/*.csv` **only** | `results/figures/*.png` (each as `<stub>.png` clean + `<stub>_titled.png`) |

Shared machinery lives in `code/utils.R` (partner/product partitions, Wong colorblind-safe palette, `compute_tier`, Shapley two-way `shapley_decomp`, `per_group_attribution`, tracker-vintage stamping, `save_fig`). The strip modules in `code/strips/` (ported from `tariff-etr-adj`) decompose the S4→T timing gap in-memory; they never modify `data/`.

### Step 01a — raw data pull (`code/01a_pull_raw_data.R`)

Pulls Census IMDB bulk ZIPs, tracker statutory-rate snapshots + daily ETRs (from the shared publish when configured in `config/local_paths.yaml`, else a sibling checkout), USMCA counterfactual reconstructions, non-USMCA preference shares, and Treasury revenue (vendored snapshot `resources/treasury_revenue.csv`). Flags:

```bash
Rscript code/01a_pull_raw_data.R                       # full pull
Rscript code/01a_pull_raw_data.R --only-imdb           # IMDB CSVs from cached ZIPs
Rscript code/01a_pull_raw_data.R --only-tracker        # tracker sections only
Rscript code/01a_pull_raw_data.R --only-counterfactual # counterfactual panels only
Rscript code/01a_pull_raw_data.R --refresh-tracker     # rebuild tracker first (~hours, DataWeb token)
Rscript code/01a_pull_raw_data.R --tracker-data=PATH   # pin a publish vintage
Rscript code/01a_pull_raw_data.R --no-shared-tracker   # force sibling checkout
```

**Publish vs full mode.** Since publish vintage `2026-06-10-22` the shared publish carries the USMCA scenario snapshots (`scenarios/usmca_2024`, `scenarios/usmca_monthly`), so publish mode builds the S0 panel (`rate_2024`) and `rate_usmca_monthly` and the ladder runs the full S0–S4 + T. Against older vintages the pipeline auto-detects the missing scenarios (`have_s0` attribute on `panel.rds`) and degrades to S1–S4 + T. A tracker checkout with `DATAWEB_API_TOKEN` is now needed only to rebuild tracker data itself (`--refresh-tracker`). See `docs/shared_publish_extensions.md` and `docs/open_questions.md` #2.

### Step 01b — panel build (`code/01b_build_panel.R`)

One row per (HS10 × country × month) over the analysis window: Census value/duty/quantity, the day-weighted statutory rate panels (`rate_h2avg` for S1/S2, `rate_all_pref` for S3, `rate_2024` for S0 when present), 2024 + monthly weights, partner/product partitions. Integrity checks (key uniqueness, non-negative rates, S3 ≤ S2) fail fast. The per-revision `tracker_snapshots` merge from the Stata pipeline is deliberately not ported (only the archived 06 diagnostic consumed it).

### Step 02a — ladder (`code/02a_ladder.R`)

Computes the tiers and channel gaps (definitions below), joins Treasury, and — new relative to the Stata pipeline — decomposes `gap_timing` (S4 − T) into:

- **de-minimis postal channel** — carrier-remitted duty with no Census entry counterpart, estimated from the step in the monthly Treasury−Census duty gap at the 2025-09 global de-minimis break (`code/strips/deminimis_strip.R`);
- **AD/CVD deposits** — in Treasury but structurally excluded from Census `cal_dut_mo` (interim curated level in `resources/adcvd_collected.csv`, single source of truth in `tariff-etr-adj`);
- **residual timing/enforcement** — what remains.

Headline tables are stamped with the tracker vintage (`tracker_vintage` column; `results/tables/run_meta.csv` records vintage + window per step).

### Step 02b — decompositions (`code/02b_decomposition.R`)

S1→S2 trade-diversion Shapley two-way (between/within) under the country and product partitions — both lenses sum to `gap_diversion` and are validated against the ladder each run; S2→S3 and S3→S4 per-group attributions; S0→S1 attribution in full mode; `cmp_*` comparison tables (S2 vs S4 vs T by partner/product, HS2 ranking, top-HS10 anomalies, S1 vs S2 by group).

### Step 02c — value misreporting (`code/02c_vmr.R`)

Decomposes post-tariff import-value changes into real flow change vs value under-invoicing using the identity Δln(value) = Δln(quantity) + Δln(unit value) around each flow's tariff event, with a cross-partner within-product control. Orthogonal to the η compliance gap (under-invoicing moves duty and value proportionally). Method: `docs/value_misreporting_methodology.md`; planned upgrades (placebo floor, dose-response, related-party split): `docs/vmr_v2_proposal.md`.

## Running the pipeline

```bash
Rscript 00_run_all.R                  # 01b -> 03b (default; needs data/raw populated)
Rscript 00_run_all.R --with-pull      # run the raw pull first
Rscript 00_run_all.R --skip-data      # 02a -> 03b, reuse panel.rds
Rscript 00_run_all.R --figures-only   # 03a + 03b only
```

On the BL cluster run via SLURM (`slurm/RUNBOOK.md`): `sbatch slurm/run_pull.sbatch` (stage 1, data) then `sbatch slurm/run_r.sbatch` (stage 2, analysis; ~5 min). The panel build freads a 73M-row rate file — use a compute node, not the login node. `slurm/run_stata.sbatch` runs the archived Stata pipeline for golden-reference comparisons.

### Validating against the Stata golden

```bash
sbatch slurm/run_stata.sbatch          # archived Stata pipeline -> results/tables
cp -a results results_stata_golden     # snapshot
sbatch slurm/run_r.sbatch              # R pipeline overwrites results/tables
Rscript scripts/verify_r_port.R        # numeric comparison, 1e-6 pp tolerance
```

## Six-tier framework

| Tier | Definition |
|------|------------|
| S0 | Statutory @ USMCA 2024 baseline shares × 2024 import weights *(full mode only)* |
| S1 | Statutory @ Post-July 2025 USMCA baseline shares × 2024 import weights (= the paper's headline statutory line) |
| S2 | Statutory @ Post-July 2025 USMCA baseline shares × monthly weights |
| S3 | + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs), monthly IMDB-derived shares |
| S4 | Census collected ETR (cal_dut / con_val at HS10 × cty, summed) |
| T  | Treasury actual ETR |

The waterfall decomposes the statutory–actual ETR gap into sequential channels. The S0→S1 step is "explainable backstory" (USMCA paperwork catch-up); main analysis lives between S1 and T.

1. **USMCA adjustment (S0 → S1)** — hold weights at 2024, shift USMCA from 2024 baseline (~38% CA / ~50% MX) to post-July 2025 baseline (~89% both). Mostly retrospective.
2. **Trade diversion (S1 → S2)** — hold rates, shift weights from 2024 to actual monthly. Decomposed Shapley two-way in 02b.
3. **All-other preferences (S2 → S3)** — non-USMCA preference claim shares from IMDB (`delta_base`/`delta_recip` math in `docs/six_tier_framework_plan.md` §6.6). Structurally non-negative.
4. **Residual (S3 → S4)** — statutory-with-preferences vs Census collected: specific-duty AVE failures, tracker error, behavioral noise.
5. **Timing / enforcement (S4 → T)** — Treasury vs Census aggregation: refunds, FTZ deferrals, cash-vs-accrual, **plus the de-minimis postal and AD/CVD channels now split out explicitly in 02a**.

The framework's S1 panel equals the tracker's daily ETR collapsed to monthly by construction, so the paper's headline §4.1 "baseline statutory" line is also S1.

### Aggregation methodology

All tiers are single-stage row-level value-weighted averages over the panel: `Σ(rate × weight) / Σ(weight)` (`compute_tier` in `code/utils.R`). Rate and weight columns sit on the same row; no HS2 bridging. Zero-tariff products **must be included** in the denominator (dropping them inflates the ETR from ~3.4% to ~27%). `rate_h2avg` is the tracker's production `total_rate` (USMCA at post-July-2025 claim rates), day-weighted within months; `rate_2024` and `rate_usmca_monthly` swap only the USMCA layer.

## Sibling repo dependencies

- [`Budget-Lab-Yale/tariff-rate-tracker`](https://github.com/Budget-Lab-Yale/tariff-rate-tracker) — statutory rates, daily ETR, import weights, revision dates, USMCA product shares. On the BL cluster the **shared publish** (`tracker_data_dir` in `config/local_paths.yaml`, copy from `config/local_paths.yaml.example`) replaces the checkout for snapshots + daily ETRs; the checkout is still needed for full-mode USMCA scenario panels.
- [`Budget-Lab-Yale/tariff-impact-tracker`](https://github.com/Budget-Lab-Yale/tariff-impact-tracker) — Treasury revenue. Optional: the vendored snapshot `resources/treasury_revenue.csv` (provenance: `resources/treasury_revenue_SOURCE.md`) makes the pipeline self-contained.
- [`tariff-etr-adj`](../tariff-etr-adj) (private sibling) — **production home of the η compliance-gap calibration**. The η work formerly in this repo is archived (`archive/eta/`) to avoid drifting implementations; this repo's VMR decomposition is the base-erosion sidecar to adj's `eta_by_*` deliverables.

## Data sources

| Source | What |
|--------|------|
| Census IMDB bulk (`census.gov/trade/downloads/`) | HS10 × country × district × preference detail; value, duty, quantity, shipping weight |
| Tariff Rate Tracker (publish or checkout) | HTS10 × country statutory rates, daily ETR, import weights, revision dates |
| Treasury (vendored Haver snapshot) | Monthly customs duties + goods imports (actual ETR) |
| USITC DataWeb SPI | USMCA product-level utilization shares (full mode) |

## Repository layout

```
00_run_all.R              orchestrator
code/                     pipeline (01a/01b/02a/02b/02c/03a/03b, utils.R, strips/)
scripts/                  verify_r_port.R, verify_counterfactuals.R
slurm/                    RUNBOOK.md + sbatch runners (logs/ gitignored)
resources/                committed inputs (product groups, Treasury snapshot,
                          AD/CVD curated level, crosswalks, policy events)
data/raw|imdb|processed/  gitignored, rebuilt by 01a/01b
results/tables|figures/   gitignored, rebuilt by 02*/03*; run_meta.csv carries
                          the tracker vintage per step
docs/                     method notes, paper outline, open_questions.md tracker
paper/                    paper draft (Rmd)
archive/stata/            retired Stata pipeline (golden reference for the port)
archive/eta/              η calibration (production home: tariff-etr-adj)
archive/exploratory/      GTAP validation + AD/CVD spot checks
```

## Requirements

R ≥ 4.4 with `dplyr`, `tidyr`, `readr`, `data.table` (+`bit64`), `ggplot2`, `scales`, `here`; `yaml`/`jsonlite` for config + vintage resolution; `arrow` only for the publish-reading sections of 01a. No Stata required (the archive needs Stata 17+ with `gtools` if re-run).

## Conventions

- `year_month` is a `"YYYY-MM"` string key everywhere in R; tier values in percent, gaps in pp, panel rates as ratios.
- Every figure exports as `<stub>.png` (clean, slides) + `<stub>_titled.png` (paper).
- Design debt and deferred ports are tracked in `docs/open_questions.md` — update it in the same commit as the change.

## Further reading

- `docs/six_tier_framework_plan.md` — framework math and applicability matrix
- `docs/value_misreporting_methodology.md` + `docs/vmr_v2_proposal.md` — VMR method and v2 design
- `docs/eta_calibration_methodology.md` — η methodology (work lives in tariff-etr-adj)
- `docs/etr-literature-review.md` — related literature
- `docs/paper_outline.md` — paper structure and headline results

## License

MIT — see `LICENSE`.
