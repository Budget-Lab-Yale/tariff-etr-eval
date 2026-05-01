# Paper Outline (v2): Decomposing the Statutory–Actual Tariff Rate Divergence

**Working title**: Decomposing the Statutory–Actual Tariff Rate Divergence: A Five-Channel Framework for the 2025–2026 U.S. Tariff Episode

**Authors**: Abhi Gupta, John Iselin, John Ricco (The Budget Lab at Yale)

**Status**: Draft outline post-framework-restructure (April 2026). Supersedes `archive/paper_outline.md` (which used the older T1/T2/T3/T4 four-tier nomenclature).

**Companion documents**:
- `etr_divergence_slides.tex` — 10-minute presentation, same structure, less detail
- `etr-literature-review.md` — full citation library (lift inline references from there)
- `six_tier_framework_plan.md` — framework math derivation (Shapley two-way, applicability matrix, sign-bearing channel discussion). Tier definitions kept in sync with `CLAUDE.md`.

---

## 0. Front matter

- Title, authors, affiliations
- Abstract (~150 words):
  - Document the gap (S1 = 15.07% Dec 2025, 14.06% Feb 2026; T = 9.88% / 10.49%; framework gap S1−T = 5.19 pp / 3.57 pp)
  - Five-channel decomposition: USMCA adjustment, trade diversion, all-other preferences, residual, timing
  - S1 (post-USMCA-stabilization) as the analytic anchor — aligns with paper's headline figure by construction
  - Reproduce Eck, Hoang, Mix, Ray (2026) Dec-2025 numbers within ~0.6 pp via independent methodology (S1 = 15.07 vs 14.7; T = 9.88 vs 9.27 implied; total gap = 5.19 vs 5.43)
  - Per-country, per-product attribution at every channel except S4→T; period-mean diversion contributions reveal China carries 90%+ of the trade-diversion gap; Steel/Aluminum, Autos, and Other Manufactured dominate the product-side decomposition
- Keywords: tariffs, trade policy, effective tariff rate, USMCA, Section 232, Section 301, Section 122, IEEPA
- JEL: F1, F3

---

## 1. Introduction

- **Hook**: The 2025–2026 U.S. tariff escalation produced post-stabilization statutory rates of **15.07% in December 2025 and 14.06% in February 2026** (S1 in our framework, equivalently the tracker's daily ETR collapsed monthly); Treasury-collected duties yield a realized rate of **9.88% in December 2025 and 10.49% in February 2026**. The post-USMCA-stabilization gap is **5.19 pp in December 2025 and 3.57 pp in February 2026** — narrower than the headline statutory-vs-actual numbers cited in the broader literature [Gopinath & Neiman, 2026, ~27% statutory peak / ~10–11% actual] because we treat the USMCA claim-rate ramp as backstory rather than as part of the headline gap. The full ladder gap (S0−T, including the USMCA backstory) reaches **7.84 pp in December 2025 and 6.07 pp in February 2026**.
- **Three motivating questions**:
  1. How big is the gap, and how has it evolved month-by-month?
  2. What channels explain it: USMCA claim-rate dynamics, supply-chain composition shifts, statutory exemptions, or implementation/timing/enforcement?
  3. Where does the gap concentrate — which partner countries and which product groups carry it, and which channels dominate where?
- **Contribution**:
  - First **five-channel ladder** that cleanly separates USMCA claim-rate normalization from the policy-relevant trade-diversion signal. Existing decompositions [Azzimonti, 2025; Eck et al., 2026] bundle these.
  - Direct, transparent reconstruction of statutory rates from the HTS + Chapter 99 authorities (via the `tariff-rate-tracker` pipeline) using day-weighted monthly panels — captures mid-month policy events (e.g. Liberation Day, April 2 2025) that revision-snapshot lookups miss.
  - Shapley two-way decomposition of trade diversion at every partition (country, product), so the same numbers are decomposable along orthogonal cuts. Sums match the ladder identity within numerical noise.
  - Per-country and per-product attribution at four channels (USMCA adjustment, diversion, other preferences, residual). Treasury timing remains aggregate-only, by construction.
  - Cross-validation: our independent methodology reproduces Eck et al. (2026) FEDS Notes "Mind the Gap" December-2025 numbers within ~0.6 pp on every comparable quantity, despite different decomposition mechanics (Laspeyres-style vs. Shapley two-way).
- **Roadmap paragraph**.

---

## 2. The 2025–2026 tariff episode (compressed policy context)

### 2.1 Authorities active in 2025–2026

- **IEEPA reciprocal tariffs**: Phase 1 (April 2025), Phase 2 (August 2025), country-specific EOs.
- **IEEPA fentanyl tariffs**: 25% MX, 35% CA (raised from 25% mid-2025), 10% China — with carve-outs (energy, minerals, potash) for CA/MX.
- **Section 232**: steel/aluminum/copper (50%, June 2025); autos (March 2025); MHD vehicles (June 2025); annex restructuring (April 2026).
- **Section 301**: pre-existing China lists 1–4 (carrying ~$200B in covered imports), Biden-era 2024 expansions on EVs/batteries/semiconductors.
- **Section 122**: 10% blanket, post-SCOTUS ruling (Feb 24, 2026), 150-day expiry July 23, 2026.
- **Section 201**: residual safeguards.
- Authority stacking conventions [tracker `06_calculate_rates.R`]; per-country exemptions (CA/MX/EU/UK/JP/KR/AU/BR/AR/UA pre-March 2025; Russia 200% permanent).

### 2.2 USMCA mechanics

- Claim rates: ~38% CA / ~50% MX in 2024 → ~89% by H2 2025 [PWBM, 2025–26; USITC DataWeb].
- Claim-rate visibility shifted in **July 2025** when USITC reporting changed; pre-July claim rates were depressed both by genuine non-claiming and by reporting lag.
- Auto/MHD parts exemption uses 0.40 US-content rule [tracker §7].

### 2.3 Concentration profile

- HHI ≈ 0.06 [Eck et al., 2026] — far broader than 2018–2019 (HHI ≈ 0.29, China-dominant).
- Implication: any single-channel decomposition will miss most of the action; multi-channel framework is necessary.

---

## 3. Literature: existing decompositions of the gap

### 3.1 Anchor papers

- **Gopinath & Neiman (2026, NBER w34620)** "The Incidence of Tariffs":
  - Documents ~27% trade-weighted statutory vs ~10–11% actual, September 2025.
  - Pass-through on *collected* duties is near-100% (94% in 2025 vs 80% in 2018–2019).
  - Implication: the gap is what shields prices, not under-implementation; understanding the gap is the welfare question.
  - Channels cited: shipping lags, exemptions, FTA utilization, enforcement.

- **Azzimonti (2025, Richmond Fed Economic Brief No. 25-29)** "Why Predicted and Actual Tariff Rates Diverged in May 2025":
  - May 2025 predicted AETR 17.5%; actual 8.7%; gap 8.8 pp.
  - Three-channel decomposition: within-country product mix (0.6 pp), cross-country share shifts (2.7 pp), implementation frictions (5.5 pp).
  - Canada case: 31% of CA product lines with positive predicted tariff generated zero duty; electronics 19 pp gap, electrical equipment 10 pp, machinery 7 pp.

- **Eck, Hoang, Mix, Ray (2026, FEDS Notes April 2026)** "Mind the Gap":
  - **Direct comparator**: same conceptual frame (announced vs realized; compositions vs rate discrepancies).
  - Dec 2025: announced ETR 14.7%; realized fell short by 5.43 pp ($\approx$44% of the announced increase).
  - 2018–19 comparison: gap was 0.44 pp ($\approx$22% of announced) — current episode's *fraction* is double, despite broader concentration.
  - Methodology: Laspeyres baseline weights; composition channel + rate-discrepancy channel.

- **PWBM (2025–26)** "Effective Tariff Rates and Revenues":
  - Tracks T_4 monthly; mechanical-vs-behavioral split; through Jan 2026 about $209B raised, $46B lost to behavior.
  - PWBM USMCA series: 33–38% (2024) → 88% (Dec 2025).

- **Yale Budget Lab (2025–26)** tracking series:
  - Pre/post-substitution distinction; MFN-zero pickups (CA −6 pp / MX −3 pp methodology revision).
  - Companion to this paper at TBL.

### 3.2 Methodological complements

- **Waugh (2026, Minneapolis Fed Staff Report 681)** Trade Restrictiveness Index:
  - Welfare-equivalent uniform rate ~21–23% (Oct/Nov 2025).
  - Implication: dispersion roughly doubles the welfare cost vs the duties-to-imports ratio.
- **Cavallo, Llamas, Vazquez (2025, NBER w34496)** "Tracking the Short-Run Price Impact":
  - 20% retail pass-through after six months; 0.7 pp CPI contribution.
  - Underscores that the gap is what determines the consumer-price effect.
- **Cavallo, Gopinath, Neiman, Tang (2021)** AER:I: 2018–19 border pass-through evidence.
- **Flaaen, Hortaçsu, Tintelnot, Urdaneta, Xu (2025, BFI WP 2025-137)**: tariff engineering case studies.
- **Cui, Feng, Lu, Tomlin (2025, SSRN 5110124)**: firm strategy framework — mitigation (stockpiling, sourcing) vs contingency (responsive pricing).

### 3.3 Historical perspective

- **Gerlach (EFG International, 2025)**: 150-year ETR series; current 10–12% is highest in a century but well below 19th-century norms (~50%).

### 3.4 Where this paper fits

- Existing work decomposes piecewise: each paper opens one or two channels.
- Our framework provides a **single unified ladder** that covers all of: USMCA claim-rate evolution, cross-country composition, within-country product mix, non-USMCA exemptions, residual collection gaps, and Treasury timing.
- Cross-validation against Eck et al. (2026) at Dec 2025 (within ~0.6 pp on S1, T, total gap, and channel split) provides independent check on the methodology.

---

## 4. Framework

### 4.1 The five-channel ladder

- Tier definitions (per-cell rates, aggregated by value-weighted average over HS10 × country cells):

| Tier | Rate panel | Weight | USMCA layer |
|------|------------|--------|-------------|
| S0 | `rate_2024` | `imports` (2024) | 2024 baseline (~38% CA / ~50% MX) |
| S1 | `rate_h2avg` | `imports` (2024) | H2-2025 baseline (~89% CA/MX) |
| S2 | `rate_h2avg` | `con_val_mo` | H2-2025 baseline |
| S3 | `rate_all_pref` | `con_val_mo` | H2-2025 minus non-USMCA preference Δ |
| S4 | Census collected (cal_dut / con_val) | — | — |
| T | Treasury actual | — | — |

- **Channels** (sequential):
  - S0 → S1: **USMCA adjustment** — claim-rate normalization 2024 → H2-2025 with weights frozen. Mostly retrospective; the data show it primarily because of the July 2025 USITC reporting change. Treated as backstory in the paper, not as a co-equal analytical channel.
  - S1 → S2: **Trade diversion** — composition shift in monthly weights with USMCA stable at H2-2025. Main analysis channel.
  - S2 → S3: **All-other preferences** — Annex II / ITA / Ch98 (Berman Amendment) / generic pharma / KORUS / GSP-AGOA / other bilateral FTAs.
  - S3 → S4: **Residual** — gap between statutory-with-all-preferences and Census-collected duties at the cell level. Captures specific-duty AVE failures, AD/CVD, tracker error, behavioral noise.
  - S4 → T: **Timing/enforcement** — Treasury vs Census aggregation. Refunds, post-entry adjustments, FTZ deferrals, cash-vs-accrual.

### 4.2 Why S1 is the framework anchor

- S1 = `rate_h2avg × imports (2024)` is identically the tracker's daily ETR collapsed to monthly by construction.
- This is the line that anchors the paper's headline figure (§5 below) and TBL's public-facing "State of U.S. Tariffs" tracking.
- Absorbing USMCA upfront (S0→S1) treats the 2024-to-H2-2025 claim-rate ramp as explainable backstory, not a co-equal analytical channel. Most of the paper's exposition lives between S1 and T.

### 4.3 Mapping to existing decompositions

| Our channel | Azzimonti (2025) | Eck et al. (2026) |
|---|---|---|
| S0 → S1 USMCA adjustment | Pre-period — not directly addressed | Subset of "rate discrepancies" |
| S1 → S2 between-country | Cross-country share shifts (2.7 pp May) | "Composition": cross-country |
| S1 → S2 within-country | Within-country product mix (0.6 pp May) | "Composition": product reclassification / engineering |
| S2 → S3 other preferences | Part of "frictions" (5.5 pp May) | Part of "rate discrepancies" |
| S3 → T residual + timing | Remainder of "frictions" | Residual rate discrepancies |

- Discussion: our framework's contributions vs. these are (i) cleanly separating USMCA from cross-country composition, (ii) handling non-USMCA preferences as a distinct rung, (iii) Shapley-clean partition of trade diversion that the literature handles ad hoc.

---

## 5. Methodology

### 5.1 Per-cell rate construction (`tariff-rate-tracker`)

- Rate panel built per (HS10 × country × revision) by `06_calculate_rates.R` with five layers:
  1. Authority components from HTSUS / Ch99 parsing: `rate_232`, `rate_ieepa_recip`, `rate_fent`, `rate_301`, `rate_s122`, `rate_other`, base MFN.
  2. Metal-content scaling for S232: `rate_232 × metal_share` per type (steel / aluminum / copper); IEEPA recip and S122 apply to (1 − metal_share).
  3. Authority stacking by country: China-with-232 = 232 + recip×nonmetal + fent + 301 + s122×nonmetal; CA/MX-with-232 = 232 + (recip + fent + s122)×nonmetal; without-232 = all authorities full.
  4. USMCA scaling by claim share. Auto/MHD parts use 0.40 US-content rule.
  5. MFN exemption shares (HS2 × country, ~4,695 pairs from Tariff-ETRs); IEEPA floor adjustments (10% min for EU/JP/KR/CH).

### 5.2 Day-weighted monthly aggregation

- Per (HS10 × country × revision) rates are aggregated to monthly by **day-weighting across HTS revisions active within each month**.
- Critical for capturing mid-month policy changes (Liberation Day Apr 2 2025, Phase 2 Aug 7 2025, SCOTUS Feb 24 2026, S232 annex restructure Apr 6 2026).
- Same machinery (`build_counterfactual()` in R `00_pull_raw_data.R` §3e) produces all four rate panels (rate_2024, rate_h2avg, rate_usmca_monthly, rate_all_pref); they differ only in the USMCA layer.

### 5.3 Aggregate ETR formula

**Symbols** (cell level). Index $i$ runs over (HS10 × country) cells in a given month $t$:

- $r_i$: cell-level statutory tariff rate (a fraction). Concretely, one of the four rate panels — `rate_2024`, `rate_h2avg`, `rate_usmca_monthly`, `rate_all_pref` — depending on which tier we are computing.
- $w_i$: cell-level value weight in dollars. Concretely either `imports` (2024 annual weight) or `con_val_mo` (monthly weight) depending on tier.

**Aggregate ETR.** For a given (rate panel, weight panel) pair the aggregate effective tariff rate is the value-weighted average across cells:

$$
S = \frac{\sum_i w_i \, r_i}{\sum_i w_i}.
$$

Writing this out for a particular tier and month $t$:

$$
S^{\text{tier}}_t = \frac{\sum_i r^{\text{tier}}_{i,t} \cdot w^{\text{tier}}_{i,t}}{\sum_i w^{\text{tier}}_{i,t}}.
$$

For example, **S2** uses $r_i = $ `rate_h2avg`$_i$ and $w_i = $ `con_val_mo`$_i$ at month $t$.

**Symbols** (group level). For any partition $g \in \{1, \ldots, G\}$ of cells (e.g. 8 partner groups or 9 product groups), define group-level rate and group-level share:

- $R_g$: group $g$'s value-weighted average rate,
$$
R_g = \frac{\sum_{i \in g} w_i r_i}{\sum_{i \in g} w_i}.
$$
- $s_g$: group $g$'s share of total weight,
$$
s_g = \frac{\sum_{i \in g} w_i}{\sum_i w_i}, \qquad \sum_g s_g = 1.
$$

**Partition identity.** The aggregate ETR equals the share-weighted average of group-level rates:

$$
S = \sum_g s_g \, R_g.
$$

This is the algebraic foundation for the Shapley decomposition in §5.4: at any given month, $S$ is a linear function of $G$ shares and $G$ rates.

**Methodology choices**:

- Single-stage row-level value-weighted average. No HS2 bridging.
- Zero-tariff products **must be in the denominator** [`docs/weighting_note.md`]. Dropping them inflates the ETR from ~3.4% to ~27%.
- All rate panels are day-weighted across HTS revisions within each month (R `00_pull_raw_data.R` §3e), so $r^{\text{tier}}_{i,t}$ is a smooth monthly object even when the underlying revision schedule changes mid-month.

### 5.4 Shapley two-way decomposition (S1 → S2 trade diversion)

**Setup.** For any pair of tiers that share a rate panel but differ in weights (or vice versa), define two periods indexed by superscripts $0$ and $1$:

- For trade diversion (S1 → S2): rate panel held at `rate_h2avg`; period $0$ = 2024 weights ($w^0_i = $ `imports`$_i$), period $1$ = monthly weights ($w^1_i = $ `con_val_mo`$_i$ at month $t$).

The aggregate ETR in each period is:

$$
S^k = \sum_g s^k_g \, R^k_g \qquad (k = 0, 1),
$$

where $s^k_g$ and $R^k_g$ are group $g$'s share and rate computed using the period-$k$ weights, exactly as defined in §5.3.

**Trade-diversion gap.** The framework defines $\text{gap}_{\text{diversion}} = S^1_{\text{frame}} - S^2_{\text{frame}} = S^0 - S^1$ in the superscript notation here. (The "0" / "1" labeling reflects the two periods entering the decomposition; "S1" / "S2" labels the two framework tiers being compared.)

**The Shapley two-way decomposition**. Decompose $\Delta S = S^0 - S^1$ into a between-group term (shifts in shares $s_g$) and a within-group term (shifts in rates $R_g$). Symmetric Shapley two-way (averaging the two orderings of share-then-rate vs rate-then-share):

$$
\Delta S = \underbrace{\sum_g \tfrac{1}{2}(R^0_g + R^1_g)(s^0_g - s^1_g)}_{\text{between-group: composition shift}} + \underbrace{\sum_g \tfrac{1}{2}(s^0_g + s^1_g)(R^0_g - R^1_g)}_{\text{within-group: rate shift inside group}}.
$$

**Reading the terms** (for the country lens, $g$ = partner_group):

- **Between-country.** $(s^0_g - s^1_g) > 0$ means group $g$ lost share from period 0 to period 1. Multiplied by the average of group $g$'s two rates. Captures composition: how much of the gap comes from "imports shifted away from country $g$ toward other countries". Positive when high-rate countries lose share or low-rate countries gain share.
- **Within-country.** $(R^0_g - R^1_g) > 0$ means group $g$'s within-group product mix shifted to less-tariffed cells. Multiplied by the average of group $g$'s two shares. Captures rate change inside each group at fixed across-group composition.

**Trade diversion is purely composition-driven.** For S1 → S2 the rate panel is fixed (`rate_h2avg` in both periods). Therefore the within-group term involves $R^0_g - R^1_g$ which arises only from the within-group product mix changing — i.e., the same `rate_h2avg` rates re-weighted by changing within-group import shares. The between-group term arises from the across-group share of total imports changing.

For S0 → S1 (USMCA adjustment) the situation is the opposite: weights are fixed and rates change. The between-group term is mechanically zero (no share movement at fixed weights). The within-group term collapses to a per-group dollar attribution — see §5.5.

**Sign convention.** Positive contribution by group $g$ = positive contribution to $\Delta S$ = positive contribution to gap_diversion = (S1 − S2) > 0. Negative contributions ("reverse diversion") arise when a high-tariff group gains share (e.g., a hypothetical China-share-rises scenario) or a low-tariff group loses share. In our 2025–2026 data, ROW shows persistent negative between-country contribution because low-tariff partners (Vietnam, India, etc.) gained share.

**Both partitions sum to the same $\Delta S$** at every month — the country and product lenses are complementary, not mutually exclusive. We compute both. The Shapley sum identity is asserted at runtime in `03_etr_analysis.do` Section B (validates both lenses against `gap_diversion` from `counterfactual_ladder.dta` to within numerical noise, default tolerance $10^{-3}$ pp).

### 5.5 Per-group attribution (S2 → S3, S3 → S4)

- When weights are fixed across the two periods (S2 → S3: rate panel changes, weights stay at `con_val_mo`), the Shapley between-term is mechanically zero. Per-group attribution simplifies:

$$\text{contribution}_g = \frac{\sum_{i \in g}(r^{\text{left}}_i - r^{\text{right}}_i) \cdot w_i}{\sum_i w_i}$$

- Implemented as `compute_per_group_attribution` in `programs.do`.
- Same form for S3 → S4 with the right-hand "rate" being row-level Census ETR (`cal_dut_mo / con_val_mo`).

### 5.6 What we do not decompose

- **S4 → T (timing)**: Treasury revenue is reported in aggregate; no partner or product breakout. Per-group attribution is therefore impossible. The aggregate-level gap is reported in the ladder; in the per-group attribution figures (F2, F3) timing appears as an unattributed residual.

### 5.7 Independent validation against Eck et al. (2026)

| Quantity | Our framework (Dec 2025) | Eck et al. (2026) | Δ |
|---|---:|---:|---:|
| Statutory ETR (S1) | 15.07% | 14.7% | +0.37 pp |
| Realized ETR (T) | 9.88% | 9.27% (implied) | +0.61 pp |
| Total gap (S1 − T) | 5.19 pp | 5.43 pp | −0.24 pp |
| Composition channel | 2.22 pp (gap_diversion) | within their "composition" range | within methodology variance |
| Rate-discrepancy channel | 2.97 pp (others + residual) | within their "rate discrepancies" range | within methodology variance |

Cross-validation: independent methodology, same numbers within ~0.6 pp on every comparable quantity at December 2025.

**Series-wide consistency** (full month-by-month panel, S1 vs T):

| Month | S1 (%) | T (%) | S1 − T (pp) |
|---|---:|---:|---:|
| 2025m1 | 3.19 | 2.31 | 0.88 |
| 2025m2 | 6.21 | 2.51 | 3.69 |
| 2025m3 | 6.82 | 2.38 | 4.44 |
| 2025m4 | 14.48 | 5.66 | 8.81 |
| 2025m5 | 13.80 | 8.02 | 5.77 |
| 2025m6 | 14.55 | 10.03 | 4.52 |
| 2025m7 | 14.83 | 9.47 | 5.36 |
| 2025m8 | 16.46 | 11.22 | 5.24 |
| 2025m9 | 16.83 | 10.73 | 6.10 |
| 2025m10 | 16.02 | 11.40 | 4.62 |
| 2025m11 | 15.24 | 11.79 | 3.44 |
| 2025m12 | 15.07 | 9.88 | 5.19 |
| 2026m1 | 15.10 | 10.65 | 4.46 |
| 2026m2 | 14.06 | 10.49 | 3.57 |

Spot-checks against other tracking series:
- **PWBM** (Jan 2026): 10.3% effective rate; our T = 10.65% (Δ = +0.35 pp) -- matches
- **Yale Budget Lab** (Aug 2025): ~11.5% actual / 15.7–18.2% statutory range; our T = 11.22% / S1 = 16.46% -- within range
- **Gopinath & Neiman** (Sept 2025): 27% statutory cited; our S0 = 19.57%, S1 = 16.83%. Their 27% is higher because it appears to be a pre-substitution / pre-USMCA-stabilization upper bound. Our T = 10.73% matches their realized (10–11%).

---

## 6. Data

- **Census IMDB bulk** (HS10 × country × district × preference × rate provision × month): primary monthly trade source; pulled via R `00_pull_raw_data.R` §2.
- **USITC DataWeb** (USMCA S/S+ program codes): source of USMCA claim-rate panels (2024 baseline, H2-2025 average, monthly empirical).
- **Tariff Rate Tracker** (sibling repo `tariff-rate-tracker`): HTS10 × country statutory rates per revision; daily ETR; 2024 import weights; revision-date metadata.
- **Tariff Impact Tracker** (sibling repo `tariff-impact-tracker`): Treasury customs duties / monthly imports = T.
- **Window**: January 2025 – February 2026 (inclusive). Carry-forward used for 2026-Feb USMCA shares (DataWeb release lag).

---

## 7. Headline gap (figs 1–3)

### 7.1 The puzzle (Fig 1: figure_baseline)

- Two-line monthly time series: S1 (statutory at H2-2025 USMCA × 2024 weights) and T (Treasury actual).
- Headline numbers (most recent month, Feb 2026): **S1 = 14.06%**, **T = 10.49%**, **gap = 3.57 pp**.
- Trajectory: S1 jumps from 6.82 (March 2025) to 14.48 (April 2025, post-Liberation Day) → 16.83 (September 2025, peak) → 14.06 (February 2026, post-SCOTUS / Phase 3 partial unwind).
- T trajectory: 2.38 (March 2025) → 5.66 (April 2025) → 11.40 (October 2025, peak) → 10.49 (February 2026).
- Policy event markers: Liberation Day (Apr 2 2025), Phase 2 (Aug 7 2025), SCOTUS / Phase 3 (Feb 24 2026).
- Per-month gap (S1 − T) ranges 3.4–8.8 pp; average ~4.95 pp over the analysis window.

### 7.2 The full ladder (Fig 2: figure_ladder)

- Five lines: S0 (gray dashed; backstory), S1 (navy solid; framework anchor), S2, S3, T.
- S0 → S1 step is the USMCA adjustment; visible as a constant or near-constant offset because both use 2024 weights.
- S1 line equals figure_baseline's statutory line by construction.

### 7.3 Channel decomposition (Fig 3 / figure_channel_stacked)

- Stacked monthly bars: trade diversion + all-other preferences + residual+timing.
- Gap_total = gap_adjustment + gap_diversion + gap_others + gap_residual + gap_timing — additive identity.
- For comparison to Eck et al. (2026), the two-channel collapse (composition + rate-discrepancy) is the appendix figure.

---

## 8. USMCA adjustment (S0 → S1) — backstory

### 8.1 Visualizing the claim-rate evolution (Fig U1: figure_adjustment_explainer)

- Two-panel facet (CA, MX), three lines per panel:
  - 2024 USMCA baseline (purple, dashed): the rate the schedule would have produced if claim rates stayed at 2024 levels.
  - Empirical monthly (red, solid): the rate produced by the actual monthly claim share each month.
  - H2-2025 USMCA baseline (navy, dashed): the rate the schedule produces at H2-2025 average claim shares.
- Empirical line transitions from near the 2024 baseline (early 2025) toward the H2-2025 baseline (post-July 2025) — the July 2025 USITC reporting-change inflection is visible.

### 8.2 Per-country attribution (Fig U2: figure_adjustment_country)

- Period-averaged S0 − S1 gap per partner group (horizontal bar chart, sorted).
- CA and MX dominate; everyone else is essentially zero (USMCA only applies to those two).

### 8.3 Discussion

- The S0 → S1 step is "explainable backstory" — paperwork caught up after July 2025; the underlying preference structure didn't change.
- Distinguishing this from the policy-relevant channels (S1 → T) is what motivates the framework restructure.

---

## 9. Trade diversion (S1 → S2) — main analysis

### 9.1 Aggregate decomposition (Fig D1: figure_diversion_decomp)

- Stacked monthly bar: between-country (share shifts) + within-country (product mix inside each country) = total S1 − S2.
- Between+within sum to total by Shapley construction; the bars visually demonstrate the additive identity.
- Sign-bearing: between-country can flip negative ("reverse diversion" for CA/MX whose imports concentrate in inelastic high-tariff categories).

### 9.2 Country lens (Fig D2: figure_diversion_country)

- Stacked monthly contributions per partner group.
- **Period-mean contributions to S1−S2 (pp; from `diversion_by_country_avg.csv`)**:
  - China: **+2.13** (between +2.07, within +0.06) — overwhelmingly between-country (share dropped from ~13% of imports to ~7%).
  - Canada: +0.18 (between +0.10, within +0.08)
  - EU: +0.11 (between +0.02, within +0.09)
  - S. Korea: +0.09 (between +0.02, within +0.06)
  - Japan: +0.09 (between +0.05, within +0.04)
  - Mexico: +0.08 (between −0.02, within +0.10) — within dominates; product mix shifting toward lower-tariff lines
  - UK: +0.03
  - **ROW: −0.47** (between −0.77, within +0.30) — ROW share *rose* (low-tariff partners gaining), so its between contribution is negative
- China alone accounts for 90%+ of the between-country trade-diversion effect. The headline "trade diversion" story is overwhelmingly a China-share-dropped story.
- ROW's negative bar is the mirror image: trade reallocated *to* ROW (Vietnam, India, etc.).

### 9.3 Product lens (Fig D3: figure_diversion_product)

- 9-group taxonomy aligned with policy salience: S232 metals, autos, electronics, pharma, energy, chemicals, apparel, food, other.
- **Period-mean contributions to S1−S2 (pp; from `diversion_by_product_avg.csv`)**:
  - **Autos & Auto Parts**: +0.59 (between +0.56, within +0.03) — between dominates (auto imports compressed under S232 autos at 25%).
  - **Other Manufactured**: +0.49 (between −0.39, within +0.88) — within dominates: composition shifts inside this catchall group toward lower-tariff lines.
  - **Electronics & Machinery**: +0.34 (between −0.42, within +0.76) — share *rose* as Annex II electronics gained; within shows product-mix shift toward lower-tariff sub-categories.
  - **Steel & Aluminum**: +0.33 (between +0.29, within +0.03) — imports compressed under 50% S232.
  - **Apparel & Textiles**: +0.27 (between +0.20, within +0.08)
  - **Chemicals & Plastics**: +0.15 (within dominates)
  - Food & Agriculture: +0.05
  - Pharmaceuticals: +0.03
  - Energy & Minerals: −0.004 (essentially zero)
- Two distinct product stories: high-tariff goods (Steel, Autos) lose share (positive between); medium-tariff catchall categories (Other, Electronics) gain share but shift toward lower-tariff sub-products inside (negative between, positive within).
- **Result**: the trade-diversion gap has both supply-side (high-tariff imports compressed) and demand-side (substitute toward lower-tariff variants within categories) drivers — both Shapley terms matter.

### 9.4 Connection to literature

- Azzimonti's three-channel result (May 2025, 0.6 pp within / 2.7 pp cross) is recovered by our country-lens between/within split at the same period.
- Eck et al.'s "composition" channel is our gap_diversion total.

---

## 10. Other preferences (S2 → S3)

### 10.1 What's in here

- Seven preference channels classified from IMDB importer-declared codes [`classify_pref_channel` in `programs.do`]:
  - **Major IEEPA carve-outs** (`duty_free`: rate_prov 10/18/19): Annex II, ITA, Ch98 / Berman Amendment, generic pharma. Reduces both MFN base and IEEPA reciprocal.
  - **KORUS** (KR program code).
  - **Other bilateral FTAs**: AU, IL, SG, CL, CO, PE, PA, JO, MA, OM, BH, JP partial.
  - **GSP / AGOA**: A, A+, A*, D, E, J, W, Z, N codes.
- Math: per cell,
  - $\Delta_{\text{base}} = (s_{\text{duty\_free}} + s_{\text{korus}} + s_{\text{gsp}} + s_{\text{other\_fta}}) \cdot r_{\text{base}}^{\text{pre}}$
  - $\Delta_{\text{recip}} = s_{\text{duty\_free}} \cdot r_{\text{IEEPA}}^{\text{pre}}$ (only `duty_free` reduces IEEPA reciprocal)
  - $r_{\text{S3}} = \max(0, r_{\text{S2}} - \Delta_{\text{base}} - \Delta_{\text{recip}})$

### 10.2 Per-group attribution (Figs O2, O3)

- O1 (`figure_others_channel_stack.png`): stacked monthly bar showing how the 7 preference channels (Annex II / ITA / Ch98, KORUS, other FTAs, GSP/AGOA, etc.) sum to gap_others.
- O2 (`figure_others_country.png`): stacked bar of per-country contributions to gap_others.
- O3 (`figure_others_product.png`): stacked bar of per-product contributions.
- Sums to gap_others = S2 − S3 by construction.

### 10.3 Discussion

- The `duty_free`-on-IEEPA-recip term is the policy-salient piece: executive-branch carve-outs (Annex II / ITA / Ch98 / generic pharma).
- KORUS / GSP / other_fta are "preferences as usual" — long-standing trade-agreement claims; small in current magnitude.

---

## 11. Residual and timing (S3 → S4 → T)

The 6-tier ladder splits the old "residual+timing" block into two empirically distinct phenomena heading in opposite directions: a structural and persistent residual (S3→S4), and a cyclical, recently-reversed timing channel (S4→T).

### 11.1 The residual (S3 → S4): structural and persistent

- Magnitude: ~1.4–2.6 pp window-mean across W1–W5 (Pre-Liberation through Post-SCOTUS); does **not** converge.
- Per-group: R2 (`figure_residual_country.png`), R3 (`figure_residual_product.png`) decompose gap_residual.
- What's in the residual: specific-duty AVE failures, AD/CVD, tracker error not yet corrected, behavioral noise within HS10 × cty cells.
- Census-declared duties (S4) keep undershooting the cell-level statutory reconstruction (S3) regardless of which policy regime is in force. This is a measurement and behavioral phenomenon, not a transient.

### 11.2 Timing (S4 → T): cyclical, now reversed

- Magnitude trajectory: +0.37 (W1) → +0.45 (W2) → +0.28 (W3) → −0.72 (W4) → **−2.01 (W5, Post-SCOTUS Feb 2026)**.
- Treasury cash receipts (T) now *exceed* Census-declared duties (S4) by a widening margin. Cumulatively (Feb 2025 – Feb 2026), Treasury has over-collected by **~$10.5B** vs IMDB.
- Visualization: `figure_cumulative_duty_gap.png` (built by standalone `code/07_cumulative_duty_gap.do`).
- Aggregate-only — no Treasury microdata available for partner or product breakout.
- Plausible drivers: ACH lag catch-up, post-entry adjustments, refund reversals, FTZ deferrals being paid down. Consistent with Eck et al. (2026)'s prediction that frictional gaps compress as front-loading depletes — but the empirical *sign* of the catch-up is opposite to the naive read (under-collection compressing toward zero); instead, Treasury has overshot.

### 11.3 Tracker miss / over diagnostics

- **`05a tracker_miss_diagnostic.do`**: HS10 × cty × ym cells where tracker rate = 0 but Census duty > 0. Surfaces unparsed authorities, AD/CVD, specific-duty AVE failures.
- **`05b tracker_over_diagnostic.do`**: cells where tracker over-states. Channel-tagged (legit / bug-likely / noise) using `pref_channel`.
- These bound how much of the residual is measurement error vs genuine behavior; appendix-grade content.

---

## 12. Where the gap concentrates

### 12.1 Product × country heatmap (Fig P3: figure_s2s4_heatmap)

- Period-averaged S2 − S4 gap on the 9 (product) × 8 (partner) grid.
- Identifies high-magnitude cells: e.g. China × Electronics (Annex II), CA/MX × Autos (USMCA + S232 derivatives), EU × Pharma (generic exemption).
- Gap is concentrated, not pervasive — most cells small.

### 12.2 4-panel attribution facets (Figs F2, F3)

- F2 (`figure_attribution_country.png`): four panels (USMCA adjustment, trade diversion, other preferences, residual), each a stacked-bar by partner_group × month. Same y-axis across panels (`ycommon`) for magnitude comparability. Treasury timing channel not shown (aggregate-only).
- F3 (`figure_attribution_product.png`): same structure with product_group.
- Reading the figures: which channel × group cells are loud over the analysis window.

### 12.3 Underlying tables (paper appendix)

- `attribution_by_country.csv` and `attribution_by_product.csv`: per-(month, group) for all four decomposable channels.
- Suggested table in main text: period-mean contribution to gap_total per partner_group × channel (8 × 4 grid).

---

## 13. Discussion

### 13.1 What this paper establishes

- The gap is large, growing, and faster-arriving than 2018–2019 [Eck et al., 2026]. Post-USMCA-stabilization (S1−T): **5.19 pp December 2025, 3.57 pp February 2026**. Full ladder gap (S0−T) including USMCA backstory: **7.84 pp December 2025, 6.07 pp February 2026**.
- USMCA claim-rate normalization (S0→S1) averages **2.42 pp** across our window; absorbing it upfront lets the policy-relevant signals (S1→T) come through cleanly. The reporting-pattern shift in July 2025 is visible directly in the data.
- The trade-diversion channel (S1→S2) averages **2.24 pp**; **China alone carries ~90% of the positive between-country contribution** (period mean +2.07 pp from China vs +2.27 pp total positive between-country across all groups; ROW contributes −0.77 pp between as low-tariff partners gain share).
- The product-side decomposition (Fig D3) reveals a two-story pattern: high-tariff goods (Steel, Autos) lose share via the *between* term; medium-tariff catchalls (Other Manufactured, Electronics) gain share but shift their internal mix to lower-tariff variants via the *within* term.
- Composition shifts began *immediately* in 2025, contradicting the slow-substitution view from 2018–2019 [Cavallo et al., 2021; Eck et al., 2026]. By April 2025 the trade-diversion channel was already +3.13 pp.
- The other-preferences channel (S2→S3) is small in magnitude (~**0.5–0.9 pp** late-period) but policy-salient: Annex II / ITA / Ch98 carve-outs reduce both MFN base *and* IEEPA reciprocal, while KORUS / GSP / other FTAs reduce MFN only.
- The 6-tier ladder bifurcates what older frameworks bundled as "residual+timing": (i) **gap_residual (S3→S4) stays positive throughout** at ~1.4–2.6 pp — a structural, non-converging gap from specific-duty AVE failures, AD/CVD, and within-cell behavioral noise; (ii) **gap_timing (S4→T) flipped strongly negative** in mid-2025 and accelerated, hitting **−2.01 pp in February 2026** — Treasury cash receipts now *exceed* Census-declared duties. Cumulatively (Feb 2025–Feb 2026) Treasury has over-collected by **~$10.5B** vs IMDB; the gap widens monotonically since November 2025. Plausible drivers: ACH lag catch-up, post-entry adjustments, refund reversals, FTZ deferrals being paid down.
- Per-product/per-country attribution shows the gap is concentrated, not pervasive: most of the dollar volume sits in a handful of (product × country) cells.
- **Cross-validation against Eck et al. (2026)**: independent methodology reproduces their December 2025 numbers within ~0.6 pp on every comparable quantity (S1: 15.07 vs 14.7, Δ=+0.37 pp; T: 9.88 vs 9.27 implied, Δ=+0.61 pp; total gap: 5.19 vs 5.43, Δ=−0.24 pp). Convergence in independent methodologies validates the framework anchor.

### 13.2 What this paper does not establish

- **Causal claims** about firm behavior — we describe co-movements, not identified responses.
- **Pass-through to consumer prices** — we cite Cavallo, Llamas, Vazquez (2025) and Gopinath–Neiman (2026); we do not estimate.
- **Welfare implications** — Waugh's (2026) TRI framework is the right complement; the framework's per-cell rates are the inputs for that calculation but we do not redo it.
- **Persistence of the gap** — we describe the trajectory but do not test whether transitory frictions (frontloading, shipment timing) will fully resolve.

### 13.3 Investigation paths

- **Convergence dynamics, bifurcated**: Eck et al. predict the gap compresses as front-loading depletes and shipping lags resolve. Our 6-tier ladder splits "convergence" into two tests: (i) the structural residual (S3→S4) shows *no* sign of compressing — Census-declared duties persistently undershoot the cell-level reconstruction by ~1.4–2.6 pp regardless of regime; (ii) the timing channel (S4→T) is converging *and overshooting* — Treasury cash receipts have moved from below to above Census-declared, with cumulative over-collection reaching ~$10.5B by Feb 2026. The Eck prediction is half right: timing resolves, but residual is structural.
- **Annex II quantification**: the largest single chunk of gap_others sits in the IEEPA carve-out term. Decomposing further by HS2 chapter inside Electronics × Pharma × Energy would attribute the carve-out story across product classes.
- **Tracker error itemization**: the two diagnostic files (`05a`, `05b`) export operator-handoff CSVs identifying specific HTS codes where Census duties exceed (or fall short of) tracker rates. These bound how much of the residual is measurement vs behavior.
- **Welfare framing**: pair our duty-collection ETR series with Waugh's TRI. Estimating dispersion and the welfare-equivalent uniform rate is mechanical from the per-cell rates we already produce.
- **2018–19 vs 2025 comparison**: Eck et al. note the 2018 episode had a 22% gap fraction; 2025 has 44%. Re-running the framework on 2017–19 data would test whether the channel mix has structurally changed.
- **Policy-counterfactual ladder**: the existing `counterfactual_usmca_none.csv` panel (0% claim rate) gives the upper-bound "if no USMCA" statutory rate. Pair with the existing rungs to bound revenue under enforcement scenarios.

### 13.4 Live policy questions the paper can inform

- **Fiscal forecasting**: how much revenue should be expected from announced tariffs? Our channel decomposition implies a 30–45% haircut in 2025; the per-channel evolution suggests partial convergence over time.
- **Will the gap close as frictions resolve?** Eck et al. say partly; our panel splits the answer: the *timing* channel has already resolved and overshot (cumulative over-collection reached ~$10.5B by Feb 2026), while the *structural residual* shows no sign of compressing.
- **What would full enforcement / no exemptions imply?** The `usmca_none` ladder provides an upper-bound number; a similar `pref_none` panel (zero non-USMCA preferences) is mechanical to construct.

---

## Appendices

### A. Detailed math
- Shapley two-way derivation (with both orderings averaged)
- Validation: Σ(c_total) per ym matches gap_diversion within numerical noise (asserted at runtime in 03 Section B)
- Per-group attribution math for fixed-weight rate-shift cases (S2→S3, S3→S4)

### B. Rate panel construction
- 5-layer authority stacking (with worked examples for S232 derivatives, IEEPA fentanyl carve-outs, USMCA exemption mechanics)
- Day-weighting algorithm across HTS revisions
- Comparison of the four scenario panels (rate_2024, rate_h2avg, rate_usmca_monthly, rate_all_pref) and their construction

### C. Data sources
- Detailed IMDB schema; rate_prov / cty_subco classification rules
- Tracker_snapshots schema and revision dates
- USITC DataWeb USMCA share files (carry-forward conventions)
- Treasury revenue series (Haver mnemonics)

### D. Validation
- Cross-validation against Eck et al. (2026) at Dec 2025 — full table with all comparable months
- Self-consistency checks (Fig 7 diagnostic): etr_full ≡ S1, s0_recon ≡ S0
- Tracker_miss / tracker_over magnitudes
- Specific-duty AVE coverage audit

### E. Robustness
- Alternative USMCA scenarios (none / 2024 / monthly / h2avg comparison table)
- Alternative weight years (2023, 2024)
- Sub-period splits (pre-Liberation, Liberation→Phase 2, Phase 2→SCOTUS, post-SCOTUS)
- Thin-trade thresholds (drop cells below $X import value)
- Sensitivity to the 0.40 US-content rule for auto/MHD

### F. Product-group taxonomy
- Full 9-group HS2 mapping (`product_groups.csv`)
- Justification for groupings (policy salience)
- Sensitivity: alternative groupings (e.g. separating copper from "Other Manufactured")

---

## References

Lifted from `etr-literature-review.md`. Full bibliography in the paper.

**Anchor papers**:
- Gopinath, G. and B. Neiman (2026). "The Incidence of Tariffs: Rates and Reality." NBER Working Paper No. 34620.
- Azzimonti, M. (2025). "Why Predicted and Actual Tariff Rates Diverged in May 2025." Federal Reserve Bank of Richmond Economic Brief No. 25-29.
- Eck, S., T. Hoang, C. Mix, and M. Ray (2026). "Mind the Gap: Announced versus Implied Tariff Rates in Recent Trade Policy Episodes." FEDS Notes, Board of Governors of the Federal Reserve System, April 8.

**Tracking series**:
- Penn Wharton Budget Model (2025–26). "Effective Tariff Rates and Revenues." Updated monthly.
- Yale Budget Lab (2025–26). "State of U.S. Tariffs" and "Tracking the Economic Effects of Tariffs."

**Methodology / measurement**:
- Waugh, M. (2026). "How Restrictive Is U.S. Trade Policy?" Federal Reserve Bank of Minneapolis Staff Report No. 681.
- Anderson, J. and J.P. Neary (1996). "A New Approach to Evaluating Trade Policy." *Review of Economic Studies* 63(1): 107–125.

**Pass-through and firm response**:
- Cavallo, A., G. Gopinath, B. Neiman, and J. Tang (2021). "Tariff Pass-Through at the Border and at the Store." *AER:I* 3(1): 19–34.
- Cavallo, A., P. Llamas, and F. Vazquez (2025). "Tracking the Short-Run Price Impact of U.S. Tariffs." NBER Working Paper No. 34496.
- Flaaen, A., A. Hortaçsu, F. Tintelnot, N. Urdaneta, and D. Xu (2025). "Tariff Pass-Through from the Border to the Store." BFI Working Paper No. 2025-137.
- Cui, S., Z. Feng, L.X. Lu, and B. Tomlin (2025). "Navigating Tariff Risks: Stockpiling, Sourcing Diversification, or Responsive Pricing?" SSRN No. 5110124.

**2018–19 episode**:
- Fajgelbaum, P., P. Goldberg, P. Kennedy, and A. Khandelwal (2020). "The Return to Protectionism." *QJE* 135(1): 1–55.
- Alfaro, L. and D. Chor (2025). "An Update on the Great Reallocation in US Supply Chain Trade." CEPR VoxEU Column.
- Barbiero, O., A. Silva, V. Sheremirov, and H. Stein (2025). "U.S. Firms' Exposure to Tariffs." Federal Reserve Bank of Boston Working Paper.

**Historical / fiscal**:
- Clausing, K. and M. Obstfeld (2025). "Tariffs as Fiscal Policy." NBER Working Paper No. 34192.
- Gerlach, S. (2025). "Long-Run Effective Tariff Rates: A 150-Year Perspective." EFG International.

---

## Cross-document map

| Document | Role |
|---|---|
| `paper_outline_v2.md` (this) | Current paper outline |
| `methodology_outline.md` | Implementation-side methodology reference; predates the May 2026 framework restructure (some script names and tier labels are stale; treat as supplementary). |
| `etr-literature-review.md` | Full citation library |
| `etr_divergence_slides.tex` | 10-min presentation, parallel structure |
| `weighting_note.md` | Aggregation note (single-stage row-level value-weighted; correctly described after the framework restructure) |
| `six_tier_framework_plan.md` | Framework math derivation (Shapley two-way, applicability matrix, sign-bearing channels). Tier definitions kept in sync with `CLAUDE.md` |
| `archive/` | Superseded planning docs (`paper_outline.md`, `Outline.docx`, `dense_rate_export_plan_response.md`, `diagnostic_refresh_plan.md`, `todo.txt`). See `archive/README.md` for disposition |

---

## Open questions for authors

1. **Headline scenario confirmation**: `usmca_h2avg` = S1/S2 anchor (current); `usmca_2024` = S0; `usmca_monthly` = explainer only. Confirm.
2. **Channel naming**: "USMCA adjustment" for S0→S1 (current) vs. alternatives (normalization, recognition, backfill). Stick with adjustment unless paper editor pushes.
3. **Ordering of §9 (diversion) vs §10 (other preferences)**: present-tier order (current) vs magnitude order (which is largest in the data).
4. **Section 2 length**: keep policy taxonomy compact or expand into a self-contained chapter? Current draft compresses; the archived `archive/paper_outline.md` had a fuller version that could be revived.
5. **Audience**: economics journal (full math + appendices) vs policy outlet (compress §5 to a methods box, expand §13)? The Beamer slide deck targets the latter; the paper outline above targets the former.
