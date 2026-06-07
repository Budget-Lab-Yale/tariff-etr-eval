# Tracker shared-publish extensions requested by `tariff-etr-eval`

**To:** John (tariff-rate-tracker maintainer)
**From:** John Iselin (tariff-etr-eval)
**Date:** 2026-06-07
**Re:** contents of the shared `model_data/Tariff-Rate-Tracker/` publish on the BL cluster

## Context

`tariff-etr-eval` now reads the shared tracker publish directly (as of the
2026-06-07 change to `code/R/00_pull_raw_data.R`). Against the current
publish (vintage `2026-06-06`, commit `1df7abd0e`, schema 2.0) we consume
the per-revision rate snapshots (`actual/snapshots/valid_from=*/rates.parquet`)
and the daily ETR files (`actual/daily/`), and we derive revision dates from
the `valid_from=` layout. That covers everything we need **except the items
below, which only the tracker build can produce**. Everything else
(import weights, USMCA share files, revision policy-event annotations) we
can generate or copy ourselves from the public repo — see the last section.

## 1. USMCA scenario snapshot series — the main ask

The six-tier framework's counterfactual ladder (S0/S1/S2/S3) needs
per-revision snapshots built under alternative USMCA utilization
assumptions (previously `data/timeseries/<scenario>/snapshot_<rev>.rds`,
built by `src/build_usmca_scenarios.R`):

- `usmca_none` — 0% utilization (upper bound)
- `usmca_2024` — 2024 annual claim shares (S0)
- `usmca_monthly` — monthly empirical shares from DataWeb SPI (explainer)
- `usmca_h2avg` — post-July-2025 average shares (S1/S2; equals the
  production `total_rate`, so this one may be redundant with `actual` —
  confirm and we can drop it)

We cannot self-serve this one: the scenario rates must come from the **same
rate engine and vintage** as the published `actual` series (the framework
depends on scenario-vs-production consistency, e.g. `usmca_h2avg` ≡
production `total_rate` by construction). Building them ourselves from a
checkout of a different branch/engine than the one that produced the
publish would silently break that. As far as we can tell the scenario
builder hasn't been ported to the `theseus` engine yet — happy to discuss
scope.

**Requested layout** — the manifest's `series` map already supports this:

```
<vintage>/
├── actual/snapshots/valid_from=*/rates.parquet      # existing
├── usmca_none/snapshots/valid_from=*/rates.parquet
├── usmca_2024/snapshots/valid_from=*/rates.parquet
└── usmca_monthly/snapshots/valid_from=*/rates.parquet
```

Only three columns are consumed per scenario row: `hts10`, `country`,
`total_rate` (plus the embedded `revision`). A slimmed schema for the
scenario series is fine if that keeps build time/size down.

Alternative if per-revision series are too expensive: publish the four
**day-weighted monthly panels** (HS10 × country × month `total_rate`,
day-weighted across revisions within month) and we consume those directly.
Per-revision snapshots are preferred — they keep the day-weighting logic in
one place (ours) and stay consistent with the `actual` series layout.

## 2. Manifest fix: `country_code_vocabulary`

The manifest declares:

```json
"country_code_vocabulary": "ISO-3166-1 alpha-3 (column: country)"
```

but the `country` column in `rates.parquet` (and `daily_by_country.csv`)
carries **Census numeric country codes** as strings (`"5700"` China,
`"1220"` Canada, …). That's what we want — just fix the manifest string so
future consumers don't convert against the wrong vocabulary.

## 3. Minor: `s232_usmca_eligible` column

The RDS snapshots carry `s232_usmca_eligible` (232 auto/MHD USMCA
eligibility flag); `rates.parquet` does not. etr-eval degrades gracefully
(`01_etr_clean.do` guards with `capture confirm variable`), but if the
column is cheap to include in the parquet schema we'd take it for parity.

## 4. Reproducibility ask

Please keep dated vintage directories around once etr-eval results are
produced against them (we log `vintage` + `git.commit` from the manifest on
every run, and can pin via `--tracker-data=…/<vintage>`). A note in the
manifest when a vintage supersedes a broken one (like `2026-06-04_2`) would
also help.

## Not asking for — we self-serve these

For your awareness, the following are handled on our side and need nothing
from you:

- **2024 import weights** — gitignored build artifact on your side; we
  rebuild from your committed `src/build_import_weights.R` against the same
  Census IMDB inputs (deterministic, so it matches the weights behind the
  published daily series). If the weights methodology ever changes, a bump
  in the manifest notes would be appreciated.
- **USMCA product share files** (`resources/usmca_product_shares_*.csv`) —
  git-tracked in your repo; we copy from a checkout.
- **Revision policy-event annotations** (`config/revision_dates.csv`) —
  git-tracked in your repo; we keep a vendored copy refreshed from it
  (dates themselves come from the publish's `valid_from` layout).

## What we verified against the 2026-06-06 vintage (no action needed)

- 42 `valid_from=` dirs ↔ 42 unique `revision` values (`basic` … `rev_32`,
  `2026_basic` … `2026_rev_9`); `valid_from` matches the re-dated
  (policy-effective) dating, which we treat as authoritative.
- `rates.parquet` carries every other column etr-eval reads
  (`total_rate`, `statutory_rate_*`, `statutory_base_rate`, metal shares,
  `usmca_eligible`).
- `rate_unit: "fraction"` matches our Stata assumptions; we warn at run
  time if a future vintage changes it.
- `daily_overall.csv` / `daily_by_country.csv` schemas match what
  `01_etr_clean.do` B1/B2 imports.
- Coverage (snapshots through 2026-05-01, dailies through 2026-06) spans
  our analysis window.
