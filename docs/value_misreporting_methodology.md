# Value-misreporting decomposition

Method note for `code/R/09_value_misreporting.R` (orchestrator Step 7, `$run_vmr`).

## Question

During the 2025–2026 tariff escalation, reported import **value** by product × country
moved sharply. How much of each value shift is a **real change in trade flows** versus
**misreporting of value** — under-invoicing to shrink the dutiable base? The intuition:
within a flow, a genuine value decline should come with a quantity decline; if value
falls while quantity holds, the implied unit value dropped, which is a misreporting
signal. Literal framing: *"how often, after a tariff change, does value change but
quantity not?"*

## Why this is orthogonal to η

The compliance gap is a revenue ratio, `1 − η = duty / (rate · value)`. Under-invoicing
scales `value` down; since `duty = rate · value`, duty falls proportionally and
`duty/value` (hence η) is **unchanged**. η is structurally blind to value
under-invoicing. This analysis measures that base-erosion channel directly, on the same
partner × product grid as `eta_by_*.csv`, so it is a complement rather than a competitor
to the η calibration (`code/R/08_eta_calibration.R`, `docs/eta_calibration_methodology.md`).

## Data

Census IMDB monthly detail, aggregated to HS10 × country × month
(`data/raw/imdb_hs10_country_monthly.csv`), augmented in Step 0 with:

- `con_qy1_mo` — Quantity 1 in the HTS first unit-of-measure. The unit **varies across
  HS10** (kg, number, dozens, liters, m², or "X" = no quantity required) but is **fixed
  within an HS10 over time**, so a within-flow unit-value series is internally consistent.
- `con_qy2_mo` — Quantity 2 (often a mass unit; frequently zero).
- `air_wgt_mo`, `ves_wgt_mo`, `cnt_wgt_mo`, and `ship_wgt_mo = air + ves` — shipping
  weight by mode. **Census weighs only air and vessel** shipments; land (truck/rail)
  carries zero weight, so weight systematically undercounts Canada/Mexico, and `cnt` is a
  subset of `ves` (not additive).

Statutory rate path `rate_h2avg` (day-weighted monthly `total_rate`) is read from
`data/working/merged_analysis.dta`. Partner groups and the 9-way product grouping mirror
`assign_partner_group` (`code/utils/programs.do`) and `resources/product_groups.csv`.

## Physical anchor

Primary anchor is **`con_qy1_mo`**, with a fall-back to `ship_wgt_mo` where `qy1` is
zero/missing. It covers all transport modes (no land gap) and is the schedule's own
dutiable-relevant unit; because the unit is fixed within HS10, within-flow log changes are
clean. Shipping weight (`air + ves`, Canada/Mexico excluded) is available as a robustness
anchor (`QTY_MODE = "weight"`). Flows with no usable physical anchor (e.g. "X"
no-quantity HTS) are excluded from the decomposition and reported as a coverage caveat
(currently ≈ 0.9 % of value).

## Decomposition

For flow `i = (HS10 × country)` with `unit_value = value / quantity`, the identity is exact:

```
Δln(value_i) = Δln(quantity_i) + Δln(unit_value_i)
```

Each flow's pre/post change is taken around its own **tariff-change event** (staggered):
`event_ym` is the month of the largest in-window statutory step ≥ `DRATE_THRESH` (3 pp).
Windows are averaged to damp lumpiness, skipping the event month and the month after to
absorb in-transit lag and front-running:

- pre-window = months `[t* − 3, t* − 1]`
- post-window = months `[t* + 2, t* + 4]`

`V_w`/`Q_w` are window means (value, quantity); `UV_w = V_w / Q_w`. Both windows must have
strictly positive value and quantity. `EVENT_MODE = "fixed"` is a robustness alternative
that anchors all flows on a single calendar month.

## Classification

With a dead-band `τ` (`T_V`, `T_Q`, default 0.10):

| Bucket | Condition | Reading |
|---|---|---|
| B1 real contraction | Δlnv < −τ and Δlnq < −τ | value and physical fall together |
| **B2 misreporting-suspect** | Δlnv < −τ and \|Δlnq\| ≤ τ | **value down, quantity flat → unit value collapsed** |
| B3 quantity-driven | \|Δlnv\| ≤ τ and Δlnq < −τ | quantity fell, value held |
| B4 real expansion | Δlnv > τ and Δlnq > τ | genuine growth |
| B5 unit-value spike | Δlnv > τ and \|Δlnq\| ≤ τ | value up, quantity flat |
| B6 mixed | otherwise | ambiguous |

The headline is the **value-weighted share** of B2 (weight = post-window value).

## Cross-partner control

A unit-value drop is not proof of under-invoicing — the product may simply have gotten
cheaper for everyone. For each HS10 and event window, the value-weighted unit-value change
of **untariffed origins of the same HS10** (`|window rate change| ≤ CTRL_DRATE_MAX`, ≥
`MIN_CTRL` such origins) defines `world_dln_uv`; `dln_uv_excess = dln_uv − world_dln_uv`.
The **strict** signal requires B2 **and** `dln_uv_excess < −T_W` — value down, quantity
flat, and unit value falling *relative to* untariffed peers of the identical product. This
is a cross-partner, within-product version of the Fisman–Wei evasion-gap idea (using
domestic cross-origin comparison in place of exporter mirror data). HS10 with no clean
control origin (e.g. China-dominant lines) are out of scope for the strict signal.

## Outputs

Tables (`results/tables/`): `vmr_decomp_by_partner_product.csv` (headline),
`vmr_decomp_by_partner.csv`, `vmr_decomp_by_product.csv`, `vmr_decomp_china_by_hs2.csv`,
`vmr_flow_classified.csv` (top flows by value), `vmr_identity_check.csv`.
Figures (`results/figures/`, titled + clean pairs): `figure_vmr_suspect_share_by_partner`,
`figure_vmr_suspect_share_heatmap`, `figure_vmr_dln_scatter`.

## Robustness knobs (top-of-file constants)

Dead-band `T_V`/`T_Q`/`T_W`; event materiality `DRATE_THRESH`; control threshold
`CTRL_DRATE_MAX`/`MIN_CTRL`; value floor `VALUE_FLOOR` ($100k mean monthly pre-window,
below which flows are flagged lumpy and excluded from classification); `EVENT_MODE`
(flow vs fixed); `QTY_MODE` (qy1 vs weight); pre/post offsets; `DRY_RUN`.

## Limitations

- The control removes product-wide price/mix drift, not origin-specific genuine quality
  downgrading — the signal is "unit-value drop net of common price," *consistent with* but
  not *uniquely* under-invoicing.
- No foreign mirror data, so it is a relative (cross-partner) statement; China-dominant
  HS10 have no clean control and are excluded from the strict signal.
- Shipping weight is zero for land modes, disabling the weight anchor for Canada/Mexico.
- No-quantity ("X") HTS are unmeasurable.
- Declared data only — this flags patterns consistent with understatement, not adjudicated
  fraud.

## Verification (build of 2026-06-08)

Decomposition identity holds exactly (max |Δlnv − Δlnq − Δlnuv| = 4.6e-15); augmented-CSV
monthly value totals match `merged_analysis.dta` to 0.000 % every month; spot-check flow
HS 9503000090 (China toys, Liberation Day): value −17 %, quantity +8 %, unit value −25 %
→ bucket B2, strict = FALSE (no clean control origin — China-dominant line, as expected).
