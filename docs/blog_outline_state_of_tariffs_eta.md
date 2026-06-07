---
output:
  word_document: default
  html_document: default
---
# Blog outline — Putting a number on the tariff "compliance gap"

**Working title options**
- *How much of the tariff actually gets paid? Replacing a rule of thumb with data*
- *Statutory vs. collected: calibrating the tariff compliance gap*
- *The 10% question: what the data say about tariff collection shortfalls*

**Audience / venue:** Budget Lab public blog, companion to the *State of U.S. Tariffs* series.
General-interest-but-numerate (press, Hill staff, fiscal analysts).

**One-sentence thesis:** Announced tariff rates badly overstate what Treasury actually collects;
our *State of Tariffs* model has always corrected for this with a flat 10% assumption, and newly
assembled data on actual-versus-statutory collection let us make that correction empirical — which
turns out to imply a *larger* and *regime-dependent* discount than the round 10% we had been using.

**Length / format:** ~1,200–1,600 words, 3–4 charts. Lead with the puzzle, keep the method light
(link to the methodology doc), land on the policy takeaway.

---

## 1. Hook — the announced rate is not the paid rate

- Open with the gap everyone has noticed: announced statutory rates ran into the mid-teens through
  2025, but Treasury collected far less. (Lead chart: announced statutory vs. Treasury-realized ETR,
  monthly — our headline figure.)
- The gap is not measurement noise and not a scandal; it is the predictable product of trade
  shifting, statutory carve-outs, collection frictions, and some noncompliance. The question for a
  forecaster is not *whether* to discount the announced rate, but *by how much*.
- Frame: this post is about that discount — what it is, how we have handled it, and how we are now
  pinning it down with data.

## 2. Why this matters for our numbers

- Three downstream consequences of getting the discount wrong (revenue projections, pass-through /
  price estimates, and the implied burden on households and partners).
- The discount is large enough to swing 10-year revenue and the headline household-cost figures —
  so a defensible value matters.

## 3. How our model handles it today

- Brief, honest description of the current State of Tariffs / Tariff Model pipeline:
  statutory rates (from our tariff-rate tracker) → trade-model substitution (GTAP) → revenue,
  prices, macro.
- The model already separates a **pre-substitution** rate (statutory on a fixed basket) and a
  **post-substitution** rate (after the import basket shifts toward cheaper origins).
- The one remaining catch-all: a **compliance parameter** that reduces collected revenue below the
  post-substitution statutory level. Today it is a flat **10%** ("a reduction in collections due to
  noncompliance and evasion"), applied to gross tariff revenue. (Note for accuracy: a *separate* 23%
  income/payroll-tax offset is not part of this — we are only refining the 10% compliance piece.)
- Plain-English admission: 10% was a sensible round number, not an estimate. We can now do better.

## 4. New ingredient — measuring the gap, cell by cell

- Introduce the actual-vs-statutory exercise: we reconstruct the statutory rate for every
  product × country cell from the tariff schedule, and compare it to what was actually collected,
  using two collection measures — **Census-declared** duties (available cell by cell) and
  **Treasury** cash receipts (the ground truth, but aggregate-only).
- The ladder, in one sentence each: announced → composition (basket shifts) → preferences
  (Annex II / ITA / Chapter 98, KORUS, GSP) → residual (specific-duty AVE failures, AD/CVD, noise)
  → timing (refunds, deferrals, cash-vs-accrual). (Chart: the stacked decomposition.)
- Key clarification for readers: because the model already handles composition, the compliance
  parameter should capture *everything after* composition — preferences, residual, and timing —
  not the basket shift.

## 5. Turning the gap into a parameter

- Define the compliance parameter simply: one minus the ratio of collected to statutory revenue.
  Calibrated so the adjusted statutory rate reproduces what Treasury actually took in.
- Three flavors, increasing in detail: (a) one number for the whole economy; (b) numbers that vary
  by country and by product; (c) a full country-by-product schedule.
- The honest constraint, stated plainly: Treasury totals can pin down *one* number; to let the
  parameter vary by country or product we have to borrow the *shape* from the cell-level Census
  data and set the *level* to Treasury.
- The test that makes it credible: calibrate on the IEEPA period (through February 2026), then
  predict March 2026 — the first month after the Supreme Court struck down the IEEPA tariffs — and
  see how close we get. A real out-of-sample test across a genuine policy regime change.

## 6. What we find

*Calibrated on the IEEPA regime, January 2025 through February 2026; all figures from
`code/R/08_eta_calibration.R`.*

- **The single-number answer is bigger than 10%.** Setting aside the chaotic first few months of
  2025 (more on that below), the composition-adjusted compliance gap calibrated to Treasury is
  about **19%** — Treasury collected a **10.4%** effective rate against a statutory **12.7%** over
  May 2025–February 2026. Including the volatile January–April ramp raises it to about **23%** (the
  full-window value). Either way it is roughly **double** the flat 10% the model has been using, and
  on the *announced* (fixed-2024-basket) basis the gap is larger still — about **32%** post-April,
  **38%** over the full window — with the ~13–15-point difference between the two bases being the
  import-composition channel the model already handles separately. The takeaway is not that 10% was
  a rough central value; it is that 10% was **too low**: importers declared duties roughly a quarter
  below the reconstructed statutory schedule, before any timing adjustment.
- **It moves a lot month to month — and the early months are a timing artifact.** The monthly gap
  was widest during the spring-2025 rate ramp-up — around **50%** in February–April 2025, when
  statutory rates jumped well ahead of the cash Treasury actually booked — then narrowed to the low
  teens or single digits by late 2025/early 2026 as collections caught up, before widening again to
  ~20% in March 2026 when the regime changed. (Chart: calibrated η by month, with the flat 10%
  line and both calibrated constants — full-window ~23% and post-April ~19%.) That the early width
  is mostly a **cash-timing lag** rather than structural noncompliance is something we can show, not
  just assert: dropping January–April moves the *Treasury*-based gap from ~23% to ~19%, but the
  *Census-declared* gap — which strips out the Census-to-Treasury timing wedge — barely budges
  (~25% to ~23%). The piece that disappears when we drop the ramp is almost entirely timing, so the
  post-April **~19%** is our preferred central estimate and the structural declared shortfall sits a
  couple of points above it.
- **Where the gap concentrates.** The shortfall is highly uneven. By partner it is largest for
  **Canada (~52%) and Mexico (~51%)** — where high IEEPA/fentanyl statutory rates met heavy USMCA
  and carve-out exemptions — followed by the rest of the world (~30%) and China (~15%), and is
  small or even slightly negative for the EU, Korea, UK, and Japan (where declared duties roughly
  match or marginally exceed the modeled statutory rate). By product it tracks statutory carve-outs
  almost mechanically: nearly total in energy (Ch. 27, ~94%), Chapter 98 special classifications
  (~90%), and pharmaceuticals (Ch. 30, ~69%); large in machinery (Ch. 84, ~47%) with its many
  Section 301 exclusions; and smallest in fully dutiable categories like apparel (Ch. 61, ~8%).
  (Chart: η by partner and by product, HTS-2 chapter.)
- **Simpler is no worse, so we keep it simple.** We used the March 2026 regime change — the first
  month after the Supreme Court struck down the IEEPA tariffs — as a live stress test: calibrate on
  2025, then predict the post-IEEPA month cold. A single economy-wide number predicts March about as
  well as the detailed country-by-product schedules; all land within roughly **half a percentage
  point** of what Treasury actually collected (7.3%). The granular versions fit the 2025 data more
  tightly but travel no better across the regime break — the part of the estimate that *does* move is
  the collection-timing lag, not the country-and-product detail. So we adopt the single calibrated
  number and keep the detailed schedule in reserve. (Chart: train-vs-test fit by specification.)

## 7. What changes in the *State of Tariffs* report

- Concrete update: replace the flat 10% with the calibrated value — the composition-adjusted,
  Treasury-pinned constant, using the post-April **~19%** as the central estimate (the full-window
  ~23% as a with-ramp upper bound), recalibrated as the regime evolves and potentially varied by
  fiscal year. The country/product schedule is held in reserve: it does not meaningfully beat the
  constant out of sample, so the simpler parameter is what we adopt.
- Be candid about direction and size: this roughly doubles the compliance discount, from 10% to
  ~19% on the composition-adjusted base, so it **lowers projected net tariff revenue** relative to
  the prior assumption. It is a genuine revision, not a cosmetic one — but it makes the revenue path
  empirically grounded rather than assumed, and it is the change the data clearly call for.
- Note the option (flagged, not yet adopted) to apply the same empirical discount consistently to
  the price/macro side, not just revenue: if a larger share of duties is never collected, the
  associated consumer-price effect is correspondingly smaller, which would partly offset the
  revenue change in the household-burden numbers.

## 8. Caveats (short, candid)

- The parameter is a *compliance gap*, not pure evasion — it bundles exemptions, AVE failures,
  AD/CVD, and measurement error.
- It is regime-dependent and will need periodic recalibration as the tariff structure evolves
  (and as Section 122's statutory clock runs).
- Census-declared duties are not Treasury cash; the timing wedge between them has been large and
  volatile lately (Treasury over-collecting by roughly \$12 billion cumulatively through March 2026).

## 9. Close

- Tie back to the mission: announced rates are a poor guide to realized burden, and good fiscal
  analysis means measuring the gap rather than guessing it. Link to the methodology doc and the
  underlying actual-vs-statutory paper.

---

### Suggested charts
1. Announced statutory vs. Treasury-realized ETR, monthly (the puzzle).
2. The stacked gap decomposition (composition / preferences / residual+timing).
3. Calibrated constant η by month vs. the flat 10% line.
4. η by partner and by product (HTS-2 chapter), where the gap concentrates.
5. *(optional)* Train-vs-test fit by specification (detail doesn't help out of sample).

### Accuracy checklist before publishing
- [ ] Confirm `compliance_effect = 0.10` and `income_effect = 0.23` are still current in
      `Tariff-Model/config/global_assumptions.yaml`.
- [x] Replace all Section 6 placeholders with actual calibrated values and test errors.
      *(Done: composition-adjusted η ≈ 19% post-April (lead) / ~23% full window; announced-basis
      ~32% / ~38%; partner/product cross-section and OOS errors from
      `code/R/08_eta_calibration.R` → `results/tables/eta_{summary,by_window,...}.csv`.)*
- [ ] Confirm the cumulative Census–Treasury gap figure (\$12.1B through March 2026) against the
      latest `cumulative_duty_gap.csv`. *(Calibration train window through Feb 2026 shows Treasury
      over-collecting ≈ \$11B — \$318.4B cash vs \$307.6B declared; reconcile the through-March
      figure.)*
- [x] Verify which specification is recommended after seeing out-of-sample results.
      *(Constant, composition-adjusted: disaggregated specs do not beat it out of sample.)*
- [ ] Re-run the calibration and refresh all figures/numbers once March (or later) revisions are
      final, since η is regime-dependent and the test month sits right at the Section 122 break.
