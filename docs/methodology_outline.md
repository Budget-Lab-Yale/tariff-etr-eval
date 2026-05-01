# Actual vs Statutory ETR — Outline

> **Status (May 2026)**: supplementary methodology reference. Predates the May 2026 framework restructure (h2avg-USMCA spine, S4 tier inserted, channel relabeling). Specific script references and tier labels below may not match current file numbering — see `paper_outline_v2.md`, `six_tier_framework_plan.md`, and `CLAUDE.md` for the current canon. Kept for the §6–§7 implementation docket and §5 derivations, which are still load-bearing.

Single source of truth for the paper, the supporting code changes across this repo and `tariff-rate-tracker`, and the open questions still blocking prose. Subsumes the earlier sketch in `main.tex` and the tracker-side plan at `tariff-rate-tracker/docs/dense_rate_export_plan.md` (revised). Sections 1–4 map to the paper; §5 is the implementation plan; §6–7 are the working docket.

---

## 1. Overview and framing

We measure the gap between the **statutory** effective tariff rate (ETR) — rates as scheduled in the HTS plus Chapter-99 authorities — and the **actual** ETR collected by U.S. Customs, for the 2025–26 tariff escalation. We decompose the gap into a **six-tier ladder** with five sequential channels. Each rung holds one input fixed and varies one other input from the previous rung:

| Tier | Definition |
| --- | --- |
| $S_0$ | Statutory @ 2024 USMCA shares × 2024 import weights |
| $S_1$ | Statutory @ 2024 USMCA shares × **monthly** import weights |
| $S_2$ | Statutory @ **monthly** USMCA shares × monthly weights |
| $S_3$ | $S_2$ minus the **non-USMCA preference** rate reduction (Annex II / ITA / Ch98 / KORUS / GSP / other_fta), at monthly IMDB-derived shares |
| $S_4$ | Census collected ETR ($\sum_p$ cal_dut$_p$ / $\sum_p$ con_val$_p$ at HS10 × cty, summed) |
| $T$ | Treasury aggregate customs duties / imports value |

Channels by signed-sum identity $S_0 - T = (S_0-S_1) + (S_1-S_2) + (S_2-S_3) + (S_3-S_4) + (S_4-T)$:

- $S_0 - S_1$ = **trade diversion** (composition shift in monthly weights, USMCA held at 2024 baseline)
- $S_1 - S_2$ = **USMCA surge** (claim-rate dynamics; ~38% → ~89% for CA, ~50% → ~89% for MX by late 2025)
- $S_2 - S_3$ = **all-other preferences** (importer claims of Annex II / ITA / Ch98 / KORUS / GSP / other FTAs)
- $S_3 - S_4$ = **residual** (specific-duty AVE failures, AD/CVD, tracker error not corrected, behavioral noise within HS10 × cty)
- $S_4 - T$ = **collections gap** (timing / refunds / FTZ deferrals / cash-vs-accrual)

The first two channels are **sign-bearing** (they can be negative — see `docs/six_tier_framework_plan.md` §5a for why). The all-others rung $S_2 - S_3$ is structurally non-negative by the delta math.

Math derivation (per-authority applicability matrix $\alpha_q^A$, cell-level effective rate, tier definitions in terms of share inputs, S2→S3 implementation as authority-component subtraction, caveats): see `docs/six_tier_framework_plan.md` §6.

Relation to existing work (pointer, not re-derived): Gopinath-Neiman (2026) decompose using product-country-level rates and actual imports; Fajgelbaum et al. (2020) estimate pass-through on Trump I tariffs; Tariff-ETRs publishes their own statutory series using similar dense-rate machinery. See `docs/etr-literature-review.md` — a §2.4 or §4.4 in the paper should place this decomposition against those.

### Mapping to the older four-tier framework

The four-tier framework ($T_1$ – $T_4$) used in earlier drafts and in section B of `02_etr_analysis.do` (Shapley) maps as follows: $T_1 \approx S_0$, $T_2 \approx S_1$, $T_3 = S_4$, $T_4 = T$. The six-tier framework refines $T_2 - T_3$ (the old "exemptions" channel) into $S_1 - S_2$ + $S_2 - S_3$ + $S_3 - S_4$ — separating USMCA dynamics, all-other preferences, and within-cell unmodeled effects. Older $T_1$/$T_2$ were computed at h2avg USMCA shares (production rates), while new $S_0$/$S_1$ use 2024-baseline USMCA shares; values differ by ~1pp at most.

---

## 2. Data

### 2.1 Statutory rate inputs (via `tariff-rate-tracker`)
- **HTS JSON archives** — 39 revisions (HTS 2025 basic → HTS 2026 rev_5). MFN general rates parsed per HS10 in `src/04_parse_products.R`; every product has a `base_rate`.
- **Chapter-99 footnote authorities** — 232 (steel/aluminum/copper/autos/MHD), 301 (China), IEEPA reciprocal (Phase 1/Phase 2), IEEPA fentanyl (CA/MX/China), Section 122 (2026), Section 201, and "other" (residual). Stacking per Tariff-ETRs convention: mutual exclusion between 232 and IEEPA on pure-metal products; per-metal-type `*_share` weighting on derivatives; fentanyl stacks at full value; USMCA exemption applies to non-232 authorities plus the auto/MHD share of 232.
- **Specific / compound duties** — converted to ad-valorem equivalents at the HS10 level using 2024 average unit values. Pairs where the 2024 unit value is missing fall back to the MFN component of the stacking output; this residual needs to be quantified.
- **USMCA utilization shares** from USITC DataWeb SPI program codes (`S`/`S+`), product-level. Applied per scenario (§3.2).

### 2.2 Trade flow inputs
- **2024 annual import weights** $i_{cp,2024}$: Census HS10 × country 2024 values. ~333k pairs with positive imports. Written to `import_weights_2024.csv` by tracker; consumed in eval as the Tier-1 weight base.
- **Monthly Census trade** $i_{cpt}$, 2025-01 through present:
  - IMDB bulk ZIPs (HS10 × country × district × preference × month) for completed months — used for Tier 3 numerator (calculated duty) and the FTA decomposition / district crosscheck;
  - Census API HS10 fallback for months not yet in IMDB.
- **Treasury revenue** $R_t$ (monthly): customs duties collected + goods imports value, from `tariff-impact-tracker`. Used for $T_4$.

### 2.3 Analysis window
January 2025 through the most recent complete month (currently February 2026). 14 months as of 2026-04-17.

---

## 3. Methods

### 3.1 Construction of $\tau^{s}_{cpt}$

For each HS10 $p$, country $c$, and day $t$, the statutory rate is

$$\tau^{s}_{cpt} \;=\; \mathrm{stack}\!\left(r^{\text{MFN}}_{pt},\, r^{232}_{cpt},\, r^{301}_{cpt},\, r^{\text{IEEPA-recip}}_{cpt},\, r^{\text{IEEPA-fent}}_{cpt},\, r^{122}_{cpt},\, r^{201}_{pt},\, r^{\text{other}}_{cpt}\right).$$

Key construction decisions (to include in the paper, not just the code):

- **Dense universe.** $\tau^{s}_{cpt}$ is defined for every HS10 in the parsed HTS and every Census trading country. MFN-only pairs (no Chapter-99 reference) take $\tau^{s}_{cpt} = r^{\text{MFN}}_{pt}$. This is a departure from the sparse policy-only export historically produced by the tracker; see §5.1.
- **AVE conversion.** Specific duties are converted to ad-valorem at HS10 using 2024 average unit values. State this upfront.
- **Revision boundaries.** Rates are piecewise-constant across HTS revision effective dates. Daily $\tau^{s}_{cpt}$ snaps to the active revision; monthly $\tau^{s}_{cp,t(\text{month})}$ is the **day-weighted mean** within the month. Liberation Day (2025-04-02), Phase 2 (2025-07-01, 2025-08-07), and the SCOTUS S.122 date (2026-02-24) each create mid-month rate changes that the day-weighting must handle correctly.

### 3.2 USMCA scenarios

USMCA eligibility reduces $\tau^{s}_{cpt}$ on CA/MX-imported, USMCA-eligible products by multiplying the non-232 authority components by $(1 - s_{cp})$, where $s_{cp}$ is the USITC DataWeb S/S+ utilization share at the scenario's mode. We report results under four scenarios:

| Label | Shares | Interpretation |
| --- | --- | --- |
| `usmca_none` | $s_{cp} \equiv 0$ | Upper bound on statutory — no one claims |
| `usmca_2024` | Annual 2024 | Pre-tariff baseline claiming |
| `usmca_monthly` | Actual monthly 2025+ | Realized claim rates; retrospective only |
| `usmca_h2avg` | H2-2025 rolling average | Steady-state post-shock claim rate |

**Baseline for headline results: `usmca_h2avg`**, because it most closely matches realized post-shock claim rates and is the tracker's production default. Note this is the *lowest* statutory among the four — so $T_1^{\text{h2avg}}$ is a conservative measure of statutory. The `usmca_none` series is reported alongside as the upper bound.

**Reproducibility note.** `usmca_monthly` uses data that is only available with a DataWeb lag; it cannot be computed in real time. For nowcast use the paper should report `usmca_h2avg` or `usmca_2024`; `usmca_monthly` is a backward-looking comparator.

### 3.3 Trade weights and universe reconciliation

Two weight schemes:

$$T_1 \;=\; \tau^{s}_{t} \;=\; \frac{\sum_{c,p} i_{cp,2024}\,\tau^{s}_{cpt}}{\sum_{c,p} i_{cp,2024}} \qquad T_2 \;=\; \tau^{s\prime}_{t} \;=\; \frac{\sum_{c,p} i_{cpt}\,\tau^{s}_{cpt}}{\sum_{c,p} i_{cpt}}$$

The two series have **different denominators** (fixed 2024 total vs monthly total). For any pair $(c, p)$:

| 2024 imports $i_{cp,2024}$ | Month-$t$ imports $i_{cpt}$ | Weight in $T_1$ | Weight in $T_2$ |
| :---: | :---: | :---: | :---: |
| $>0$ | $>0$ | $i_{cp,2024}$ | $i_{cpt}$ |
| $>0$ | $=0$ | $i_{cp,2024}$ | $0$ |
| $=0$ | $>0$ | $0$ | $i_{cpt}$ |

Row 3 — trading relationships new in 2025-26 — are retained in $T_2$ with positive weight. This asymmetric treatment is what makes $T_1 \ne T_2$ more than a pure scaling.

### 3.4 Four-tier decomposition, in detail

- $T_1$ and $T_2$ as above.
- $T_3 = \hat{\tau}^{a}_{t} = \sum_{c,p} d^{\text{calc}}_{cpt} / \sum_{c,p} i_{cpt}$. **Proxy assumption**: $d^{\text{calc}}_{cpt} \approx i_{cpt}\tau^{a}_{cpt}$. Census calculated duties are entry-level, filed-at-entry, pre-refund. $T_3$ equals eq. (3)'s $\tau^{a\prime}_{t}$ under the proxy. The $T_2 - T_3$ gap captures both the genuine pair-level rate gap **and** any proxy error — flag explicitly in prose, not buried in limitations.
- $T_4$: Treasury goods customs duties divided by goods imports value, monthly. Source: BEA / Haver (to confirm — see §7).

Gap channels as labeled in §1. The signed-sum identity is a mechanical by-construction result; tables should row-sum to the total gap as a quick sanity check.

### 3.5 Aggregation hierarchy

Reported at three levels:
1. **Total** — all HS10 × country pairs.
2. **Partner group** — China, CA, MX, EU, Japan, S. Korea, UK, ROW.
3. **HS2 chapter** — 99 chapters.

All three aggregations use the same tier definitions with the sum restricted to the relevant subset.

### 3.6 USMCA counterfactual ladder

Parallel ladders at fixed 2024 weights and at monthly weights:

- $T_1^{\text{none}} \to T_1^{\text{2024}} \to T_1^{\text{monthly}} \to T_1^{\text{h2avg}}$ — isolates USMCA claim effects at fixed weights
- $T_2^{\text{none}} \to T_2^{\text{2024}} \to T_2^{\text{monthly}} \to T_2^{\text{h2avg}}$ — adds behavioral weight composition on top

Differences within a ladder give "claim any / surge / averaging" subcomponents. Differences between ladders give the interaction of USMCA response with weight composition. This cleanly separates what the old S0 → S1 → S2 code conflated.

---

## 4. Proxies and limitations

1. **Calculated-duty proxy** ($T_3$): entry-level, pre-refund, pre-enforcement adjustment. Over- or under-states $\tau^{a}_{cpt}$ depending on the direction of post-entry settlements.
2. **MFN coverage gaps**: tracker models general rates; column-2 countries (RU/CU/KP/BY post-2022), some ITA exemptions, GSP/AGOA beneficiaries are not applied at the country level beyond Chapter-99. Known residuals for limitations section.
3. **Specific-duty AVE**: 2024 unit-value-based conversion is a point-in-time approximation; fails on new HS10s and thin trade.
4. **USMCA measurement**: DataWeb S/S+ shares reflect what importers *claimed*, not what was *eligible*. `usmca_none` gives the "no claim" upper bound.
5. **Revision-date effects**: within-month rate changes are day-weighted; no intra-day variation modeled. Large changes (Apr 2025, Feb 2026) create sensitivity at the monthly aggregate.
6. **Treasury-Census denominator mismatch** ($T_3$ vs $T_4$): $T_3$ uses Census consumption-entry value, $T_4$ uses Treasury goods imports. Differences in timing, customs valuation, and coverage mean $T_3 - T_4$ is not pure enforcement.
7. **Pair-level trade lumpiness**: thin $(c,p)$ cells in a given month can swing sub-aggregates; inference / robustness checks should account for this.

---

## 5. Implementation plan

### 5.1 Changes in `tariff-rate-tracker`

Full plan: `tariff-rate-tracker/docs/dense_rate_export_plan.md` (revised, post-review). Summary:

- **Dense grid.** Extract `06_calculate_rates.R:909-943` (the `ieepa_was_invalidated` block) into a helper `ensure_dense_grid(rates, products, countries)`; call it unconditionally between step 6d (floor recomputation) and step 7 (USMCA). MFN-only pairs enter the grid with authorities zero and `base_rate` populated before USMCA applies.
- **Four USMCA scenarios** via the existing `build_alternative_timeseries()` harness in `09_daily_series.R:799`, with a small addition: optional `snapshot_out_dir` to persist per-revision snapshots to `data/timeseries/<scenario>/` rather than a tempdir.
- **`usmca_none` mode**: add to `load_usmca_product_shares()` in `data_loaders.R` returning 0% utilization everywhere.
- **Validation**: TPC match-rate regression on rev_6, rev_10, rev_17, rev_18, rev_32; expected daily-ETR shift of +1–2 pp for Jan-Mar 2025 (reclaimed MFN), ~0 after.

Handoff contract: four scenario subdirectories under `data/timeseries/`, same per-revision file names and schema as today, just denser.

**Open on the tracker side** (reproduced here for tracking):
- Layout: `data/timeseries/<scenario>/` vs `data/timeseries/scenarios/<scenario>/`.
- Symmetry for `usmca_h2avg`: populate a subdir, or keep top-level as the h2avg output?
- Any revisions with known HS10 parse gaps that will surface as false MFN-coverage holes.

### 5.2 Changes in `tariff-etr-eval` (this repo)

**R pull (`code/R/00_pull_raw_data.R`)**
- Pull from all four tracker scenario subdirs. Output: `data/raw/snapshot_rates/{scenario}/snapshot_*.csv`.
- Delete the `counterfactual_usmca2024.csv` / `counterfactual_usmca_monthly.csv` reconstruction block (§3d-3e) — that logic now lives in the tracker.

**Stata pipeline**
- `01_etr_clean.do`: rebuild the canonical analysis panel from the 2024 weight universe × month → revision × per-scenario dense rates. The merged panel is the union of 2024 pairs and 2025-26 monthly pairs (§3.3 rule). `merged_analysis.dta` becomes a secondary dataset used only where HS10 × country monthly trade is needed directly (e.g., Tier 3 numerator).
- `02_etr_analysis.do`: redefine Tier 1 / Tier 2 per §3.3–3.4; Tier 3 from Census calculated duties; Tier 4 from Treasury. Figures and tables update to the new definitions. The current behavior of dropping unmatched snapshot pairs with `total_rate = 0` goes away — everything is defined.
- `05_counterfactual_ladder.do`: replace the reconstructed S0 → S1 → S2 with the explicit USMCA ladders of §3.6. The "USMCA surge" and "trade diversion" channels become two orthogonal differences rather than a compound move.
- `06_baseline_etr_diagnostic.do`: retire. Its role (2024-weight ETR under tracker baseline USMCA) is now just $T_1^{\text{h2avg}}$.
- `03_fta_decomposition.do`: unchanged in intent; consumes IMDB detail for preference-claim decomposition of $T_2 - T_3$.
- `04_max_district_crosscheck.do`: unchanged.

### 5.3 Validation

- Signed-sum identity: $T_1 - T_4 = (T_1-T_2) + (T_2-T_3) + (T_3-T_4)$ to floating-point tolerance, for every month and every sub-aggregation.
- Dense-grid sanity: for each revision, $n_{\text{pairs}} \approx |\{\text{HS10}\}| \times |\{\text{countries}\}|$ after the tracker export. Spot-check 5 MFN-only pairs per revision.
- USMCA ladder monotonicity at 2024 weights: $T_1^{\text{none}} \ge T_1^{\text{2024}}$, $T_1^{\text{none}} \ge T_1^{\text{h2avg}}$. Other pairs not necessarily ordered.
- TPC regression per §5.1.

---

## 6. Open questions

**Paper-level (John to resolve)**
1. Headline scenario confirmation: `usmca_h2avg` baseline + `usmca_none` upper bound. Agreed?
2. Should the paper include a formal literature-positioning subsection (§2.4 / §4.4) referencing Gopinath-Neiman, Fajgelbaum et al., Tariff-ETRs?
3. Aggregation priority: which tables in main text, which in appendix? Proposal: total + partner group in main, HS2 chapter in appendix.
4. Include a §3.6 "USMCA ladder" as a separate section, or fold into the main decomposition as robustness?

**Cross-repo (tracker maintainer)**
5. Scenario subdirectory layout and `usmca_h2avg` output location (see §5.1 bullet).
6. Whether to collapse the `ensure_dense_grid` call placement decision before vs after the blanket-authority passes, or document both and pick on cost.
7. Any HS10 gap audit needed before dense export ships.

**Data proxy questions**
8. Confirm the Treasury $T_4$ series is goods customs duties / goods imports (Haver series ID, frequency, seasonal adjustment). Current `01_etr_clean.do:322` imports `tariff_revenue.csv` with `customs_duties`, `imports_value`, `effective_rate` — need to verify upstream Haver mnemonic.
9. Specify the specific-duty AVE fallback when 2024 unit value is missing (use tracker documented behavior).
10. Thin-trade HS2-chapter / partner-group cells: decide a reporting threshold (e.g., suppress if cell denominator < \$X).

---

## 7. Empirical TODOs before prose

- [ ] **Quantify "new in 2025-26" pairs**: count, total monthly imports ($M), share of $T_2$ denominator. Blocks settling the §3.3 universe rule in prose.
- [ ] **Measure the MFN-only reclamation effect**: rerun `06_baseline_etr_diagnostic.do` after the tracker ships the dense export; confirm the Jan-Mar 2025 $T_1$ shift is in the 1–2 pp range predicted.
- [ ] **Revision day-weight sanity check**: April 2025 monthly $\tau^{s}_{cp,t}$ for a high-tariff pair should be close to 29/30 of post-Liberation-Day rate + 1/30 of pre-. Spot-check on 5-10 pairs.
- [ ] **Treasury series definition**: resolve question 8.
- [ ] **AVE coverage audit**: count HS10s where the tracker has a specific duty but no 2024 AVE; share of 2024 imports affected.
- [ ] **Ladder monotonicity failures**: after the four scenarios land, flag any country / HS2 cell where $T_1^{\text{none}} < T_1^{\text{2024}}$ at the sub-aggregation level (may exist due to per-product 232 stacking interactions; worth investigating).
- [ ] **Sub-aggregation coverage**: partner-group and HS2 monthly denominators; flag cells with < \$100M that are unreliable.

---

## Appendix: what this file replaces

- Old scattered planning: the earlier `methodology_outline.md` (replaced by this), `dense_rate_export_plan.md` in this repo (deprecated — now lives only in tracker), and `dense_rate_export_plan_response.md` (superseded by the revised tracker plan).
- This outline is the single working document until the code changes in §5 land and we can draft §3–§4 of the paper directly from it.
