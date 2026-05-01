# Six-tier framework plan: implementation scope + math

**Authored**: 2026-04-28. **Last refreshed**: 2026-05-01 (tier definitions and channel labels updated to match the post-restructure h2avg-USMCA spine; math derivations in §5–§6 unchanged).

This doc is the standalone derivation source for the framework's math: the Shapley two-way decomposition (§5–§5a), the channel-ordering rationale (§4–§5), and the per-authority applicability matrix for the non-USMCA preference delta (§6, §6.6). Tier definitions are kept synchronized with `CLAUDE.md`; if the two ever diverge, `CLAUDE.md` is canonical.

**Companions**:
- `paper_outline_v2.md` — paper exposition target (subsumes the older `methodology_outline.md`).
- `tracker_miss_report.md` — Round 3 motivates the Annex II claim-rate channel that becomes part of S3.
- `tracker_over_report.md` — companion diagnostic (over-statement direction).

---

## 1. Motivation

The pre-restructure four-tier framework (T1 statutory @ 2024 weights; T2 statutory @ monthly weights; T3 Census collected; T4 Treasury) bundled the entire "exemptions" story into a single T2→T3 channel — at Feb 2026 ~6.4 pp, confounding USMCA share dynamics with Annex II / ITA / Ch98 claims, KORUS / GSP / other-FTA preferences, and unmodeled residuals (specific-duty AVE failures, AD/CVD, tracker error, behavioral noise).

The six-tier framework below decomposes that channel cleanly. After implementation, an additional tier (S4 = Census-collected) was inserted between S3 and Treasury, and the USMCA layer was rebuilt around an H2-2025 average claim-rate panel (`rate_h2avg`) so that S1 — the framework anchor — equals the tracker's daily ETR collapsed monthly by construction. The S0→S1 USMCA adjustment becomes "explainable backstory"; main analysis lives between S1 and Treasury.

## 2. Tier definitions

| Tier | Definition | Rate panel × Weight |
|---|---|---|
| **S0** | Statutory @ USMCA 2024 baseline × 2024 weights | `rate_2024` × `imports` |
| **S1** | Statutory @ USMCA H2-2025 baseline × **2024** weights (framework anchor; equals tracker daily ETR collapsed monthly) | `rate_h2avg` × `imports` |
| **S2** | Statutory @ USMCA H2-2025 baseline × **monthly** weights | `rate_h2avg` × `con_val_mo` |
| **S3** | S2 minus non-USMCA preference Δ (Annex II / ITA / Ch98 / KORUS / GSP / other_fta) | `rate_all_pref` × `con_val_mo` |
| **S4** | Census collected ETR (HS10 × cty, summed) | `cal_dut_mo / con_val_mo` |
| **T** | Treasury actual ETR (aggregate revenue / aggregate imports) | tariff revenue file |

## 3. Channel decomposition

| Channel | Definition | Interpretation |
|---|---|---|
| **USMCA adjustment** | $S_0 - S_1$ | CA/MX claim-rate normalization 2024 → H2-2025 baseline (~38% CA / ~50% MX → ~89% both); weights frozen at 2024. Mostly retrospective — paperwork caught up after July 2025 USITC reporting change. Backstory; main analysis is S1→T. |
| **trade diversion** | $S_1 - S_2$ | Composition shift in monthly weights with USMCA stable at H2-2025 baseline. Decomposed Shapley two-way (between-group + within-group) in §5–§5a. |
| **all-others** | $S_2 - S_3$ | Non-USMCA preference claiming: Annex II / ITA / Ch98 / KORUS / GSP / other FTAs. Structurally non-negative. |
| **residual** | $S_3 - S_4$ | Within-cell unmodeled effects: specific-duty AVE failures, AD/CVD, tracker error not yet corrected, behavioral noise. |
| **timing** | $S_4 - T$ | Treasury vs Census aggregation, refunds, post-entry adjustments, FTZ deferral, cash-vs-accrual. |

## 4. Channel-ordering rationale

The ladder is sequential, so the magnitude of each rung depends on the order in which channels are applied. The chosen order — **USMCA adjustment → trade diversion → all-others → residual → timing** — places USMCA before trade-diversion (composition). The S0→S1 USMCA adjustment "spends" the claim-rate ramp at fixed 2024 weights *before* the diversion channel re-weights to monthly composition. Justification:

1. **USMCA-as-backstory framing.** S0→S1 (USMCA adjustment) holds weights at 2024 and lets USMCA shares move from 2024 baseline to H2-2025 baseline. This isolates the claim-rate normalization from any composition story. The mid-2025 reporting-pattern shift becomes its own rung; the policy-relevant signal lives between S1 and Treasury. Aligning S1 with the tracker's daily ETR (collapsed monthly) makes S1 the framework anchor and lets the paper's headline figure double as the framework backbone.

2. **Data confidence ordering.** USMCA shares are sourced from USITC DataWeb's SPI program codes — authoritative, audited, in the tracker. The all-others share is reconstructed from IMDB importer-declared `rate_prov` + `cty_subco`, which is good data but involves classification choices (the 9-channel taxonomy) and edge cases (a `rate_prov = 19` could reflect Annex II, ITA, Ch98, Berman — we collapse them). Putting the higher-confidence USMCA channel first means measurement error in the all-others reconstruction lands on its own rung rather than contaminating the USMCA estimate.

3. **Mutual exclusivity at the entry level.** USMCA claim and Annex II / ITA / KORUS / GSP claim are mutually exclusive at the entry level (each entry has exactly one `cty_subco` / `rate_prov`). Shares partition imports, so the ladder magnitudes are order-invariant in the limit; small overlap effects in practice.

4. **Legal-priority objection is not load-bearing.** In the per-cell rate calculation, exemptions are applied before USMCA only because zero-rate paths short-circuit. The legal-priority story matters for the tracker code, not for the attribution ladder.

## 5. One consequence of the ordering

Because USMCA and the all-others channels (Annex II / ITA / KORUS / GSP / other_fta) are mutually exclusive at the entry level, the S2→S3 all-others rung only picks up preferences claimed on *non-USMCA-claimed* imports. For CA/MX, where USMCA captures ~89% of imports late-2025, S2→S3 is structurally small — most CA/MX preference activity already sits in the S0→S1 USMCA adjustment. S2→S3 therefore concentrates on **non-USMCA partners** (Asia, EU, ROW), which is where the ITA / Annex II / GSP signal lives anyway. USMCA adjustment is the "Mexico/Canada story"; all-others is the "everywhere-else story".

## 5a. Channels can have either sign — and that is informative

The ladder is sequential, but rung magnitudes are *not* required to be non-negative. The framework's S1→S2 trade-diversion channel routinely produces sign reversals at the country level, and the S4→T timing channel has flipped strongly negative since mid-2025.

**S1 → S2 (`gap_diversion`)**: holds rates at `rate_h2avg` (USMCA H2-2025 baseline) and varies only the import-weight composition (2024 → monthly). Sign depends on whether monthly imports concentrated in higher-tariff cells (negative; "reverse diversion") or lower-tariff cells (positive; standard diversion).

The bidirectional pattern is itself a finding: USMCA partners' exports to the U.S. are concentrated in autos / steel / energy / manufacturing — high-tariff categories with relatively inelastic short-run demand. Lower-tariff CA/MX exports (lumber, agriculture) dropped more sharply, leaving the within-country composition tilted toward higher-tariff cells. Non-USMCA partners (EU/UK/KR/JP) have more diverse baskets where consumer-goods substitution toward lower-tariff origins is feasible, so their composition shifted in the standard direction. China's contribution is dominantly *between-country* (share dropped from ~13% of imports to ~7%); ROW's between-term is large and negative (low-tariff partners gained share). See `figure_diversion_country.png` and `diversion_by_country_avg.csv` for current period means.

**S0 → S1 (`gap_adjustment`)**: holds weights at 2024 and varies USMCA from 2024 baseline (~38% CA, ~50% MX) to H2-2025 baseline (~89% CA/MX). Mostly one-signed: positive throughout the analysis window, dominated by CA and MX, ~2.4 pp window-average. Treated as backstory; the July 2025 USITC reporting change made the underlying utilization visible, but the legal entitlement was unchanged.

**S2 → S3 (`gap_others`)**: structurally non-negative. Per the delta math (R section 3g), `delta_base ≥ 0` and `delta_recip ≥ 0` always; the floor `max(0, S2 − delta)` never binds because shares are bounded by mutual exclusivity (`Σ_q s_q ≤ 1`). The all-others rung can only reduce the realized ETR, never raise it. Empirically: zero S2 < S3 cells in the cross-section.

**S3 → S4 (`gap_residual`)**: structurally positive. Census-declared duties undershoot the cell-level reconstruction by 1.4–2.6 pp window-mean across W1–W5; *not* converging in the panel. Composition: specific-duty AVE failures, AD/CVD, tracker error not yet corrected, within-cell behavioral noise.

**S4 → T (`gap_timing`)**: bidirectional. Trended strongly negative since mid-2025 (positive 2025m1–m6, negative starting around 2025m9), reaching −2.01 pp in February 2026. Cumulatively (Feb 2025–Feb 2026), Treasury has over-collected by ~$10.5B vs IMDB-declared duties (`figure_cumulative_duty_gap.png`). Plausible drivers: ACH lag catch-up, post-entry adjustments, refund reversals, FTZ-deferred duties being paid down.

**Implication for paper exposition**: report `gap_diversion` and `gap_timing` with sign preserved; don't take absolute values; don't reorder the channels to force monotonicity. Each sign-bearing channel tells a different story (composition shift direction; cash-vs-accrual catch-up), and the framework's value is in surfacing them, not hiding them.

---

## 6. Math

### 6.1 Authority decomposition

The tracker's per-cell statutory rate (HS10 product `p` × country `c` × revision `r`) decomposes additively into authority components:

$$r_{pcr} = r^{\text{base}}_{pcr} + r^{\text{recip}}_{pcr} + r^{\text{fent}}_{pcr} + r^{232}_{pcr} + r^{301}_{pcr} + r^{s122}_{pcr} + r^{s201}_{pcr}$$

| Component | Authority | Notes |
|---|---|---|
| `base` | MFN Column 1 | Specific-duty AVE included; can be 0 for ITA / Ch98 products |
| `recip` | IEEPA reciprocal | Universal baseline (9903.01.25, +10%) + Phase 1/2 country-specific (9903.01.43–.75, 9903.02.xx) + country EOs (9903.01.76–.89) |
| `fent` | IEEPA fentanyl | CA, MX, China |
| `232` | Section 232 | Steel/aluminum/copper headings + derivatives (post-April-2026 annex restructuring); auto/MHD via separate product lists |
| `301` | Section 301 | China-specific (original Trump + Biden EV/steel/cranes lists) |
| `s122` | Section 122 | Trade Act §122 universal blanket (effective 2026-02-24, expiry 2026-07-23) |
| `s201` | Section 201 | Solar safeguard, washing machines |

The `232` component carries metal-content stacking interactions that we treat as already resolved at the snapshot level (we work with post-stacking values exposed by the tracker rather than re-deriving them).

### 6.2 Preference channels and IMDB sources

For each cell `(p, c, t)` (HS10 × country × month) we observe imports declared under preference channels in IMDB. Let $s_q^{pct}$ denote the share of cell imports claiming preference $q$:

| Channel $q$ | IMDB classifier | Legal basis |
|---|---|---|
| `usmca` | `cty_subco ∈ {S, S+, CA, MX}` and `cty ∈ {1220, 2010}` | USMCA (replaces NAFTA), CA/MX origin with content rules |
| `duty_free` | `rate_prov ∈ {10, 18, 19}` and not preference-claimed above | Composite: HTS Column 1 zero (ITA / statutory MFN-zero), HTS 9903.01.32 (Annex II claim, per CBP CSMS #65829726), Ch98 (American goods returned, etc.), Berman (informational ch49/ch97) |
| `korus` | `cty_subco = "KR"` | KORUS Free Trade Agreement |
| `gsp_agoa` | `cty_subco ∈ {A, A+, A*, D, E, E*, J, J+, J*, W, Z, N}` | Generalized System of Preferences + AGOA |
| `other_fta` | `cty_subco ∈ {AU, IL, SG, CL, CO, PE, PA, JO, MA, OM, BH, P, P+, R, JP, NP}` | Bilateral FTAs |

Mutual exclusivity at the entry level: an import line carries exactly one preference claim, so

$$\sum_q s_q^{pct} \le 1, \quad q \in \{\text{usmca, duty\_free, korus, gsp\_agoa, other\_fta}\}.$$

The remainder $1 - \sum_q s_q^{pct}$ is the share of imports paying the full pre-preference statutory rate. Non-preference `rate_prov` codes (61/62/64/70 MFN-dutiable; 69/79 Ch99-dutiable; 00 FTZ) are pooled into the residual paying share.

### 6.3 Applicability matrix $\alpha_q^A$

For preference $q$ and authority $A$, $\alpha_q^A \in [0,1]$ is the fraction of authority $A$'s rate that a claim of preference $q$ exempts on the claimed entry. Per the tracker's `06_calculate_rates.R` (step 6c for non-USMCA preferences, step 7 for USMCA) and the controlling EO / CBP guidance for the `duty_free` channel:

| | `base` | `recip` | `fent` | `232` (auto/MHD)¹ | `232` (non-auto, USMCA-elig)² | `232` (non-USMCA-elig) | `301` | `s122` | `s201` |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `usmca` | 1.0 | 1.0 | 1.0 | 0.40 | 1.0 | 0.0 | 0.0 | 1.0 | 0.0 |
| `duty_free` | 1.0 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| `korus` | 1.0 | 0.0 | n/a | 0.0 | 0.0 | 0.0 | n/a | 0.0 | 0.0 |
| `gsp_agoa` | 1.0 | 0.0 | n/a | 0.0 | 0.0 | 0.0 | n/a | 0.0 | 0.0 |
| `other_fta` | 1.0 | 0.0 | n/a | 0.0 | 0.0 | 0.0 | n/a | 0.0 | 0.0 |

¹ The 0.40 for USMCA × 232 auto/MHD is the U.S. auto-content rule (`us_auto_content_share` in `policy_params.yaml`). Applied only to `rate_232`; the other components for auto/MHD products use full USMCA share.
² Only products with the tracker's `s232_usmca_eligible = TRUE` flag (set from heading-level `usmca_exempt:` config in the pre-annex regime) get USMCA scaling on `rate_232`. Other 232 products keep full `rate_232` even for CA/MX-claimed entries.

Three legal-source notes:
- The `duty_free` channel exempts `recip` because products on `ieepa_exempt_products.csv` (4,326 HTS10s, expanded to include Ch98 / ITA / Berman per Fix 4-5 in `expand_ieepa_exempt.R`) are claimed via 9903.01.32. Per EO 14326 §3 and EO 14346, Annex II coverage is preserved across Phase 2 and floor structures.
- The `duty_free` channel does **not** exempt `fent`: fentanyl IEEPA (9903.01.20–.24) is a separate authority not preempted by Annex II.
- KORUS / GSP / other-FTA preferences exempt only `base` (per tracker step 6c). The IEEPA reciprocal applies to all imports unless on Annex II — KORUS or GSP claims on their own do not exempt recip.

### 6.4 Cell-level effective rate

For each authority $A$, the effective rate at the cell level applies the share-weighted exemption:

$$r^{A,\text{eff}}_{pct} = r^A_{pcr(t)} \cdot \left(1 - \sum_q s_q^{pct} \cdot \alpha_q^A\right)$$

Total cell-level effective rate:

$$r^{\text{eff}}_{pct} = \sum_A r^A_{pcr(t)} \cdot \left(1 - \sum_q s_q^{pct} \cdot \alpha_q^A\right)$$

The factor $\left(1 - \sum_q s_q^{pct} \cdot \alpha_q^A\right)$ is the effective fraction of cell imports paying authority $A$.

### 6.5 Tier definitions in terms of share inputs

Each tier holds a different subset of preference shares fixed at zero or at chosen reference values:

| Tier | $s_{\text{usmca}}$ | $s_{\text{duty\_free}}$ | $s_{\text{korus}}$ | $s_{\text{gsp\_agoa}}$ | $s_{\text{other\_fta}}$ | weights |
|---|---|---|---|---|---|---|
| **S0** | 2024 annual | 0 | 0 | 0 | 0 | 2024 annual |
| **S1** | H2-2025 average | 0 | 0 | 0 | 0 | 2024 annual |
| **S2** | H2-2025 average | 0 | 0 | 0 | 0 | monthly $t$ |
| **S3** | H2-2025 average | monthly $t$ | monthly $t$ | monthly $t$ | monthly $t$ | monthly $t$ |
| **S4** | (Census collected: $\sum_p$ cal_dut$_p$ / $\sum_p$ con_val$_p$ at HS10 × cty, aggregated) | monthly $t$ |
| **T** | (Treasury actual: aggregate revenue / aggregate imports) | n/a |

The H2-2025 USMCA panel (`rate_h2avg`) is the framework anchor: rebuilding the tracker's authority stack with H2-2025 average claim shares (~89% CA/MX) instead of 2024 baseline (~38% CA / ~50% MX) defines a stable USMCA layer that S1 and S2 inherit. The S0→S1 step is then a pure USMCA-share adjustment at fixed weights; the S1→S2 step is a pure weight composition shift at fixed rates. This is what makes the Shapley two-way decomposition (§5–§5a) attribute the diversion channel cleanly.

### 6.6 Implementation: $S_2 \to S_3$ as authority-component subtraction

Because non-USMCA preferences exempt only a subset of authorities (mostly `base`, with `duty_free` additionally exempting `recip`), we compute $r^{S_3}$ from $r^{S_2}$ by an **additional** authority-component reduction:

$$r^{S_3}_{pct} = r^{S_2}_{pct} - \Delta^{\text{base}}_{pct} - \Delta^{\text{recip}}_{pct}$$

where:

$$\Delta^{\text{base}}_{pct} = \big( s_{\text{duty\_free}}^{pct} + s_{\text{korus}}^{pct} + s_{\text{gsp\_agoa}}^{pct} + s_{\text{other\_fta}}^{pct} \big) \cdot r^{\text{base},\text{pre}}_{pcr(t)}$$

$$\Delta^{\text{recip}}_{pct} = s_{\text{duty\_free}}^{pct} \cdot r^{\text{recip},\text{pre}}_{pcr(t)}$$

The other authorities (`fent`, `232`, `301`, `s122`, `s201`) carry no incremental reduction from $S_2$ to $S_3$.

The pre-preference component rates $r^{\text{base},\text{pre}}$ and $r^{\text{recip},\text{pre}}$ come from the tracker's top-level snapshot columns `statutory_base_rate` and `statutory_rate_ieepa_recip`. Day-weighting across revisions within a month is handled identically to existing section 3e.

### 6.7 Caveats

1. **The `duty_free` channel is composite.** Importers declaring `rate_prov 10/18/19` could be claiming any of MFN-zero, ITA, Ch98, Berman, or 9903.01.32 (Annex II). Our applicability $\alpha_{\text{duty\_free}}^{\text{recip}} = 1.0$ is correct for the Annex II / ITA / Ch98 / Berman cases (all on `ieepa_exempt_products.csv`) but slightly over-counts for pure MFN-zero products that the tracker's `base_rate` already shows as 0. In practice the over-count is small: pure MFN-zero products have $r^{\text{base}} = 0$ already, and IEEPA recip exemption requires being on the Annex II list anyway. A purist refinement would split the channel using the tracker's `is_universally_exempt` flag at the HS10 level.
2. **`other_fta` heterogeneity.** The bilateral FTAs (AU/IL/SG/CL/CO/PE/PA/etc.) have varying coverage of authorities beyond `base`. None of them have IEEPA reciprocal carve-outs in the current EOs, so $\alpha = 0$ for `recip` is correct, but content-rule interactions (e.g., Australia FTA on copper) are simplified.
3. **USMCA × 232 country exemptions.** Some 232 products have country-level exemptions (UK 25% steel/aluminum, etc.) that operate independently of USMCA shares. These are encoded in the snapshot's `rate_232` and unaffected by share-based scaling — the snapshot already reflects them.
4. **Mutual exclusivity assumption.** $\sum_q s_q^{pct} \le 1$ holds at the entry level. Aggregation to cell shares preserves this — the residual share $1 - \sum_q s_q^{pct}$ is unambiguously the "paying full rate" share. Verified in `validate_s3.do`.
5. **Section 122 expiry.** $r^{s122}$ is 0 outside the 2026-02-24 → 2026-07-23 window; no special handling needed in the share math.
6. **IEEPA SCOTUS invalidation (2026-02-24).** Post-SCOTUS, `rate_ieepa_recip = rate_ieepa_fent = 0` for all rev_4+ rows by tracker config. The $\Delta^{\text{recip}}$ term vanishes for those revisions automatically.

---

## 7. Implementation (historical)

The framework was implemented as planned (April 2026), with one structural change after a post-implementation refactor (May 2026): the S1/S2 USMCA layer was rebuilt around the H2-2025 average claim-rate panel (`rate_h2avg`), making S1 the framework anchor and renaming the S0→S1 channel to "USMCA adjustment" (was "trade diversion") and S1→S2 to "trade diversion" (was "USMCA surge"). The implemented file map is:

| Stage | File | What |
|---|---|---|
| R 3f | `code/R/00_pull_raw_data.R` | Non-USMCA preference shares from IMDB → `imdb_other_pref_shares_monthly.csv` |
| R 3g | `code/R/00_pull_raw_data.R` | Per-cell preference Δ → `counterfactual_other_pref_delta_monthly.csv` |
| Stata 02 | `code/02_counterfactual_ladder.do` | Six-tier waterfall (canonical tier values via `compute_tier`) |
| Stata 03 | `code/03_etr_analysis.do` | Decomposition figures, Shapley two-way, attribution facets |
| Stata 03b | `code/03b_baseline_figures.do` | Paper §4.1 baseline + USMCA adjustment explainer |
| Stata 04 | `code/04_fta_decomposition.do` | Preference channel decomposition |
| Validation | `scripts/validate_s3.do` | Monotonicity + share bounds + spot-checks |

The validation gate (no monotonicity violations on $S_0 \ge S_1 \ge S_2 \ge S_3$, share bounds $\sum_q s_q^{pct} \le 1$, S2→S3 magnitude consistent with the FTA decomposition channel sums) is enforced at runtime in 03 Section B.

## 8. Out of scope for the original PR (status notes)

- **Sub-channel split of S2→S3** (Annex II vs KORUS vs GSP) — data hooks exist in `imdb_other_pref_shares_monthly.csv`'s per-channel shares; per-group attribution is implemented in 03 Section B2 but the in-paper exposition keeps S2→S3 aggregated.
- **"Eligible-but-unclaimed" channel** (counterfactual against a hypothetical 100%-claim baseline) — not implemented; remains a future direction.
- **Shapley re-decomposition** for trade diversion (S1→S2) — implemented (`compute_diversion_decomp` in `code/utils/programs.do`); see §5 of `paper_outline_v2.md` for the derivation and §5a above for the sign-bearing channel discussion.
