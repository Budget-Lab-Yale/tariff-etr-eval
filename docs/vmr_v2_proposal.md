# Value-misreporting decomposition v2 — proposal

Status: **proposal** (2026-06-10). Upgrades `code/02c_vmr.R` (the pipeline
successor to `09_value_misreporting.R`; method note for v1:
`docs/value_misreporting_methodology.md`). Each item below is independent and
can land separately; the ordering is by evidentiary payoff per unit of work.

## Motivation — what v1 establishes and where it is weak

v1 classifies each tariffed flow `i = (HS10 × country)` around its tariff
event `t*_i` using the exact identity

```
Δln V_i = Δln Q_i + Δln UV_i ,        UV = V / Q
```

and headlines the value-weighted share of flows in bucket B2
(`Δln V < −τ_V`, `|Δln Q| ≤ τ_Q`), with a "strict" variant requiring the
unit-value drop to exceed that of untariffed origins of the same HS10
(`Δln UV_i − Δln UV_ctrl(h) < −τ_W`).

Four weaknesses, in order of importance:

1. **Exporter price absorption is observationally equivalent.** If exporters
   cut pre-duty prices in response to the tariff (incomplete pass-through),
   the treated flow's unit value falls *relative to untariffed origins* with
   quantity comparatively stable — exactly B2-strict, and entirely legal. The
   cross-partner control nets out *common* price moves but cannot net out
   *treatment-induced* ones, because the treatment defines the groups. The
   same applies to within-HS10 variety downgrading (buyers switching to
   cheaper varieties inside the code). **The strict signal is therefore an
   upper bound** on under-invoicing, commingled with price absorption and
   quality downgrading.
2. **No noise floor.** Monthly HS10 × country trade is lumpy; some B2 mass
   arises with no tariff at all. v1 gives the reader no benchmark.
3. **A bucket share is not a magnitude**, and the post-window value weights
   (`V_post`) mechanically *down-weight* the most aggressive under-invoicers
   (under-invoicing shrinks `V_post` itself).
4. **The control index has a composition bias**: it is a ratio of sums across
   control origins, so origin-mix shifts (e.g. diversion toward Vietnam) move
   it with zero price change anywhere.

v2 keeps the identity and bucket machinery (cheap, descriptive, audit-friendly)
and adds the design below.

---

## 1. Placebo noise floor (highest priority)

Run the identical window/classification machinery on **untariffed flows**
(`|Δrate| ≤ CTRL_DRATE_MAX` over the whole window) with pseudo-event months
drawn to match the treated event-month distribution:

- For each treated event month `E` with `n_E` treated flows, sample
  `min(n_E, available)` untariffed flows and assign them `t* = E`.
- Classify with the same dead-bands, floors, and windows.
- Report `B2_placebo` (value-weighted, same weights as §3) alongside `B2_treated`.

**Headline becomes the excess share:**

```
ΔB2 = B2_treated − B2_placebo ,
```

with a permutation band from repeating the placebo draw (e.g. 200 times,
seeded): report the placebo 2.5–97.5 % envelope so "X pp above noise" carries
an uncertainty statement. Same for the strict variant (placebo flows get the
same control construction).

*Implementation*: one extra `lapply` over event months in `02c`; the placebo
flows already sit in `mf`. Output: `vmr_placebo.csv` (draw-level) +
placebo columns in `vmr_decomp_by_*.csv`.

## 2. Dose-response regression (the actual Fisman–Wei test)

Bucketization throws away the incentive gradient. Estimate, on the treated
flow-event panel (weights `w_i` from §3):

```
Δln UV_i  =  β · Δrate_i  +  γ_h(i),E(i)  +  ε_i              (within-product)
Δln (V_i/Q_i) decomposed:  also report the same spec with Δln Q_i as outcome
```

- `γ_h,E`: HS10 × event-month fixed effects — identification is *within
  product, within window*, across origins facing different tariff steps. This
  absorbs the world-price move nonparametrically (strictly better than the
  v1 two-sided control) and the de-minimis/calendar shocks common to a
  product-month.
- `β < 0` with magnitude rising in `Δrate` is the evasion signature
  (Fisman–Wei 2004 use the tariff-level slope of the mirror-data gap; this is
  the domestic-data analogue).
- **Within-China variant**: re-estimate on China flows only, identification
  from cross-HS10 variation in China's own `Δrate`. This kills the bilateral
  exchange-rate confound (an RMB move shifts *all* China unit values, absorbed
  by a country intercept), which the cross-partner control cannot.
- Report `β` separately for related-party and arm's-length subsamples (§4) —
  the single most discriminating contrast available.

*Implementation*: `fixest::feols(dln_uv ~ drate_win | hs10^event_ym, weights)`
if `fixest` is available on the cluster; otherwise within-demeaning by
`(hs10, event_ym)` and `lm()`. Output: `vmr_dose_response.csv`
(spec × subsample × coefficient/SE), figure: binned scatter of within-cell
demeaned `Δln UV` against `Δrate`.

## 3. Weighting and magnitudes

- **Switch flow weights from `V_post` to duty at stake**:
  `w_i = V_pre,i × Δrate_i` (sensitivity: `V_pre` alone). `V_post` weighting
  biases the headline toward zero precisely when the behavior is present.
- **Report implied dollars, not just shares.** For strict-suspect flows the
  under-invoiced value and forgone duty are

```
ΔV̂_i  =  V_pre,i · e^{Δln Q_i} · (e^{Δln UV_ctrl(h)} − e^{Δln UV_i})
ΔD̂_i  =  rate_post,i · ΔV̂_i
```

  (counterfactual post value = pre value × realized quantity growth × control
  unit-value growth). Sum by partner × product; present alongside the
  η-implied revenue gap as the base-erosion sidecar it was designed to be.
  Label both as **upper bounds** (§5).

## 4. Related-party split

Census IMDB publishes related-party trade. If the IMP_DETL fixed-width layout
in the cached ZIPs carries the related/non-related field, add it to the
Step-0 aggregation (`imdb_hs10_country_monthly.csv` gains `con_val_rel_mo`,
`con_val_nrel_mo`, ideally the qty analogues) and:

- compute B2/strict shares and the §2 slope separately by relatedness;
- prior: under-invoicing is easier intra-firm (transfer pricing), while
  exporter price cuts should appear in both — a related-party-concentrated
  signal is the strongest evidence this design can produce, and a flat split
  is honest evidence against the misreporting reading.

If the field is not in the bulk layout, fall back to the Census related-party
API at HS6 × country × year as a coarse share control. *(Check the layout
first; this gates the whole item.)*

## 5. Control index fix + bias-direction accounting

Replace the ratio-of-sums control with a **fixed-weight (Laspeyres) index**
over control origins `c` of product `h`:

```
Δln UV_ctrl(h) = Σ_c  ω_c,pre · Δln UV_c ,    ω_c,pre = V_c,pre / Σ_c V_c,pre
```

so origin-mix shifts inside the control group no longer move the index.
Remaining (document, don't pretend to fix):

- **Diversion price pressure**: tariffed-origin demand lands on control
  origins; with upward-sloping supply their prices *rise*, inflating
  `Δln UV excess` → overstates the strict signal (one more reason to call it
  an upper bound).
- Thin controls: keep `MIN_CTRL`, additionally require the control group to
  hold ≥ some share (e.g. 10 %) of the product's pre-window value.

## 6. Scope hygiene

- **Specific-duty lines**: for them the dutiable base is quantity, not value —
  the evasion margin inverts (under-report Q, not V) and the B2 logic
  misreads. Flag HS10s with specific/compound MFN duties (the tracker's rate
  components identify them) and exclude or report separately.
- **De-minimis discontinuity**: the May/Aug-2025 eliminations pushed small-
  parcel e-commerce into formal entries, a composition break in exactly the
  China-heavy cells with the largest events. Robustness: drop events whose
  windows straddle 2025-05/2025-09 for affected chapters, or re-run with
  `POST_OFFSETS = 3:5`.
- **Reclassification is out of scope** and likely first-order at these rates:
  shifting value into a lower-rate HS10 shows up here as B1 "real
  contraction." Say so in the paper text; the HS-code-switching analysis is a
  separate design (entry-level data or HS8-family flows).
- **Event dating**: events come from the day-weighted monthly rate series, so
  a legal change late in a month registers as the *next* month's step; the
  skipped `t*+1` mostly covers it, but the `POST_OFFSETS` sensitivity above
  doubles as insurance.

## 7. Reframed presentation

Lead the limitations with price absorption, not data coverage:

> The strict signal isolates origin-specific unit-value declines after a
> tariff step that quantities do not explain and untariffed peers do not
> share. Under-invoicing produces exactly this pattern; so do exporter price
> cuts and within-code quality downgrading. The estimates are therefore an
> **upper bound on value misreporting**, with the related-party split (§4)
> and dose-response slope (§2) the discriminating evidence, and the placebo
> floor (§1) the null benchmark.

Cite the pass-through literature both ways: near-complete pass-through in
2018–19 (Amiti–Itskhoki–Konings; Fajgelbaum et al.) supports the misreporting
reading; 2025-vintage evidence of partial absorption (e.g. Cavallo et al.)
argues for the bound language. If an external pass-through estimate `ρ` is
adopted, the absorption-explained unit-value decline is `≈ (1−ρ)·Δrate_i` and
can be netted from `ΔV̂_i` in §3 as a "net of assumed absorption" column.

## Outputs added by v2

| Output | Content |
|---|---|
| `vmr_placebo.csv` | placebo draws; treated-vs-placebo B2/strict shares |
| `vmr_dose_response.csv` | β by spec (pooled / within-China / by relatedness) |
| `vmr_implied_dollars.csv` | ΔV̂, ΔD̂ by partner × product (upper bound) |
| `figure_vmr_dose_response` | binned within-cell scatter + fit |
| `figure_vmr_placebo` | treated vs placebo share distribution |
| revised `vmr_decomp_by_*` | duty-at-stake weights; placebo and excess columns |

## Decision points (flagging, not blocking)

1. Related-party field availability in the IMP_DETL bulk layout (gates §4).
2. `fixest` on the cluster R module (else hand-rolled FE in §2).
3. Whether to adopt an external pass-through `ρ` for the §3/§7 netting column,
   and which estimate.
