---
output:
  word_document: default
  html_document: default
---
# Calibrating the Tariff Compliance Parameter from Observed Collections

The Budget Lab at Yale — Methodology Documentation

Status: Draft (June 2026); engine implemented in `code/R/08_eta_calibration.R` and first
calibration run complete (results in Section 8 and `results/tables/eta_*.csv`). Companion to the
*State of U.S. Tariffs* series and the Budget Lab Tariff Model.

---

## 1. Overview

The Budget Lab Tariff Model turns a statutory tariff schedule into revenue, price, and
macroeconomic estimates. Because importers do not, in practice, pay the full statutory rate on
every shipment, the model scales collections below their statutory level using a compliance
parameter. To date this has been a single round value — a 10% reduction in gross revenue — meant
to stand in for noncompliance and evasion.

This document describes a way to replace that fixed assumption with a parameter estimated from
data: the observed gap between statutory tariff rates and the duties actually collected over the
2025–2026 tariff episode. We define the parameter, set out three increasingly flexible versions of
it (a single economy-wide value; values that vary by country and product; and a full
country-by-product schedule), and explain how each can be estimated given that the cleanest measure
of collections — U.S. Treasury customs receipts — is published only as a national total. We then
test the calibration out of sample, using the February 2026 Supreme Court ruling that struck down
the IEEPA tariffs as a natural break between two tariff regimes. The method is designed to slot into
the Tariff Model in place of the current fixed parameter.

The calibrated gap is consistently larger than the current 10%. Depending on which statutory rate
we measure against and which months we use — choices we lay out below — it runs from roughly 19% to
nearly 40%. We report these variants side by side rather than collapsing them to a single number,
because the right choice for the model is not yet settled.

We use the neutral term compliance gap (denoted $\eta$) rather than "evasion" throughout. The
measured shortfall reflects a mix of things: statutory exemptions the model does not otherwise
capture; specific duties (charged per physical unit rather than as a percentage of value) that work
out to a different effective rate than assumed; antidumping and countervailing duties; ordinary
measurement error; and genuine behavioral noncompliance. For the purpose of adjusting revenue the
split among these does not matter — only the ratio of collected to statutory revenue does — but the
parameter should not be read as a pure evasion rate.

---

## 2. Conceptual framework

### 2.1 Basic terms

Before describing the calibration, we fix a few terms.

- The *statutory rate* is the tariff rate the law specifies for a given product from a given
  country — what the schedule says should be charged.
- *Collections* (or realized duties) are what is actually paid. They fall short of the statutory
  amount for several distinct reasons: trade shifts toward lower-tariff products and origins;
  statutory exemptions and preference programs lower the rate that legally applies; and the cash
  Treasury records in a given month lags the duties owed on goods entering that month.
- An *effective tariff rate* (ETR) expresses any of these as a single average rate — total duties
  divided by total import value, so larger trade flows count more. We build statutory and realized
  ETRs the same way and compare them.

The compliance gap is the distance between a statutory ETR and what is actually collected,
expressed as a fraction of the statutory amount.

### 2.2 The statutory–realized ladder

We measure the distance between announced statutory rates and realized collections as a sequence of
ETRs, each differing from the one above it in a single input. For month $t$ and (HTS-10 product
$\times$ partner country) cell $i$, with statutory rate $r_i$ and import value $w_i$, an ETR is the
value-weighted average $\sum_i w_i r_i / \sum_i w_i$. The rungs are:

| Measure | Rate input | Weight input |
|---|---|---|
| Announced statutory | post-USMCA statutory rate | 2024 (fixed) import value |
| Composition-adjusted | post-USMCA statutory rate | monthly (actual) import value |
| Preference-adjusted | + non-USMCA preferences applied | monthly import value |
| Census-declared | Census calculated duty / import value | (observed) |
| Treasury-realized | Treasury customs duties / goods imports | (observed) |

Stepping down the ladder isolates, in order: import composition (the basket moving toward
lower-tariff cells); non-USMCA preference claiming (Annex II, ITA, Chapter 98, KORUS, GSP/AGOA, and
other free-trade agreements); a statutory-versus-declared residual (specific-duty conversions,
antidumping and countervailing duties, measurement error, and behavioral noncompliance); and a
declared-versus-collected timing wedge (refunds, drawback, foreign-trade-zone deferral,
administrative-review liquidations, and cash-versus-accrual recognition). The full derivation is
documented separately; here the ladder serves only to define what the compliance parameter must
capture.

### 2.3 What the parameter must capture

The Tariff Model represents import substitution explicitly: trade volumes respond through a trade
model (GTAP), so the model already distinguishes a pre-substitution rate (statutory rates on a fixed
basket) from a post-substitution rate (statutory rates after the basket shifts toward lower-tariff
origins). Our two statutory baselines are the natural empirical counterparts — the announced
(fixed-2024-basket) ETR lines up with the pre-substitution rate, and the composition-adjusted
(monthly-basket) ETR with the post-substitution rate.

The correspondence is close but not exact. The model's modeled substitution response and the actual
month-to-month change in the import basket need not coincide, and squaring the two is something we
will need to work through before fixing how a calibrated parameter feeds the model. We therefore
calibrate against both baselines and report both, without prejudging which the model should
ultimately use:

- *Composition-adjusted baseline.* The parameter measures how far collections fall below statutory
  rates applied to the actual monthly basket. It leaves out the basket shift itself, which the model
  handles separately.
- *Announced baseline.* The parameter additionally absorbs the shift in trade composition. The
  difference between the two baselines' parameters is itself an estimate of that composition
  channel.

---

## 3. Data

The calibration panel is the (HTS-10 $\times$ country $\times$ month) cell file underlying the
Budget Lab statutory–actual ETR analysis, January 2025 through March 2026. Each cell carries:

- *Statutory rate* ($r^{\text{stat}}_i$): the post-USMCA statutory rate (`rate_h2avg`),
  reconstructed from the Harmonized Tariff Schedule and Chapter 99 authorities by the Budget Lab
  tariff-rate tracker and day-weighted across mid-month revisions.
- *Census-declared rate* ($r^{\text{cens}}_i$): calculated duty divided by consumption value from
  the Census Import Merchandise database (IMDB) — the only collections measure available at the cell
  level.
- *Import weights*: monthly consumption value (the actual basket) and 2024 annual value (the fixed
  basket).
- *Partner country* and *HTS-2 chapter* identifiers.

The aggregate Treasury-realized rate ($\text{ETR}^{\text{treas}}_t$) — customs duties from the
Monthly Treasury Statement divided by goods imports — is the cash-basis ground truth, but it is
published only as a national total, with no country or product detail. This constraint is central to
identification (Section 6).

*Train/test split.* The IEEPA-regime months (2025m1–2026m2) are the training sample; March 2026 —
the first full month after the Supreme Court invalidated the IEEPA tariffs and the regime
transitioned to Section 122 — is the held-out test sample.

---

## 4. The compliance parameter

We treat collections within a group as the statutory amount scaled down by a single fraction. For a
group $g$ — the whole economy, a country, a product, or a country-by-product cell — define
$1-\eta_g$ as the ratio of realized to statutory tariff revenue:

$$
1-\eta_g \;=\; \frac{\sum_{i\in g} w_i\, r^{\text{actual}}_i}{\sum_{i\in g} w_i\, r^{\text{stat}}_i}.
$$

So $\eta_g$ is the fraction of statutory revenue not collected within $g$, and multiplying the
statutory ETR by $(1-\eta_g)$ reproduces the realized ETR. We work with this revenue ratio at the
group level rather than averaging cell-by-cell ratios, for two reasons: the group ratio is well
defined even when some cells carry a zero statutory rate (where a cell-level ratio would divide by
zero), and it is exactly the quantity that determines revenue.

Three nested versions of the parameter trade flexibility against the risk of overfitting:

1. *Constant* — a single economy-wide $\eta$.
2. *Two-way (country and product effects)* — one multiplicative model
   $1-\eta_{cp} = \exp(\alpha_c + \beta_p)$, fit by weighted regression of the log
   realized-to-statutory ratio on country and product indicators. The parameter varies by country
   and by product but assumes the two dimensions add up separably.
3. *Full interaction* — a separate $1-\eta_{cp}$ for every country-by-product cell, pulled toward
   the two-way fit for thin cells (Section 7).

By construction the full-interaction version fits the training sample best and the constant fits
worst; the empirical question is which one generalizes across the regime break (Section 8).

---

## 5. Aggregation levels

Country and product are each defined at two granularities, run in parallel so the
flexibility-versus-overfitting trade-off can be read straight off the granularity axis:

- *Partner group $\times$ HTS-2 chapter* (8 partner groups $\times$ ~97 chapters).
- *Individual country $\times$ HTS-2 chapter* (all countries $\times$ ~97 chapters).

The constant version does not depend on granularity and anchors the low-variance end.

---

## 6. Identification

The natural calibration target is the aggregate gap between the $\eta$-adjusted statutory ETR and
the Treasury-realized ETR. That target is one equation per period. It pins down the constant version
exactly (one unknown), but it cannot pin down how $\eta$ varies across countries or products: with
8, ~97, or hundreds of free parameters against a single aggregate equation, infinitely many
$\eta$-vectors reproduce the aggregate equally well. The aggregate gap carries no information about
cross-sectional shape.

Cross-sectional variation must therefore come from disaggregated collections, and the only
disaggregated measure we have is Census-declared duties. We accordingly split the parameter into a
shape and a level:

1. *Shape (from Census).* Estimate $1-\eta^{\text{shape}}_g$ as the Census-to-statutory revenue
   ratio within each group (Section 4). This sets where the gap is larger or smaller.
2. *Level (to Treasury).* Multiply by a single per-period scalar $k$ so that the aggregate
   $\eta$-adjusted statutory ETR matches the Treasury-realized ETR. Because the Census-implied
   aggregate equals the Census-declared ETR, $k = \text{ETR}^{\text{treas}} / \text{ETR}^{\text{cens}}$
   is exactly the Census-to-Treasury timing factor.

Census thus sets where the gap falls; Treasury sets its overall level. The constant version is the
special case in which the shape is a single number and the two steps collapse into
$\eta = 1 - \text{ETR}^{\text{treas}}/\text{ETR}^{\text{stat}}$, calibrated straight to Treasury.
This construction forces the aggregate Treasury gap to zero in the training sample for every
version, meeting the aggregate target while letting the cross-section vary.

---

## 7. Estimation

For each baseline (announced and composition-adjusted) and each version of the parameter:

1. *Pool.* Combine training-period cells and compute value-weighted group ratios (constant,
   two-way) or cell ratios (full interaction). The two-way model is a weighted least-squares
   regression of $\log(r^{\text{cens}}/r^{\text{stat}})$ on country and product indicators, weighted
   by statutory revenue.
2. *Shrink.* Pull the full-interaction cell estimates toward the two-way fit by empirical Bayes — a
   shrinkage that pulls harder the less statutory revenue a cell has behind it — so that thin cells
   and cells with odd ratios (for example $\eta<0$, where antidumping/countervailing duties or
   specific-duty conversions make collections exceed the modeled statutory rate, or $\eta>1$) do not
   dominate. The share of cells shrunk or clipped is reported.
3. *Set the level.* Fix $k$ against Treasury (Section 6).
4. *Diagnostics.* Report $\eta$ by training month to expose variation within the IEEPA period (the
   realized-to-statutory gap moves materially across its sub-periods), plus a recency-weighted
   variant as a robustness check.

The full calibration — group aggregation, the weighted two-way fit, the empirical-Bayes shrinkage,
the Treasury level factor, and the out-of-sample scoring — runs in R
(`code/R/08_eta_calibration.R`), reading the working `.dta` panel via `haven`. It slots in as
pipeline step 8, after the Stata ETR construction. Outputs are written to `results/tables/eta_*.csv`
and `results/figures/figure_eta_*.png`.

---

## 8. Out-of-sample validation

The training sample (the IEEPA regime, with large fentanyl and reciprocal duties) and the test month
(March 2026, the Section 122 regime, a flat blanket) are different tariff regimes. That makes the
test demanding and policy-relevant: it asks whether a parameter calibrated under one regime carries
over to another.

- *Prediction.* Freeze each version's Census shape and training-period level $k$, apply them to
  March statutory rates, and compare the predicted Treasury ETR (and revenue) to the observed March
  values.
- *Oracle.* Re-calibrate each version on March alone, and compare the training and March estimates
  by country and product to locate where the IEEPA-period calibration breaks. We report the test
  error split into a shape part (the cross-section failed to carry over) and a level part (the $k$
  factor moved), since the timing wedge has been volatile.

*Expected pattern (a priori).* The full-interaction version should fit training best but generalize
worst, because it bakes in IEEPA-era cell ratios — dominated by fentanyl and reciprocal exposure on
Canada, Mexico, and China — that do not carry over to a flat Section 122 world. A coarser version,
constant or country-plus-product, is likely to predict March more accurately.

*Realized pattern (June 2026 run).* The trade-off appears, but muted. The full-interaction version
does fit the training cross-section best and does carry the largest shape error into March, so its
cell-level detail is the least portable, as expected. But once each version is re-leveled to the
aggregate through $k$, that overfitting largely cancels: every version (constant through full
interaction, at both granularities) predicts the March Treasury ETR within roughly half a
percentage point. The dominant source of out-of-sample error is not granularity but a common shift
in the level factor $k$ — the Census-to-Treasury timing wedge — which moves by about 0.3 points
across the break no matter how the parameter is cut. The practical conclusion is that disaggregation
buys little aggregate accuracy here, and the timing level is the binding out-of-sample risk — which
is why a constant is preferable to a schedule.

*Training-window robustness (the January–April 2025 ramp).* The early-2025 months pair a fast-rising
statutory schedule with Treasury cash that had not yet caught up, so the monthly gap there is both
very large (around 50%) and volatile — and that volatility is mostly a timing artifact rather than a
structural feature. We therefore run the whole exercise on two training windows — the full window
(2025m1–2026m2) and a post-ramp window (2025m5–2026m2) — for every baseline, version, and
granularity (results in `eta_summary.csv` and `eta_by_window.csv`; the cross-section and
out-of-sample figures are split by window). Dropping the ramp lowers the constant on both baselines:
from about 23% to 19% on the composition-adjusted basis, and from about 38% to 32% on the announced
basis. The Census-based version of the gap — which leaves out the Treasury timing wedge — barely
moves (about 25% to 23% on the composition-adjusted basis). That tells us what the ramp months add
is mostly timing, not a difference in declared compliance. We highlight the post-ramp figures as the
cleaner read on each baseline, while continuing to report the full-window figures alongside them; a
recency-weighted variant (half-life six months) lands close to the post-ramp value and corroborates
this.

Two further results favor the post-ramp window over the full window. First, it predicts the March
test month better: its Census-to-Treasury level factor $k$ (about 1.06) is closer to March's than
the full-window factor (about 1.03), so the level part of out-of-sample error shrinks from about
0.30 to 0.05–0.10 points, and the constant's March miss falls from −0.33 to +0.07 points. Second, it
localizes the regime dependence: China's gap collapses from about 15% (full window) to about 3%
(post-ramp) — its large full-window gap was an early-ramp artifact, the Geneva de-escalation period —
while Canada, Mexico, and the rest of the world are stable across windows. Both point to the
January–April months being special, and to the post-ramp calibration being the more portable one.

*Withholding the test-month basket.* The prediction above applies the frozen parameter to March's
actual import basket, which a true ex-ante forecast would not observe. As a stricter check we repeat
the prediction using the most recent training month (February 2026) as a carry-forward forecast of
the March basket, holding everything else frozen (`march_err_fcst_pp` in `eta_summary.csv`). It
changes the out-of-sample error by at most about 0.05 points on either baseline: February's basket
covers about 98% of March's trade value, and month-to-month composition is stable enough that not
knowing it costs almost nothing. The basket is therefore not a meaningful source of out-of-sample
error here, which leaves the timing level as the binding risk. (For the announced baseline the two
predictions nearly coincide by construction, since it already uses fixed 2024 weights; the test
bites only for the composition-adjusted baseline.)

---

## 9. Integration into the Tariff Model

In the current model, revenue is computed as

$$
\text{Net revenue} = \text{Gross revenue} \times \big(1 - \text{compliance\_effect} - \text{income\_effect}\big) + \text{refund adjustment},
$$

where gross revenue is post-substitution statutory duties net of baseline,
$\text{compliance\_effect}=0.10$ is the noncompliance/evasion reduction, and
$\text{income\_effect}=0.23$ is a separate offset for reduced income- and payroll-tax receipts. This
calibration refines `compliance_effect` only; the income offset and refund schedule are out of
scope.

Two integration options follow:

- *Drop-in scalar.* Replace the fixed 0.10 with the calibrated constant, allowing it to vary by
  fiscal year as the regime evolves. Because the model applies the parameter after its substitution
  step, the composition-adjusted estimate (about 19% post-ramp, 23% full window) is the closer
  counterpart, with the announced estimate (about 32% to 38%) the alternative if the parameter is
  instead applied to fixed-basket rates. As noted in Section 2.3, the correspondence between our
  baselines and the model's pre-/post-substitution rates is close but not exact, so which estimate to
  adopt — and at what timing — is a decision to settle alongside that reconciliation. This is a
  minimal change that preserves the model's current structure. (The full-window 23% is unrelated to
  the similarly sized 0.23 income offset above; the two coincide only numerically.)
- *Schedule.* Replace the scalar with a calibrated country and/or product $\eta$ schedule, applied
  to the ETR matrix before aggregation. Higher resolution, but — per Section 8 — only warranted if
  the schedule demonstrably generalizes.

A further consideration, not required by this calibration: the compliance reduction is currently
applied to revenue only, while the price and macro blocks use the full statutory ETR. If a duty is
exempted or never collected, the associated consumer-price effect is also smaller, so there is a
case for applying the realized-to-statutory ratio consistently to the ETR feeding the price and
macro blocks. This is a separate modeling choice; we flag it because an empirical $\eta$ makes
consistent application straightforward.

---

## 10. Limitations and caveats

1. *Census is declared, not collected.* The cell-level shape comes from importer-declared duties at
   entry, which differ from Treasury cash by the timing wedge (refunds, drawback, foreign-trade-zone
   deferral, administrative-review liquidations). We isolate this in the level factor $k$, but the
   wedge has been large and volatile recently (Treasury over-collected relative to Census by roughly
   \$12 billion cumulatively through March 2026), so the level is the least stable component.
2. *Regime dependence.* $\eta$ is not a structural constant. Because the announced baseline bundles
   composition, and because the realized-to-statutory gap depends on the rate structure in force, a
   parameter calibrated under IEEPA need not hold under Section 122 or any future regime. The
   validation quantifies this; it does not remove it.
3. *Variation within the training period.* The training window spans several IEEPA sub-periods with
   very different rates and gaps; the pooled parameter is a value-weighted average that hides this
   variation. Recency weighting is offered as a robustness check.
4. *Not pure evasion.* As noted in Section 1, the gap folds in unmodeled exemptions, specific-duty
   conversions, antidumping/countervailing duties, and measurement error alongside behavioral
   noncompliance. It is the right quantity for adjusting revenue, but it should not be read as an
   evasion rate.
5. *Thin cells.* The full-interaction version relies on shrinkage to stay stable where trade is
   sparse; its cell-level estimates should not be read individually without regard to their
   precision.

---

## 11. References

- The Budget Lab at Yale. *State of U.S. Tariffs* (updated series) and the Budget Lab Tariff Model.
- Eck, Hoang, Mix, and Ray (2026), "Mind the Gap: Announced versus Implied Tariff Rates in Recent
  Trade Policy Episodes," FEDS Notes.
- Gopinath and Neiman (2026), "The Incidence of Tariffs: Rates and Reality," NBER WP 34620.
- Companion: Budget Lab statutory–actual ETR decomposition (`paper/etr_divergence_paper.Rmd`) and
  framework derivation (`docs/six_tier_framework_plan.md`).
