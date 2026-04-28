# Ch99-dutiable trackerover — China stacking pattern

**Date**: 2026-04-28
**Triggered by**: `tracker_over_report.md` Round 1 ch99_dutiable finding (~$42 B)
**Status**: pattern characterized; fix path mixed (some parser, some empirical calibration)

## Finding

The trackerover Round 1 BUG-LIKELY ch99_dutiable bucket (rate_prov 69 + 79) is $42.2 B. Spot-check of the top 25 cells: **all are China-origin**. Concentration:

| HS10 | Description | Top trackerover cells | Tracker rate composition (rev_17+) |
|---|---|---|---|
| 8507.60.0020 | Lithium-ion batteries | $230–520 M / month from China | base 2 % + §232 23.8 % + §301 25 % + IEEPA recip 0–34 % + fent 10 % |
| 8517.62.0090 | Telecom apparatus | $90–140 M / month | base 0 % + §301 25 % + IEEPA recip variable |
| 8471.30.0100 | Portable ADP (laptops/tablets) | $90–110 M / month | base 0 % + §232 23.8 % (derivative aluminum) + §301 25 % + fent 10 % |
| 6307.90.9891 | Other made-up textile articles | $80–135 M / month | base 7 % + §301 50 % + fent 10 % |
| 9503.00.0073 | Toys (dolls) | $180 M+ at peak | §301 + fent + base |
| 3924.10.4000 | Plastic kitchenware | $90 M | §301 + fent + base |
| 8708.70.4548 | Auto parts | $45 M (rev_6) | §232 auto + §301 + IEEPA recip + fent |

Spot-check vs. snapshots in `data/timeseries/snapshot_rev_*.rds` confirmed each cell's tracker rate is the sum of authority layers from ch99 entries — no rate-parsing bug per cell. The cells are *legitimately* stacked at the rates the tracker computes.

## Why Census collection is lower

The tracker's stacked rate represents the *maximum* theoretical statutory burden on a China-origin product subject to all applicable authorities. Census-collected duty is lower because:

1. **Importer entry-timing optimization.** Importers can clear entries during windows when specific authorities are suspended or pending. China-IEEPA-reciprocal in particular spiked from 34 % → 84 % → 125 % across rev_7–9 (April 5–9, 2025), then suspended at rev_17 (post-Geneva). Goods cleared in different sub-windows of a calendar month face different rates; the eval pipeline's monthly-weighted tracker rate captures the average, but Census duty captures the *actual* mix of entry timings.
2. **Bonded warehouse / FTZ entries.** Some imports defer duty via FTZ. Those entries appear in IMDB at low effective rates.
3. **Product-level §232 derivative scaling.** §232 derivative rates apply to aluminum/steel content only; tracker scales by `aluminum_share` from BEA I-O. Census-collected reflects the realized content mix, which may differ from the tracker's BEA-derived share for specific HTS10s.
4. **Section 232 effective-date misalignment.** Documented separately in `s232_auto_effective_date_2026-04-28.md`. Affects auto parts (8708) cells specifically and likely accounts for a portion of the ch99_dutiable signal in March/April 2025 for chapter 87 codes.
5. **§301 list-versioning edge cases.** Trump-era and Biden-era §301 lists overlap on some products with different rates; the tracker's MAX-across-lists rule may pick the higher rate when actual collection used a lower one.

## Diagnosis

This is **not a single fixable bug**. It is a mix of:

- **Real parser bugs** (§232 effective-date — already documented; potentially others)
- **Calibration gaps** (semi `qualifying_share` — already addressed; possibly metal-share for batteries; §232 derivative coverage)
- **Modeling vs. reality** (entry-timing, FTZ, bonded warehouse — not fixable in a statutory-rate model)

The third category is structural: a statutory-rate model that day-weights across revisions inherently *over-states* what importers actually pay during transition windows. This is the same conceptual gap the four-tier ETR decomposition in `tariff-etr-eval` is built to attribute (Tier 2 → Tier 3 = exemptions / timing / enforcement).

## What's actually fixable here

Of the ~$42 B ch99_dutiable trackerover, plausible attributions:

| Category | Estimated $ | Fix path |
|---|---:|---|
| §232 auto effective-date misalignment (March 2025) | $5–8 B | Parser fix (separate memo) |
| §232 derivative metal-share recalibration | $5–10 B | Empirical calibration via Census data |
| §301 list-versioning (max vs. realized) | $2–5 B | Diagnostic-only — TPC confirmed mutual exclusion |
| Lithium-ion battery §232 over-application | $5–10 B | Verify 8507.60.0020 should be on s232_derivative_products.csv at all |
| Entry-timing / FTZ / structural | $15–20 B | **Not addressable in tracker** — owned by eval-side decomposition |

## Recommended actions

1. **No immediate code changes** beyond the §232 auto effective-date fix (separate memo).
2. **Battery §232 verification**: confirm 8507.60.0020 (Li-ion batteries) is correctly on `s232_derivative_products.csv` and that the BEA aluminum_share is reasonable. If batteries are not §232 derivatives at all, this single line removes ~$5–10 B of trackerover.
3. **Empirical calibration loop**: as part of the diagnostic refresh plan, build a calibrator that uses Census-realized rates per HS10 × country to produce per-product *effective-share* corrections to the tracker statutory rates. This addresses both the metal-share calibration and entry-timing gaps in one mechanism. Same pattern as the proposed semi `qualifying_share` calibrator.
4. **Update `tracker_over_report.md` framing**: the report currently treats ch99_dutiable BUG-LIKELY as if it's all a parsing bug. With this trace, ~half is structural / calibration, not a bug per se. The report should split this bucket explicitly.

## Caveats

- **Sample**: top 25 cells covers ~$5 B of $42 B. Smaller cells could exhibit different patterns. Worth re-running the spot-check at the rank-100 mark and rank-500 mark to confirm.
- **Aggregate vs. cell-level**: the Census-realized rate at the cell level is a useful empirical signal; the trackerover gap is intrinsically *aggregate* and can't be fully resolved at the cell level when timing windows span entries.
- **8708.70.4548 specifically**: $45 M April 2025 cell is partly explained by the §232 auto effective-date misalignment. After that fix, this specific cell's residual is much smaller.
