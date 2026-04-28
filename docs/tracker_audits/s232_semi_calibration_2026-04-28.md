# Section 232 semi `qualifying_share` interim calibration

**Date**: 2026-04-28
**Triggered by**: `tariff-etr-eval/docs/tracker_over_report.md` Round 1 (Action 1, $80–110 B BUG-LIKELY surface)
**Scope**: `tariff-rate-tracker/resources/semi_qualifying_shares.csv`

## Finding

The trackerover Round 1 diagnostic flagged HS10 8471.50.01.50 as the single largest BUG-LIKELY over-statement cell (~$20 B across 9 of the top 15 cells, on imports from Taiwan / Mexico / Canada). The report initially attributed this to missing inclusions in `ieepa_exempt_products.csv`. Tracker-side trace revealed otherwise:

- `ieepa_exempt_products.csv` line 3406 already contains `8471500150`. The tracker's IEEPA reciprocal correctly returns 0 for this cell.
- The 25% rate the tracker applies comes from **`resources/s232_semi_products.csv`** (US Note 39 / 9903.79.01) — a separate authority.
- The Section 232 semi proclamation (US Note 39(b)) legally covers HS headings **8471.50, 8471.80, 8473.30** combined with a per-article **TPP / DRAM bandwidth technical gate**. Only advanced AI accelerators (Nvidia H100/H200, AMD MI325X class) actually meet the gate; ordinary computers and ADP machines do not.
- The tracker has a `qualifying_share` parameter at `resources/semi_qualifying_shares.csv` that scales the §232 rate per HTS10 to approximate the gate. **All 10 entries are currently 1.0** (uncalibrated upper bound), per the project's `todo.md` Phase 5 deferred work.
- `06_calculate_rates.R:1441` applies the share: `heading_232_rate * coalesce(qualifying_share, 1.0) * (1 - end_use_share)`.

This is exactly the calibration gap the tracker author flagged. Census collection on these cells is empirically near zero (~$0–2M on $5–12B import value, per the trackerover top-cells table), implying a realized qualifying share well below 1.0 — closer to 0 for ordinary ADP machines.

## Source authority

`tariff-rate-tracker/todo.md:88`:

> Calibrate `qualifying_share` per HTS10 — target Nvidia H200, AMD MI325X class accelerators only meet Note 39(b) TPP/DRAM gate. Primary source: 8471.80.4000 (discrete GPU/AI cards); most other 8471/8473 HTS10s should calibrate to ~0. Source: CBP trade data or SIA/SEMI industry estimates.

## Interim calibration

Pending data-driven calibration (see "Long-term" below), apply the binary split implied by `todo.md`:

| HTS10 | Description | Interim share | Reasoning |
|---|---|---:|---|
| 8471500110 | ADP w/ CRT (legacy desktop / monitor combo) | **0.0** | Not AI accelerator |
| 8471500150 | Other ADP (laptops, desktops) | **0.0** | Not AI accelerator (smoking-gun cell) |
| 8471801000 | Control or adapter units | **0.0** | Not AI accelerator |
| **8471804000** | Units for physical incorporation into ADP machines | **1.0** | GPU / AI card line per `todo.md` |
| 8471809000 | Other ADP units | **0.0** | Generic catch-all |
| 8473301140 | Memory modules | **0.0** | Generic memory; HBM specifically would qualify but not represented here at HTS10 |
| 8473301180 | Other memory parts | **0.0** | Generic |
| 8473302000 | PCB face plates / lock latches | **0.0** | Mechanical parts |
| 8473305100 | Other parts | **0.0** | Generic |
| 8473309100 | Other parts | **0.0** | Generic |

This is conservative on the trackermiss side: 8471.80.4000 keeps the full §232 rate, which over-applies the rate to non-GPU components classified there (NICs, expansion cards, motherboards). The trackermiss footprint of that residual is small relative to the trackerover savings (~$20 B → ~0 on the chs 84 ADP lines).

## Expected impact

| Metric | Pre-calibration | Post-calibration (interim) |
|---|---|---|
| Trackerover BUG-LIKELY | $161.3 B | est. $130–140 B |
| HS84 share of BUG-LIKELY | $63.8 B (39.6 %) | est. $25–35 B |
| Tracker mean ETR (Phase 2 era) | ~19 % | est. ~18.5 % |
| TPC within-2pp match (Phase 2 revs) | 75–80 % | likely improves modestly |
| Tariff-ETRs gap | +1.7 to +2.6 pp | likely narrows by 0.3–0.7 pp |

The Tariff-ETRs comparison should improve because Tariff-ETRs presumably handles the §232 semi gate in a similar way (or excludes 8471/8473 entirely from §232).

## Long-term — data-driven calibration

The interim calibration uses a binary split from project guidance. The right answer is empirical: per HTS10, `qualifying_share` ≈ Census collection / (import value × heading rate), computed over a recent rolling window where the heading rate was active.

This is a natural addition to the diagnostic refresh plan (`docs/diagnostic_refresh_plan.md`):

- New module: `code/utils/semi_calibration.do` (Stata) or `code/R/calibrate_semi_shares.R`.
- Inputs: `merged_analysis.dta` (eval repo), `s232_semi_products.csv` (tracker).
- Output: refreshed `semi_qualifying_shares.csv` with empirical shares + a confidence interval.
- Cadence: monthly with the rest of the diagnostic refresh; tracker pulls the updated file on next rebuild.

Until the empirical calibrator is built, the interim binary calibration above stands. Revisit at next refresh cycle.

## Patch

Replace `tariff-rate-tracker/resources/semi_qualifying_shares.csv` with the interim shares above. The `06_calculate_rates.R` rate path is unchanged — the existing line 1441 multiplication picks up the new shares automatically on next build.

## Caveats

- **Interim is binary, not graduated.** A more nuanced calibration would set memory modules (8473.30.11) to a partial share if HBM imports are non-trivial. Defer to empirical calibration.
- **8471.80.4000 retains 1.0**, which over-applies §232 to non-GPU items in that subline. The empirical calibrator should refine this — likely to ~0.6–0.8 based on AI-card share of physical-incorporation imports.
- **Section 232 semi proclamation may amend.** The current `s232_semi_products.csv` reflects US Note 39 as of HTS rev 1, 2026. Subsequent amendments need re-derivation via `scripts/build_semi_products.R`.
- **End-use carve-outs (Note 39(d), `end_use_exemption_share`)** are also at default (0); separate calibration pending.
