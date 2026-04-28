# Six-tier framework plan: implementation scope + math

**Authored**: 2026-04-28
**Status**: Approved for implementation — R-side first.
**Companions**:
- `tracker_miss_report.md` — Round 3 motivates the Annex II claim-rate channel that becomes part of S3.
- `tracker_over_report.md` — companion diagnostic (over-statement direction).
- `methodology_outline.md` — paper exposition target.

---

## 1. Motivation

The current four-tier framework (T1 statutory @ 2024 weights; T2 statutory @ monthly weights; T3 Census collected; T4 Treasury) bundles the entire "exemptions" story into a single T2→T3 channel. At Feb 2026 that channel is ~6.4 percentage points (pp), and it confounds USMCA share dynamics with Annex II / ITA / Ch98 claims, KORUS / GSP / other-FTA preferences, and unmodeled residuals (specific-duty AVE failures, AD/CVD, tracker error, behavioral noise).

Step 1 of the analysis (in progress) is to correct tracker statutory ETR misses. Step 2 is to decompose the remaining gap into easily-identified USMCA and all-others channels. The six-tier framework below is the structural change that makes step 2 a clean, reusable result rather than a one-off analysis.

## 2. Tier definitions

| Tier | Definition | Source | Replaces |
|---|---|---|---|
| **S0** | Statutory @ 2024 USMCA shares × 2024 weights | tracker `usmca2024` × 2024 wts | T1 / current 05 S0 |
| **S1** | Statutory @ 2024 USMCA shares × **monthly** weights | tracker `usmca2024` × monthly imports | T2 / current 05 S1 |
| **S2** | + monthly USMCA shares applied | tracker `usmca_monthly` × monthly imports | current 05 S2 |
| **S3** | + all-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / other_fta) at monthly shares | NEW — IMDB-derived non-USMCA claim shares | (none) |
| **S4** | Census collected ETR (HS10 × cty, summed) | IMDB `cal_dut_mo` / `con_val_mo` | T3 |
| **T** | Treasury actual ETR (aggregate revenue / aggregate imports) | tariff revenue file | T4 |

## 3. Channel decomposition

| Channel | Definition | Interpretation |
|---|---|---|
| **diversion** | $S_0 - S_1$ | Composition shift in monthly weights |
| **USMCA surge** | $S_1 - S_2$ | CA/MX claim-rate dynamics (~45% → ~89% mid-2025) |
| **all-others** | $S_2 - S_3$ | Non-USMCA preference claiming: Annex II / ITA / Ch98 / KORUS / GSP / other FTAs |
| **residual** | $S_3 - S_4$ | Within-cell unmodeled effects: specific-duty AVE failures, AD/CVD, tracker error not yet corrected, behavioral noise |
| **timing** | $S_4 - T$ | Treasury vs Census aggregation, refunds, post-entry adjustments, FTZ deferral, cash-vs-accrual |

## 4. Channel-ordering rationale

The ladder is sequential, so the magnitude of each rung depends on the order in which channels are applied. The chosen order — **diversion → USMCA → all-others → residual → timing** — places USMCA *before* all-others. Justification:

1. **Data confidence ordering.** USMCA shares are sourced from USITC DataWeb's SPI program codes — authoritative, audited, in the tracker. The all-others share is reconstructed from IMDB importer-declared `rate_prov` + `cty_subco`, which is good data but involves classification choices (the 9-channel taxonomy) and edge cases (a `rate_prov = 19` could reflect Annex II, ITA, Ch98, Berman — we collapse them). Putting the higher-confidence channel earlier means measurement error in the all-others reconstruction lands on its own rung magnitude rather than contaminating the USMCA estimate.

2. **Continuity with existing 05 framing.** The current 05 ladder already places USMCA at S2. Renaming S2→S2 (no change) and *appending* all-others as a new S3 rung is conceptually additive — reads cleanly in a paper / memo and avoids forcing a reviewer to reconcile two different orderings.

3. **Headline-channel pride of place.** USMCA is the cleanest, most-documented finding (~2pp aggregate, 4–7pp for CA/MX, the ~45→89% claim-rate doubling). It deserves to be the first incremental channel after diversion.

4. **The math doesn't care.** USMCA claim and Annex II/ITA claim are *mutually exclusive* at the entry level (each entry has exactly one `cty_subco` / `rate_prov`). Shares partition imports rather than compound, so the ladder magnitudes are order-invariant in the limit and only differ by small overlap effects in practice.

5. **Legal-priority objection is not load-bearing.** In the rate calculation, exemptions are applied before USMCA only because they are zero-rate paths — and zero × anything is zero, so order is irrelevant at the entry level. The legal-priority story matters for the *tracker code*, not for the *attribution ladder*.

## 5. One consequence of the ordering

Because USMCA and Annex II are mutually exclusive at the entry level, the all-others rung (S2→S3) only picks up preferences claimed on *non-USMCA-claimed* imports. For CA/MX, where USMCA captures ~89% of imports late-2025, the all-others rung will be small — most CA/MX preference activity is already in the USMCA rung. The all-others rung therefore concentrates on **non-USMCA partners** (Asia, EU, ROW), which is where the ITA / Annex II / GSP signal lives anyway. USMCA becomes the "Mexico/Canada story", all-others becomes the "everywhere-else story".

## 5a. Channels can have either sign — and that is informative

The ladder is sequential, but rung magnitudes are *not* required to be non-negative. In fact, two of the three "rate-applying" rungs (S0→S1 and S1→S2) routinely produce sign reversals at the country level:

**S0 → S1 (`gap_diversion`)**: holds rates at the 2024 USMCA baseline and varies only the import-weight composition. Sign depends on whether monthly imports concentrated in higher-tariff cells (negative; "reverse diversion") or lower-tariff cells (positive; standard diversion). Empirically:

| Country | period-avg gap_diversion (pp) | Sign |
|---|---:|---|
| EU | +1.25 | + (standard diversion) |
| UK | +1.16 | + |
| S. Korea | +0.97 | + |
| Japan | +0.58 | + |
| China | −0.15 | − (reverse diversion) |
| ROW | −0.09 | − |
| Canada | −0.42 | − |
| Mexico | −0.81 | − |

The bidirectional pattern is itself a finding: USMCA partners' exports to the U.S. are concentrated in autos / steel / energy / manufacturing — high-tariff categories with relatively inelastic short-run demand (no quick domestic substitute, supply chains take years to relocate). Lower-tariff CA/MX exports (lumber, agriculture) dropped more sharply, leaving the within-country composition tilted toward higher-tariff cells. Non-USMCA partners (EU/UK/KR/JP) have more diverse baskets where consumer-goods substitution toward lower-tariff origins is feasible, so their composition shifted in the standard direction.

**S1 → S2 (`gap_usmca`)**: holds monthly weights and varies USMCA shares from 2024 baseline (~38% CA, ~50% MX) to monthly. Negative early-period values appear in 2025m1–m2 because monthly claim rates were *lower* than the 2024 baseline (firms hadn't yet learned to claim under the new tariff regime). The mid-2025 ramp to ~85–89% then dominates the period average and produces the canonical USMCA-surge story.

**S2 → S3 (`gap_others`)**: structurally non-negative. Per the delta math (R section 3g), `delta_base ≥ 0` and `delta_recip ≥ 0` always; the floor `max(0, S2 − delta)` never binds because shares are bounded by mutual exclusivity (`Σ_q s_q ≤ 1`). The all-others rung can only reduce the realized ETR, never raise it. Empirically: zero S2 < S3 cells in the cross-section.

**Implication for paper exposition**: report `gap_diversion` and `gap_usmca` with sign preserved. Don't take absolute values; don't reorder the channels to force monotonicity. Each sign-bearing channel tells a different story (composition shift direction; firm response lag), and the framework's value is in surfacing them, not hiding them.

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
| **S1** | 2024 annual | 0 | 0 | 0 | 0 | monthly $t$ |
| **S2** | monthly $t$ | 0 | 0 | 0 | 0 | monthly $t$ |
| **S3** | monthly $t$ | monthly $t$ | monthly $t$ | monthly $t$ | monthly $t$ | monthly $t$ |
| **S4** | (Census collected: $\sum_p$ cal_dut$_p$ / $\sum_p$ con_val$_p$ at HS10 × cty, aggregated) | monthly $t$ |
| **T** | (Treasury actual: aggregate revenue / aggregate imports) | n/a |

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

## 7. Implementation scope

### 7.1 R-side: `code/R/00_pull_raw_data.R` (~150 lines new)

**Section 3f — Non-USMCA preference shares from IMDB**
- Input: `data/raw/imdb_detail.csv` (already pulled in section 2).
- Port the `classify_pref_channel` taxonomy from Stata (`code/utils/programs.do`) to an R function. Same 9 channels.
- Aggregate by (hs10, cty_code, ym) → per cell compute `share_duty_free`, `share_korus`, `share_other_fta`, `share_gsp_agoa`, plus the combined `non_usmca_pref_share`.
- Output: `data/raw/imdb_other_pref_shares_monthly.csv`.

**Section 3g — Combined-preference counterfactual rate file**
- Inputs: `counterfactual_usmca_monthly.csv` (3e output), `imdb_other_pref_shares_monthly.csv` (3f output), top-level snapshots (with `statutory_base_rate` and `statutory_rate_ieepa_recip`).
- Day-weight pre-preference base + recip components to monthly using the same `mrw` table 3e builds.
- Compute per cell: `rate_S3 = rate_S2 − (other_pref_total × base_rate) − (duty_free_share × recip_rate)`.
- Output: `data/raw/counterfactual_all_pref_monthly.csv`.

**CLI flags**
- Update `--only-counterfactual` to include 3f/3g (already does sections 3d-3e).
- Add `--skip-other-pref` for opt-out (default: include).

### 7.2 Stata-side: `code/05_counterfactual_ladder.do` (~50 lines)

- Section A: load new `counterfactual_all_pref_monthly.csv` alongside existing files.
- Section B: add one `compute_tier` call for S3.
- Section C: extend the combine block. New columns: `s3`, `gap_others = s2 − s3`, `gap_residual = s3 − s4`, `gap_timing = s4 − treasury`. Total: `gap_total = gap_diversion + gap_usmca + gap_others + gap_residual + gap_timing`.
- Section D: country-level ladder gets the same S3 column.

### 7.3 Stata-side: `code/02_etr_analysis.do` (~150–200 lines)

- Section A: rename T1→S0, T2→S1, T3→S4, T4→T. Add new computations for S2, S3.
- Section C: existing 4-tier line chart becomes 6-tier. Optional new waterfall figure.
- Sections D, G: comparison tables and Excel summary updated.

### 7.4 Validation script — `scripts/validate_s3.do` (NEW, ~80 lines)

- **Monotonicity**: $S_0 \ge S_1 \ge S_2 \ge S_3 \ge S_4$ in every month and partner group.
- **Cross-check vs 03**: at each month, the S2→S3 magnitude should approximately equal `gap_contrib_pp` summed over `{duty_free, korus, other_fta, gsp_agoa}` from `fta_decomp_monthly.csv`. Within ~10% relative.
- **Share bounds**: any cell where $\sum_q s_q^{pct} > 1$ is reported. Should be zero by construction; non-zero indicates classifier bug.
- **Spot-check**: HS10 8471.50.01.50 from Taiwan (`5830`) should show `share_duty_free ≥ 0.95` in every month.

### 7.5 Documentation

- `CLAUDE.md`: update pipeline description from four-tier to six-tier.
- `docs/methodology_outline.md`: extend with new framework definition.
- README: minor edits.

## 8. Sequence

```
Day 1 morning:
  1. Port classify_pref_channel to R (helpers in 00_pull_raw_data.R).
  2. Write section 3f: aggregate IMDB to (hs10, cty, ym) shares.
  3. Run 3f standalone, validate output (~5 min run, ~50 MB CSV).

Day 1 afternoon:
  4. Write section 3g: combined counterfactual rate.
  5. Run 3e + 3g end-to-end (~20 min, two counterfactual CSVs).
  6. Spot-check HS10 8471.50.01.50 cells against expected values.

Day 2 morning:
  7. Update 05 counterfactual ladder.
  8. Run 05 alone (~3 min), inspect counterfactual_ladder.csv.
  9. Write validate_s3.do, run it, fix any issues surfaced.

Day 2 afternoon:
 10. Update 02 etr_analysis (rename tiers, add S2/S3 columns, update figures).
 11. Run 02 alone (~10 min).
 12. Update CLAUDE.md, methodology doc.
 13. Full pipeline re-run end-to-end (`do 00_etr_eval.do`, ~45 min).
 14. Compare new figures vs old; sanity-check headline numbers.
```

## 9. Validation gate (must pass before merging)

- `validate_s3.do` reports zero monotonicity violations.
- S2→S3 channel cross-check vs 03 matches within 10% relative.
- Aggregate ETR identity holds: $S_0 - T = $ sum of all gap channels to numerical precision.
- Spot-check: HS10 8471.50.01.50 from Taiwan shows `share_duty_free ≥ 0.95` in all months.
- Existing tests in 04, 05a, 05b, 06 all still pass.

## 10. Out of scope for this PR

- **Sub-channel split of S2→S3** (Annex II vs KORUS vs GSP). Data hooks exist in 3f's output (per-channel shares) but the ladder UI / figures stay aggregated.
- **"Eligible-but-unclaimed" channel** (the importer-non-claim story from `tracker_miss_report.md` Round 3). That's a separate counterfactual against a hypothetical 100%-claim baseline.
- **Shapley re-decomposition** to remove order dependence. Current ordering is interpretable and defensible; Shapley is a robustness check we can bolt on later if reviewers push back.

## 11. Risks

- **Classifier portability**: the Stata `classify_pref_channel` and the R port must stay in sync. Mitigation: write the R version with the same docstring; validate against a small shared fixture.
- **R/Stata pipeline wall-clock**: 3f processes the 895 MB `imdb_detail.csv`. Should complete in ~5 min based on existing 03 patterns. 3g is light (~50 MB joins).
- **Memory**: 3g joins `counterfactual_usmca_monthly.csv` (~1.3 GB after expansion) with monthly-aggregated base/recip components. May require streaming if it OOMs on the work machine.
