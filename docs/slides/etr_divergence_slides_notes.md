# Slide notes — *Actual versus Statutory Tariff Rates: 2025–2026*

Speaker notes paralleling `etr_divergence_slides.tex`. One section per main slide, in deck order. Prose intended as full-sentence speaking content; not literally read but available as a fallback.

> **Note (May 2026)**: the slide deck was reordered to put Avg-ETR plots before Shapley plots within each pair, to insert a new between/within math slide before S1→S2, to move "Two ways of decomposing" after S1→S2 trade diversion, and to move S2→S3 (all-other preferences) to after the Treasury-vs-Census slide. The section titles below reflect the *intended* deck order after these changes; not all sub-section prose has been re-synced to the new positions yet — fall back to the slides themselves when in doubt.

---

## Slide 1 — Title

Brief introduction:
- Joint work between John Iselin, John Ricco, and Abhi Gupta at the Budget Lab at Yale.
- This presentation summarizes our forthcoming paper measuring and decomposing the gap between announced statutory tariff rates and Treasury-collected duties during the 2025–2026 escalation. The framework is a five-channel ladder.

---

## Slide 2 — The puzzle

By late 2025 the trade-weighted statutory tariff rate that the U.S. has announced sits in the mid-teens — our preferred summary measure (S1, statutory rate at Post-July 2025 USMCA shares × 2024 import weights) was **15.07% in December 2025** and **14.06% in February 2026**. Treasury actually collected duties at a rate of **9.88% in December 2025** and **10.49% in February 2026**.

The gap between the two — about 3.6 to 5.2 percentage points after USMCA stabilization, or 6.1 to 7.8 percentage points if we include the 2024-to-Post-July 2025 USMCA claim-rate ramp — is real. It's not measurement noise. It reflects a combination of behavioral and administrative responses: USMCA claiming, supply-chain composition shifts, statutory exemptions like Annex II / ITA / Chapter 98, and timing or enforcement frictions.

For policy and welfare analysis we want to know which of these channels carry the gap and how they evolve over the 14-month policy episode. The rest of this talk is the framework we use to answer that.

---

## Slide 3 — What the literature has established

Three anchor papers, briefly. All three predate or coincide with our paper and inform our decomposition design.

**Azzimonti (2025), Richmond Fed Economic Brief No. 25-29.** Time period: May 2025 (single month). Decomposition: predicted AETR vs actual, three channels — within-country product mix (0.6 pp), cross-country share shifts (2.7 pp), implementation frictions (5.5 pp). Headline gap: 8.8 pp on a 17.5 pp predicted AETR. Implementation frictions dominate her single-month decomposition. Canada case study finds 31% of CA product lines with positive predicted tariffs generated zero duty in May.

**Gopinath and Neiman (2026), NBER w34620 — "The Incidence of Tariffs"**. Time period: through September 2025. Documents ~27% trade-weighted statutory vs ~10–11% actual at the peak — the cleanest aggregate documentation of the gap. Their key finding for our purposes: pass-through on *collected* duties is near 100%. So the gap is what shields prices, not under-implementation of the schedule. Channels they cite: shipping lags, exemptions, FTA utilization, enforcement.

**Eck, Hoang, Mix, Ray (2026), FEDS Notes "Mind the Gap" (April 2026).** Time period: through December 2025; explicit comparison to 2018–19 episode. Decomposition: announced ETR vs realized, two channels — composition (shifts in import sourcing toward lower-tariff products and countries) and rate discrepancies (per-cell rate divergence). December 2025 announced ETR 14.7%; realized fell 5.43 pp short, $\approx$44% of the announced increase. The 2018–19 gap was 0.44 pp, $\approx$22% of announced. This 2× ratio with broader concentration is their headline.

(Footnote on slide: our framework recovers their numbers within 0.5 pp on every comparable Dec 2025 quantity. Cross-validation table is in the appendix.)

What our framework adds: a unified five-channel decomposition that cleanly separates USMCA claim-rate dynamics from cross-country and product-side composition shifts, plus a non-USMCA preferences rung that the literature handles ad hoc.

---

## Slide 4 — The complete decomposition: four channels (line figure)

This is the visual anchor for the whole talk. Five sequential ETR series:

- **S0** (top, dashed gray): the most-static counterfactual — USMCA at 2024 baseline shares applied to 2024 import weights. Effectively, "what would the ETR be if claim rates and trade composition had not moved at all from 2024."
- **S1** (solid blue, thick — the framework anchor): USMCA stabilized at the post-July 2025 average (~89% for CA/MX) applied to 2024 weights. This is also the line that the tracker daily ETR collapsed to monthly produces by construction. S1 is our preferred summary of the announced statutory ETR.
- **S2** (blue dashed): same rates as S1, but actual monthly trade weights. The S1→S2 step is "trade diversion."
- **S3** (green dot-dash): subtracts non-USMCA preferences (Annex II, ITA, Ch98, KORUS, GSP, etc.) at IMDB-observed claim shares.
- **T** (vermillion solid): Treasury actual.

The point of the line plot is to show that S1, S2, S3 are tightly bunched after July 2025, and the dominant gap is between S1 and Treasury — most of the action lives in our middle three channels.

---

## Slide 5 — The complete decomposition: four channels (text framing)

The verbal framework. Each rung "turns one channel on":

- S0 → S1 holds weights at 2024 fixed and changes USMCA claim shares from the 2024 baseline (~38% CA, ~50% MX) to the post-July 2025 baseline (~89% both). This step captures the USMCA adjustment.
- S1 → S2 holds USMCA claim rates at post-July 2025 fixed and shifts weights from 2024 to actual monthly. This step captures trade diversion.
- S2 → S3 holds Post-July 2025 USMCA and monthly weights and applies non-USMCA preference shares. This step captures all-other preferences.
- S3 → S4 → T captures the residual: the gap between cell-level statutory-with-all-preferences-applied and Census-collected duties (S3→S4), plus the gap between Census and Treasury (S4→T).

Most of our analysis lives between **S1 and T**. The S0→S1 step is treated as backstory because the underlying claim-rate normalization was largely retrospective (firms filed late; July 2025 USITC reporting changes made the underlying utilization visible).

### Sub-period ladder averages (anchor numbers)

Reference table for the 4-window (plus overall) breakdown:

| Window | S0 | S1 | S2 | S3 | S4 | T | adj | div | oth | res | tim |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Overall (2025m1–2026m2) | 15.46 | 13.05 | 10.81 | 10.26 | 8.07 | 8.33 | 2.42 | 2.24 | 0.54 | 2.19 | -0.25 |
| W1: Pre-Liberation (2025m1–m3) | 7.12 | 5.41 | 4.21 | 4.16 | 2.78 | 2.40 | 1.71 | 1.20 | 0.05 | 1.38 | 0.37 |
| W2: Liberation→Phase 2 (2025m4–m6) | 16.67 | 14.27 | 11.40 | 10.79 | 8.35 | 7.90 | 2.40 | 2.88 | 0.61 | 2.43 | 0.45 |
| W3: Phase 2→Phase 2 Recip (2025m7) | 17.59 | 14.83 | 12.72 | 12.37 | 9.75 | 9.47 | 2.76 | 2.11 | 0.34 | 2.63 | 0.28 |
| W4: Phase 2 Recip→SCOTUS (2025m8–2026m1) | 18.50 | 15.79 | 13.48 | 12.69 | 10.23 | 10.95 | 2.71 | 2.30 | 0.79 | 2.46 | -0.72 |
| W5: Post-SCOTUS (2026m2) | 16.56 | 14.06 | 10.85 | 10.31 | 8.48 | 10.49 | 2.49 | 3.22 | 0.54 | 1.83 | -2.01 |

Three things stand out in the sub-period table beyond the trend:

1. **W2 vs W3** (Liberation Day window vs Phase 2 onset): trade diversion gap is the same shape across the two periods (~2.1–2.9 pp), but the **residual** gap (S3→S4) actually widens in W3 — the system was still digesting Liberation Day rates well into Phase 2.
2. **gap_timing flip mid-2025**: the S4→T channel turns negative starting around July 2025 (W3), accelerating through W4 (-0.72 pp avg) and W5 (**-2.01 pp**). Treasury collects *more* than Census IMDB declares. Cumulatively (Feb 2025–Feb 2026), Treasury has over-collected by ~$10.5B vs IMDB. Plausible drivers: ACH lag catch-up, post-entry adjustments, refund reversals, FTZ deferrals being paid down.
3. **gap_residual stays positive throughout**: S3 still exceeds S4 in every window — the cell-level reconstruction is over-predicting what importers declare at entry. That's the structural residual: specific-duty AVE failures, AD/CVD, within-cell behavioral noise. *Not* converging in the panel.

---

## Slide 6 — Formal Model

Walk the audience through the math at the level a careful reader would expect:

We start from the basic ETR identity:
$$\tau_t = \frac{R_t}{I_t}$$
where $R_t$ is revenue (duties) collected and $I_t$ is import value, both in month $t$. This is the realized rate.

To define a counterfactual statutory rate, we need a per-cell rate and a per-cell weight. Index cells by product $p$ and country $c$:
$$\tau^{\text{stat}}_t = \frac{\sum_{p,c} w_{pc}(t) \, \tau_{pc}(t)}{\sum_{p,c} w_{pc}(t)}$$
where $\tau_{pc}(t)$ is the cell-level statutory rate (a function of the policy bundle: tariff schedule × USMCA scaling × any preference applied) and $w_{pc}(t)$ is the cell weight (dollar import value).

We construct **five tiers** by holding either rates or weights at counterfactual values:

- $S_0 = \sum_{p,c} \tau^{2024}_{pc} \cdot \overline{w}^{2024}_{pc} / \sum \overline{w}^{2024}_{pc}$ — USMCA at 2024 claim rates, weights at 2024 baseline.
- $S_1$: same weights, rates at $\tau^{\text{h2avg}}_{pc}$ (Post-July 2025 USMCA claim rates).
- $S_2$: same rates as S1, weights at actual monthly $w_{pc}(t)$.
- $S_3$: same weights as S2, rates with non-USMCA preferences applied.
- $T$: Treasury actual.

Key methodological note: the cell-level rates are produced by the tariff-rate-tracker pipeline using the same authority-stacking and metal-content rules across all four scenarios — only the USMCA claim-rate input differs. Day-weighted across HTS revisions within each month, so mid-month policy changes (Liberation Day on April 2, for instance) are correctly captured.

Defer the partition (Shapley between/within) to slide 10.

---

## Slide 7 — Data sources

Map each data source back to the formal model:

- **Census IMDB bulk** (HS10 × country × month): the source of monthly trade data and Census-collected duties. Available through **February 2026**. Two columns matter for us: `con_val_mo` (consumption value — what U.S. importers brought in for consumption that month) and `cal_dut_mo` (calculated duties — Census's reported per-cell duty). The first feeds the monthly weight $w_{pc}(t)$; the second underlies our S4 anchor.
- **USITC DataWeb** (HS10 × country × month, USMCA program codes S/S+): provides the USMCA claim shares that scale the per-cell rates. We use three derived scenarios — 2024 baseline (for S0), post-July 2025 average (for S1, S2 — the framework anchor), and monthly empirical (for the explainer figure only).
- **Tariff Rate Tracker** (Yale Budget Lab sibling repo): produces the per-(HS10 × country × revision) statutory rates by parsing HTSUS and Chapter 99 text. Authority stacking, MFN exemptions, IEEPA floors all live here. Day-weighted within months gives us $\tau^{\text{tier}}_{pc}(t)$.
- **U.S. Treasury monthly customs duties** (direct cite to the Treasury Monthly Treasury Statement / Daily Treasury Statement series): provides $T$. Reported aggregate-only — **not disaggregated by country or product**. This is why our S4→T channel cannot be split per partner or product group.

The Census ↔ Treasury distinction matters: Census reports calculated duties from importer-declared entries (pre-refund, pre-collection). Treasury reports actual cash duties collected. The S4→T gap captures the difference.

---

## Slide 8 — S0→S1: USMCA adjustment (backstory)

(The bullets that previously appeared on this slide, expanded into prose.)

The USMCA claim rate for Canadian and Mexican imports moved from roughly 38% (CA) and 50% (MX) in 2024 to ~89% by post-July 2025. This is one of the largest single-channel movements in the entire panel — averaging ~2.6 pp across our window — but most of it is **retrospective**. Two factors drove it:

First, firms filed USMCA claims late in 2024–early 2025; once tariffs ramped up at Liberation Day, the incentive to retroactively claim USMCA increased materially. Second, in **July 2025** USITC's reporting framework changed and the underlying USMCA utilization became visible in DataWeb. So part of the apparent ramp is paperwork catching up with reality, not a real-time behavioral response.

We treat this as backstory and absorb it upfront so the policy-relevant trade-diversion channel (S1→S2) is uncontaminated by the claim-rate normalization. The two figures on the slide make this concrete: the left panel shows USMCA pulling away from the rest of the gap stack over time; the right panel shows Canadian and Mexican statutory ETRs under three USMCA assumptions converge from the 2024 baseline to the post-July 2025 baseline mid-2025.

The S0→S1 step is mostly one-signed (USMCA gained share); it is the only channel where this is the case.

---

## Slide 9 — Full gap decomposition (S1 → Treasury)

The stacked-bar figure shows the three sub-channels of the main analytic gap (S1→T) per month:

- Trade diversion (S1→S2): composition shifts in monthly weights, USMCA fixed.
- All-other preferences (S2→S3): non-USMCA preference claims (Annex II / ITA / Ch98 / KORUS / GSP / FTAs).
- Residual + timing (S3→T): cell-level rate discrepancies + Treasury–Census aggregation timing.

Visually: trade diversion is the largest bar in most months; other preferences is the smallest; residual+timing is highly variable, expanding around major policy events and contracting late in the panel. By February 2026 the residual+timing segment is essentially zero (or slightly negative).

---

## Slide 10 — Two ways of decomposing by group

Two complementary lenses for the per-channel attribution that follows.

**(a) Shapley two-way decomposition.** For any channel where weights shift and rates hold (S1→S2 is the prototype), partition cells by group $g$ (partner_group or product_group). Symmetric Shapley splits the aggregate gap into:
- **Between-group**: shifts in group $g$'s share of total imports (composition).
- **Within-group**: shifts in the rate $R_g$ itself (which arises from product mix changes inside group $g$).

Both partitions sum exactly to the total channel gap at each month.

**(b) Average ETR within each group.** For the same channels, plot per-group ETR series under the two weighting schemes (or the two rate panels). Each panel shows two lines; the visible gap between them is that group's contribution to the channel after sharing-weight scaling. This is the more readable version for non-technical audiences.

Both views answer the same question (where does the channel concentrate?) but with different visual primitives. The talk shows both.

---

## Slide 11 — S1 → S2: trade diversion

This is the policy-relevant trade-diversion step. In this step:

- Hold all ETRs fixed (rates, including USMCA claim shares at post-July 2025).
- Shift weights from 2024 import-share baseline to actual monthly real-time trade weights.

Whatever moves in the aggregate ETR between S1 and S2 is, by construction, attributable to changes in the import basket — which countries are sending us how much, and what they're sending. The next four slides break this out by country and by product, both via the Shapley decomposition and via per-group average ETR.

Note timing: the trade-diversion gap is non-trivial almost from the start. By April 2025 (the first month with Liberation Day rates active) the gap is already +3.13 pp. This contradicts the slow-substitution narrative from 2018–19 (Cavallo et al. 2021); 2025 supply chains responded immediately.

---

## Slide 12 — S1 → S2 by country (Shapley)

Per-month, per-partner-group contribution to the S1−S2 gap, broken into between-country and within-country at the underlying Shapley level. The figure shows the totals stacked.

Speaker notes (the bullets removed from the slide):

The China bar dominates. Period-mean China contribution is **+2.13 pp** (between-country +2.07, within-country +0.06) — China alone carries roughly 90% of the entire trade-diversion channel. This is between-country: China's share of total U.S. imports dropped substantially as Liberation Day and post-Liberation reciprocal tariffs took effect.

ROW shows a persistent **negative** contribution (period mean −0.47 pp): low-tariff partners (Vietnam, India, etc.) gained share. The negative sign just reflects the convention that positive = positive contribution to S1−S2; gaining low-tariff share pulls the monthly-weighted ETR down, which makes the gap contribution negative.

CA and MX show small contributions because their trade is concentrated in inelastic high-tariff categories where share didn't move much; the within-country term (~+0.10 pp for both) reflects modest internal mix shifts.

Other partners (EU, UK, JP, KR) all sit below 0.20 pp.

---

## Slide 13 — S1 → S2 by country (Avg ETR)

Same channel, different lens. The 8-panel facet shows per-country statutory ETR under two weighting schemes — S1 (2024 weights, blue) and S2 (monthly weights, dashed). The visible gap between the two lines per panel is that country's contribution to the trade-diversion channel.

Visually: tight S1≈S2 in panels for stable-share partners (UK, JP); visible spread in China (S2 well below S1 — China's monthly weight dropped); inverse spread in ROW (S2 above S1 — ROW gained share at lower tariffs). CA and MX show modest spreads consistent with the small Shapley contributions on the prior slide.

---

## Slide 14 — S1 → S2 by product (Shapley)

Same Shapley two-way, partition by 9-group product taxonomy.

Period-mean contributions by product group (pp):
- **Autos & Auto Parts: +0.59** (between-product +0.56, within-product +0.03) — auto imports compressed substantially under S232 autos at 25%.
- **Other Manufactured: +0.49** (between −0.39, within +0.88) — within dominates: composition inside the catchall shifted toward less-tariffed sub-categories.
- **Electronics & Machinery: +0.34** (between −0.42, within +0.76) — electronics share *rose* (gained ground as steel fell), but the bilateral within-mix moved to lower-tariff variants.
- **Steel & Aluminum: +0.33** (between +0.29, within +0.03) — imports compressed under S232 50% rates.
- **Apparel & Textiles: +0.27** (between +0.20, within +0.08).
- Chemicals & Plastics: +0.15 (within dominates).
- Food & Agriculture: +0.05.
- Pharmaceuticals: +0.03.
- Energy & Minerals: −0.004.

**Two-pattern story**: high-tariff goods (Steel, Autos) lose share via the *between-product* term; medium-tariff catchall categories (Other, Electronics) gain share but shift their internal mix toward lower-tariff variants via the *within-product* term. Both Shapley terms matter materially.

---

## Slide 15 — S1 → S2 by product (Avg ETR)

The 9-panel product facet — same construction as slide 13 with `product_group` instead of `partner_group`. Largest visible spreads are in Steel & Aluminum and Autos & Auto Parts (high-tariff goods that compressed). Electronics shows narrow spread because the within-mix dominates and partly cancels out at the panel level.

---

## Slide 16 — S2 → S3: all-other preferences

Simplified narrative for the non-USMCA preferences rung.

Three **groups** of preference channels, classified from IMDB importer-declared codes:

1. **Major IEEPA carve-outs** — Annex II exemptions, ITA (Information Technology Agreement), Chapter 98 (Berman Amendment, re-imports, returned goods), generic pharmaceuticals. These are the policy-salient subset because they reduce *both* the MFN base rate *and* the IEEPA reciprocal layer. The executive-branch carve-outs from the reciprocal regime live here.

2. **Bilateral free-trade agreements** — KORUS (Korea), AU/IL/SG/CL/CO/PE/PA/JO/MA/OM/BH (smaller bilateral FTAs). Reduces MFN base only.

3. **GSP / AGOA** — Generalized System of Preferences, African Growth and Opportunity Act. Reduces MFN base only.

The math is per-cell: subtract a `delta_base` from the MFN portion (proportional to the sum of duty-free + KORUS + GSP + other-FTA shares) and a `delta_recip` from the IEEPA reciprocal portion (only for the duty-free share). Floor at zero so the rate doesn't go negative. Aggregate to monthly with the same machinery as the rate panels in earlier slides.

Magnitude: ~0.5–0.9 pp late-period — small in pp terms but large in dollar terms because the IEEPA reciprocal layer is the largest single rate component for many cells. The dominant subgroup is the IEEPA carve-out term (Annex II / ITA / Ch98 / pharma).

The figure on the slide is an aggregate stacked bar of S2−S3 contribution by preference channel per month, built from `fta_decomp_monthly.csv` (created in 04_fta_decomposition).

---

## Slide 17 — Understanding the residual: Treasury versus Census Actual ETRs

Definitions:
- **Census ETR (S4)**: aggregate calculated duty / aggregate import value, computed at the cell level from IMDB and summed. Captures duties as importers *report them at entry*, before refunds and post-entry adjustments.
- **Treasury ETR (T)**: aggregate customs duties / aggregate goods imports, from the Monthly Treasury Statement. Captures actual *cash collected*.

What Census *captures*: per-cell statutory exposure under whatever authority the importer declares. It is sensitive to mis-classification, specific-duty AVE failures, and AD/CVD that the tracker doesn't model.

What Census *misses*: post-entry adjustments, refunds, drawback, FTZ deferrals, ACH-payment lags. These produce the S4→T gap.

Drivers of divergence:
- **S3 → S4** (rate-vs-collected, cell level): specific-duty AVE failures, AD/CVD, tracker-side errors in modeling rare authorities, behavioral noise inside high-volume HS10 cells.
- **S4 → T** (Census-vs-Treasury aggregation): refunds and drawback (importers reclaim duties on re-exports), FTZ-bonded goods that defer duty, cash-vs-accrual timing, ACH payment scheduling (up to 6 weeks per Azzimonti).

In our panel, S4 ≈ T most months — but the size of the S4→T gap is itself informative. By February 2026 it has compressed to near-zero (T slightly exceeds S4, the first time in the window) — frictions are unwinding.

---

## Slide 18 — S2 → S4 by country (Shapley)

Stacked bar of per-country contribution to the S2−S4 gap (combined other-preferences + residual). Sourced from `figure_s2s4_gap_country`.

Reading the figure: most of the dollar volume sits in a handful of country slots. CA and MX dominate the early-period (large IEEPA fentanyl exposure that didn't translate to collections). EU and ROW gain prominence late-period as the residual+timing channel matures.

---

## Slide 19 — S2 → S4 by country (Avg ETR)

The 8-panel facet of S2 vs S4 lines per partner. Visible spread per panel = country's S2−S4 gap. Largest visible gaps in CA, MX (S232 + IEEPA fentanyl), and tail-period in EU.

---

## Slide 20 — S2 → S4 by product (Shapley)

Stacked bar by product group. Steel & Aluminum and Apparel show the largest sustained gaps (specific-duty AVE issues + late-shipment frictions). Pharmaceuticals essentially zero (Annex II carve-out).

---

## Slide 21 — S2 → S4 by product (Avg ETR)

The 9-panel facet of S2 vs S4 lines per product group. Same story visually — apparel, food, energy show persistent S4 below S2 through most of the window, indicating systematic implementation frictions in those categories.

---

## Slide 22 — All four channels at once

Synthesis figure: four-panel facet showing per-country contribution to each of the four decomposable channels (USMCA adjustment, trade diversion, other prefs, residual). Common y-axis so magnitudes are comparable.

Reading top-to-bottom (or panel-by-panel):
- **Adjustment**: CA + MX dominate by construction (USMCA only applies there).
- **Diversion**: China alone carries the bulk.
- **Other prefs**: small, broadly distributed.
- **Residual**: widest dispersion. CA + MX large mid-2025; ROW + EU prominent late-period.

Treasury timing (S4→T) is aggregate-only and not shown.

---

## Slide 23 — Open questions

Three open questions our framework opens but cannot fully close:

1. **Convergence**. Does the gap continue to compress as frictions resolve? The Feb 2026 sign-flip in the **timing** channel (gap_timing = S4−T turned to **−2.01 pp** — Treasury collected $2 of every 100 import dollars *more* than IMDB shows declared) is the strongest single signal in our panel. Cumulatively (Feb 2025–Feb 2026), Treasury has over-collected by **~$10.5B** relative to IMDB. The structural residual (S3−S4 = +1.83 pp) is *not* converging — Census-declared duties keep undershooting the cell-level reconstruction. Eck et al. (2026) predict frictional gaps compress as frontloading depletes; the timing channel matches that prediction; the residual channel does not.

2. **Annex II quantification**. The largest single chunk of S2→S3 likely sits in the IEEPA carve-out term (duty_free with IEEPA recip exemption). Decomposing further by HS2 inside Electronics × Pharma would tell us how much of the Annex II story is which product class. Currently lumped at the channel level.

3. **2018–19 comparison**. Eck et al. find the 2018–19 episode had a 22% gap fraction; 2025 has 44%. Re-running our framework on 2017–19 data would test whether the channel mix has structurally changed or whether the broader concentration alone explains the doubling.

Bonus diagnostic: the tracker-miss / tracker-over CSVs we produce (`05a` / `05b`) bound how much of the residual is measurement error vs genuine behavior. Currently a sanity check; could be tightened with focused HS10-level audit.

---

## Slide 24 — Closing

Brief acknowledgement and pointer to the public code repository (`johniselin-budget-lab/tariff-etr-eval`).

Q&A.
