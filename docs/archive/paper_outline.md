# Actual vs. Statutory Effective Tariff Rates — Paper Outline

**Working title**: Actual versus Statutory Effective Tariff Rates: Decomposing the 2025–2026 U.S. Tariff Gap
**Authors**: Abhi Gupta, John Iselin, John Ricco (The Budget Lab at Yale)
**Status**: Outline draft, 2026-04-27

This document drafts the paper's narrative structure. Implementation detail and open methodology questions live in `docs/methodology_outline.md`; literature touchpoints are catalogued in `docs/etr-literature-review.md`. Current Overleaf source: `Dropbox/Apps/Overleaf/actual_statutory_etr/main.tex`.

---

## 0. Front matter

- Title, authors, affiliations
- Abstract (~150 words): document the gap; introduce four-tier decomposition; report magnitudes by month/partner/chapter; preview USMCA surge as the dominant exemption channel; situate against Gopinath–Neiman, Eck et al. (2026), and Yale Budget Lab tracking.
- Keywords: tariffs, trade policy, effective tariff rate, USMCA, Section 232, Section 301
- JEL: F1, F3

## 1. Introduction

- Hook: announced statutory rates of ~27% by late 2025, but realized ETR ~10–11% — a gap unprecedented in modern data.
- Three motivating questions:
  1. **How big is the gap, and how has it evolved month-by-month?**
  2. **What channels explain it** — composition shifts (which products and which sources), exemptions (USMCA and other preferences), or implementation/timing/enforcement?
  3. **Where does the gap concentrate?** Which partner countries and which HS2 chapters drive the aggregate, and which channels dominate within each.
- Contribution statement (3 bullets):
  - First **four-tier** decomposition that separates exemption claiming (T2→T3) from timing/enforcement (T3→T4); existing literature pools these.
  - Direct, transparent reconstruction of statutory rates from the HTS + Chapter 99 authorities (via the `tariff-rate-tracker` pipeline) rather than relying on aggregated indices.
  - Counterfactual USMCA ladder isolating the share-claim surge from underlying weight composition.
- Roadmap paragraph.

---

## 2. Review of tariff episodes

A compact historical and policy chapter situating 2025–2026 in a longer arc and cataloguing the active authorities. Half history, half policy taxonomy.

### 2.1 Long-run perspective (1867–present)
- Tariffs as primary federal revenue source through ~1913 (peaks near 50% effective rate).
- Post-Smoot–Hawley → GATT/WTO era: secular decline to ~1.5% by 2017.
- Sources: Gerlach (2025) for the long series; standard trade-history references.
- One figure: 150-year effective tariff rate (annual, 1867–2025). 
Note: Pull from Figure 1 here - https://budgetlab.yale.edu/research/state-us-tariffs-april-8-2026) 
Note: Data located here: "C:\Users\ji252\OneDrive - Yale University\Budget Lab - Topics\Trade\2026 04 April 8 State of Tariffs\data_download.xlsx"

### 2.2 The 2018–2019 (Trump I) escalation
- Section 301 lists 1–4 against China; Section 232 on steel and aluminum.
- Effective rate rose ~2 pp; statutory increase ~4.1 pp; gap ~0.44 pp / 22% of announced (Eck et al. 2026).
- Concentration: HHI ≈ 0.29 (China-dominant).
- Empirical findings (Fajgelbaum et al. 2020; Cavallo, Gopinath, Neiman, Tang 2021): near-complete border pass-through, slow sourcing substitution.

### 2.3 The 2020–2024 interregnum
- Biden administration retains most Trump I tariffs; selected Section 301 expansions (EVs, batteries, semiconductors, cranes — late 2024).
- Effective rate stable at 2.3–2.5%.
- Sets up the 2024 baseline used throughout the paper.

### 2.4 The 2025–2026 (Trump II) escalation
- **February 2025**: IEEPA fentanyl tariffs on China, Canada, Mexico (+10% / +25%).
- **March 2025**: Section 232 expansion (steel/aluminum to 25–50%; auto vehicles 25%).
- **April 2, 2025 ("Liberation Day")**: IEEPA reciprocal Phase 1 — country-specific surcharges on most trading partners.
- **April 9, 2025**: 90-day pause on Phase 1 reciprocal (except China).
- **June–July 2025**: Section 232 commodities ramp (steel/aluminum to 50%, copper 50%, MHD vehicles).
- **August 7, 2025**: Phase 2 reciprocal — country-specific EOs replacing Phase 1.
- **November 2025**: South Korea floor (15%); Section 232 auto carve-out for KR.
- **January 2026**: Section 232 semiconductors (9903.79); Switzerland/Liechtenstein floor.
- **February 24, 2026**: SCOTUS invalidates IEEPA reciprocal authority; Phase 3 Section 122 (10% blanket) takes effect.
- **April 6, 2026**: Section 232 annex restructuring (50/25/0/15% four-tier).
- One table: chronology of major actions with HTS revision pointer.
- One figure: announced statutory rate by month with policy event markers.
- HHI ≈ 0.06 — far broader than 2018–2019.
NOTE: Replicate figure 1 here https://budgetlab.yale.edu/research/introducing-tariff-rate-tracker-open-source-tool-daily-effective-tariff-rates
NOTE: Data for policy here: C:/Users/ji252/OneDrive - Yale University/Budget Lab - Topics/Trade/2026 04 April 2 Tariff Daily Rate Tracker/tariff_rate_tracker_blog_20260408.xlsx

### 2.5 Authority taxonomy (paper's running cross-reference)
- Section 232, 301, 201; IEEPA reciprocal & fentanyl; Section 122; "other"; baseline MFN.
- Stacking conventions (per Tariff-ETRs / tracker), USMCA exemption mechanics, country-specific country EOs.
- Brief: this is what `tau^s_{cpt}` is composed of in §3.

---

## 3. Methodology

Mirrors the structure of Eck, Hoang, Mix, and Ray (2026): clean separation of *announced* ETR (statutory rates × baseline weights) from *realized* ETR (duties collected ÷ imports), then decomposition into composition and rate-discrepancy channels. We extend their two-channel structure to four tiers because Census calculated duties give us a third anchor between announced rates and Treasury collections.
NOTE: Make it clear this was developed seperately from Eck et a. (2026) but credit them as seperate work we check against. 

Implementation detail in `docs/methodology_outline.md` §3; this section is the paper-prose version of those choices.

### 3.1 Definitions and the basic identity
- Equations (1)–(3) from the Overleaf draft:
  - $\tau_t = R_t / I_t$ (basic ETR)
  - $\tau^s_t = \sum i_{cp,2024}\tau^s_{cpt} / \sum i_{cp,2024}$ (announced statutory)
  - $\tau^a_t = \sum i_{cpt}\tau^a_{cpt} / \sum i_{cpt}$ (realized actual)
- Decomposition (eqs. 4–5) into the weight-composition gap and the pair-level rate gap.
- Add the **four-tier extension**: introduce $T_3 = \sum d^{\text{calc}}_{cpt} / \sum i_{cpt}$ as a Census-duties proxy that bridges $T_2$ (statutory at monthly weights) and $T_4$ (Treasury aggregate). Signed-sum identity: $T_1 - T_4 = (T_1-T_2) + (T_2-T_3) + (T_3-T_4)$.

### 3.2 Constructing $\tau^s_{cpt}$
- HTS revision archive (39 revisions, 2025-basic → 2026-rev_5) parsed by the tracker.
- MFN base rate (HS10) + Chapter 99 stacking (232/301/IEEPA recip/IEEPA fent/Section 122/Section 201/other).
- Specific-duty AVE conversion at HS10 using 2024 unit values.
- USMCA exemption: scales the non-232 component by $(1 - s_{cp})$ where $s_{cp}$ is the DataWeb S/S+ utilization share.
- Day-weighting within months across HTS revisions.
- Forward-pointer: §3.4 reports four scenarios for $s_{cp}$.

### 3.3 Constructing $\tau^a_t$ inputs
- $T_3$: Census IMDB HS10 × country × month calculated duties / consumption value.
- $T_4$: Treasury monthly customs duties / goods imports (Haver mnemonics; see methodology_outline.md §7).
- Trade weights: $i_{cp,2024}$ from the GTAP-aligned 2024 import cache; $i_{cpt}$ from IMDB.

### 3.4 USMCA scenarios
Brief paragraph; full table in `methodology_outline.md` §3.2:

| Scenario | Shares | Role in paper |
|---|---|---|
| `usmca_none` | 0% | Upper bound on statutory | <- Note: Drop 
| `usmca_2024` | 2024 annual | Pre-tariff baseline |
| `usmca_monthly` | actual 2025+ monthly | Realized claiming |
| `usmca_h2avg` | H2 2025 average | **Headline** statutory baseline |

### 3.5 Universe alignment and the asymmetric-pair issue
- Both $T_1$ and $T_2$ defined on the union of 2024-active and monthly-active pairs (per methodology_outline.md §3.3).
- New-in-2025 pairs ($i_{cp,2024}=0,\ i_{cpt}>0$) carry zero weight in $T_1$ and positive weight in $T_2$ — this is what makes the $T_1 - T_2$ gap meaningful.
- Brief discussion of the diagnostic finding (this conversation, 2026-04-27): the asymmetric pairs are 8.93% of rows but only 6.08% of monthly value and 1.89% of duties; concentrated in ROW.

### 3.6 Aggregation hierarchy
- Total, partner group (8: China, CA, MX, EU, JP, KR, UK, ROW), HS2 chapter (99).

### 3.7 Limitations stated upfront
- Calculated-duty proxy: entry-level, pre-refund, pre-enforcement adjustment.
- Specific-duty AVE: 2024 unit-value-based; fragile on new HS10s.
- USMCA shares are *claimed*, not *eligible*.
- Treasury–Census denominator mismatch (T3 vs T4).
- Pair-level lumpiness in sub-aggregates.

(This subsection is what we promise to revisit in §6 robustness.)

---

## 4. Initial results

Mirrors §2 of Eck et al. (2026) but with our four-tier decomposition. The exposition leads with the simplest baseline-vs-actual comparison and then progressively unpacks it into tiers, channels, the USMCA sub-channel, and within-month dynamics.

### 4.1 The baseline gap: tracker statutory at 2024 weights vs. Treasury actual
- The simplest possible comparison and the paper's headline figure.
- **Statutory series**: $T_1^{\text{h2avg}}$ — tracker production rates (USMCA at H2-2025 average claim share, the tracker's default scenario) weighted by 2024 import shares.
- **Actual series**: $T_4$ — Treasury monthly customs duties divided by goods imports value.
- **Figure 1** (NEW; not yet generated by `02_etr_analysis.do`): two-line monthly time series, January 2025 → most recent complete month, with policy event markers (Liberation Day, Phase 2, SCOTUS / Phase 3, Section 232 annex restructuring).
- Headline numbers (placeholder; recompute on current data):
  - $T_1^{\text{h2avg}}$ at the latest month vs. 2024 baseline: announced increase of $\approx ?$ pp.
  - $T_4$ at the latest month vs. 2024 baseline: realized increase of $\approx ?$ pp.
  - Gap as share of announced increase.
  - Direct quantitative comparison to Eck et al. (Dec 2025: 5.43 pp / 44%) and PWBM (10.3% effective rate, Jan 2026).
- This figure is the cleanest "what most readers want to see" plot. Everything else in §4 unpacks it.
- **Implementation note**: requires a small new code block in `02_etr_analysis.do` (or a dedicated `02b_baseline_figure.do`) that computes $T_1$ from the production scenario top-level snapshots × 2024 weights and joins to `tracker_revenue.dta`. Cannot reuse the current Section C generator without changes (which builds S0/S1/S2 from the `usmca_2024` and `usmca_monthly` scenarios, not `usmca_h2avg`).

### 4.2 Four-tier decomposition
- Adds two intermediate series to §4.1: $T_2^{\text{h2avg}}$ (statutory at monthly weights) and $T_3$ (Census calculated duties ÷ imports).
- **Figure 2**: monthly four-tier ETR (current `figure1_etr_comparison.png`, re-rendered as four lines with $T_2$ and $T_3$ added).
- Channels read off the figure: $T_1{-}T_2$ (composition), $T_2{-}T_3$ (rate gap at entry, dominated by USMCA), $T_3{-}T_4$ (collections gap).

### 4.3 Decomposition into composition vs. rate-discrepancy channels (Eck-mirroring)
- Two-channel collapse for direct comparison to Eck et al.: composition $= T_1{-}T_2$; rate discrepancy $= T_2{-}T_4$.
- **Figure 3**: monthly stacked bar of the two channels (current `figure2_gap_stacked.png`, may need recolor for two channels not three).
- Numbers parallel to Eck et al.'s Table 1 (composition pp, rate-discrepancy pp, total).
- Direct quantitative comparison:
  - Eck (Dec 2025): rate-discrepancy channel ≫ composition channel.
  - Our finding: [TBD on full data].

### 4.4 USMCA surge as a sub-channel of rate discrepancies
- The single largest mover within the rate-discrepancy channel.
- **Figure 4**: USMCA vs non-USMCA decomposition (current `figure3_usmca_decomp.png`, will renumber).
- Numbers: CA/MX USMCA claim share rises from ~33–38% (2024) to ~88% (Dec 2025) per PWBM; report our analogous DataWeb-derived series.

### 4.5 Within-month variation: daily statutory vs. monthly aggregate
- Motivation: the monthly aggregate is the day-weighted mean of a daily series that has structural breaks at HTS revision dates. Plotting both demonstrates that (i) the monthly figure is well-defined despite within-month policy changes, and (ii) the largest within-month moves (Liberation Day in April 2025, SCOTUS / Phase 3 in February 2026, Section 232 annex restructuring in April 2026) are not artifacts of the aggregation.
- **Figure 5** (NEW): daily statutory ETR from `daily_overall.csv` (tracker production output) overlaid on the monthly $T_1^{\text{h2avg}}$ series from §4.1. Daily as a thin line; monthly as step bars or markers at month-mid. Same y-axis.
- This is essentially a methodology-validation figure but reads as a results figure. Could optionally move to an appendix; recommend keeping in main text since the within-month structure is intrinsically interesting.
- **Implementation note**: requires reading `data/raw/daily_overall.csv` (already present from `00_pull_raw_data.R` Section 3c) and joining month-end aggregates to the monthly series. New small code block in `02_etr_analysis.do` or a dedicated `02c_daily_overlay.do`.

---

## 5. Additional decompositions

Where this paper extends past Eck et al. The four-tier framework, the per-partner Shapley split, the HS2 chapter ranking, the FTA preference channels, and the max-district cross-check are all uniquely available because we hold tracker-level statutory rates and IMDB district-level entries.

### 5.1 Four-tier decomposition: separating exemptions from enforcement
- Eck pools both into "rate discrepancies." We split:
  - $T_2 - T_3$: pair-level rate gap (preference claiming, exemptions, MFN-zero pickups, entry-level effects).
  - $T_3 - T_4$: collections gap (post-entry adjustments, timing, denominator differences).
- **Table**: monthly four-tier rates and three-channel gaps.
- Discussion: the two channels behave very differently. $T_2-T_3$ is dominated by USMCA; $T_3-T_4$ has timing/litigation interpretation.

### 5.2 Partner-group decomposition (Shapley between/within)
- Section B of `02_etr_analysis.do`.
- Per-month, per-country contribution to the $T_1 - T_2$ behavioral gap.
- **Figure**: stacked monthly contribution by 8 partner groups.
- **Table**: cumulative between vs within for each partner group.
- Highlights:
  - China: large share-shrinkage contribution (between).
  - CA/MX: large within-country contribution (USMCA composition).
  - ROW: surge in share from low-tariff partners (Vietnam, India).

### 5.3 HS2 chapter ranking
- Where in the tariff schedule does the gap concentrate?
- **Table**: top 25 HS2 chapters by dollar gap.
- Likely highlights: chapters 84/85 (electronics/machinery), 87 (autos), 28–38 (chemicals), 72/73 (steel).

### 5.4 FTA and preference-channel decomposition
- IMDB rate-provision codes split the $T_2 - T_3$ exemption gap into: USMCA, KORUS, other FTAs, GSP/AGOA, duty-free entries, ch99 dutiable, MFN dutiable.
- **Figure**: monthly stacked by preference channel.
- Cross-reference Yale Budget Lab's MFN-zero-pickup finding (Section 4.2 of literature review): we should be able to replicate their −6 pp / −3 pp adjustment for CA/MX.

### 5.5 Max-district crosscheck
- Validates tracker statutory rates against the maximum entry-rate observed across customs districts per HS10 × country.
- Three categories: match / tracker_higher / observed_higher.
- **Table**: counts and dollar coverage by category.
- This is a tracker-validation diagnostic; appendix-grade content unless something surprising surfaces.

### 5.6 USMCA counterfactual ladder
- Two parallel ladders at fixed 2024 weights and at monthly weights:
  - $T_k^{\text{none}} \to T_k^{\text{2024}} \to T_k^{\text{monthly}} \to T_k^{\text{h2avg}}$.
- Differences within a ladder = pure USMCA-claiming response.
- Differences between ladders = interaction of claiming with weight composition.
- **Figure**: waterfall.
- Cleanly separates "claim any" vs "surge" vs "averaging" — an extension over the existing S0/S1/S2 in `05_counterfactual_ladder.do`.

### 5.7 Sub-aggregate sensitivity (appendix)
- Robustness: thin-trade cells, alternative USMCA scenarios, alternative AVE conversion.
- Quantify the asymmetric-pair contribution to the $T_1 - T_2$ gap.

---

## 6. Discussion: what we can say, and what we can't

A short concluding section organized around three claim levels.

### 6.1 What this paper establishes
- The gap is large, growing, and faster-arriving than 2018–2019.
- USMCA claim surge is the largest single channel within the exemption gap.
- Composition shifts began *immediately* in 2025, contradicting the slow-substitution view from 2018–2019.
- The four-tier structure shows that exemption claiming and timing/enforcement contribute roughly comparable magnitudes (precise split TBD on final data).
- HS2 / partner heterogeneity reveals that the aggregate gap is the average of very disparate cell-level gaps.

### 6.2 What this paper does not establish
- **Causal claims** about firm behavior — we describe co-movements, not identified responses.
- **Pass-through to consumer prices** — relegate to Cavallo, Llamas, Vazquez (2025) and Gopinath–Neiman (2026) for now.
- **Welfare implications** — Waugh's TRI framework is the right complement; cite, don't redo.
- **Persistence of the gap** — we can describe the trajectory but cannot test whether transitory frictions (frontloading, shipment timing) will fully resolve.

### 6.3 Next steps
- **Empirical**:
  - Treasury source verification: confirm $T_4$ Haver mnemonic (open question 8 in methodology_outline.md).
  - Specific-duty AVE coverage audit (open task in methodology_outline.md §7).
  - Asymmetric-pair quantification (already done at the row level — extend to dollar-weighted contribution to $T_1 - T_2$).
- **Methodological**:
  - Decide headline USMCA scenario (`usmca_h2avg` proposed; confirm).
  - Inference / standard errors on the monthly gap series — currently descriptive.
  - Tariff-engineering and HTS-reclassification audit: track HS10 codes whose import share changes dramatically and whose rates differ from neighbor codes.
- **Cross-paper**:
  - Re-run after every HTS revision to extend the panel (pipeline is now automated via `--refresh-tracker`).
  - Coordinate with the Yale Budget Lab tracking series for consistent MFN-zero treatment.

### 6.4 Live policy questions the paper can inform
- How much fiscal revenue should be expected from announced tariffs? (Composition + USMCA channels suggest a 30–45% haircut in 2025.)
- Will the gap close as frictions resolve? (Eck et al. say partly; we can test directly with our four-tier panel.)
- What would full enforcement / no exemptions imply? (Counterfactual `usmca_none` ladder gives an upper-bound number.)

---

## Appendices

- **A. Authority parsing detail** — how Chapter 99 footnotes map to product-country pairs, with worked examples for Section 232 derivatives, IEEPA fentanyl carve-outs, and USMCA exemption mechanics. Mostly pulled from `tariff-rate-tracker` documentation.
- **B. AVE conversion** — coverage table, fallback rules, sensitivity to alternative unit-value years.
- **C. HS2 chapter and partner-group tables** — full versions of the ranked tables shown in §5.
- **D. Robustness** — alternative USMCA scenarios; alternative weight years; sub-period splits; thin-trade thresholds.
- **E. Validation** — TPC match-rate regression, max-district crosscheck, dense-grid sanity check.

---

## Cross-document map

| Document | Role |
|---|---|
| `docs/paper_outline.md` (this file) | Paper structure and narrative |
| `docs/methodology_outline.md` | Implementation/working doc, equations source-of-truth |
| `docs/etr-literature-review.md` | Cited works and where they fit |
| `docs/weighting_note.md` | Two-stage weighting note (legacy; aggregation discussion) |
| `code/02_etr_analysis.do` | Section 4–5 figures and tables generator |
| `code/03_fta_decomposition.do` | Section 5.4 generator |
| `code/04_max_district_crosscheck.do` | Section 5.5 generator |
| `code/05_counterfactual_ladder.do` | Section 5.6 generator |
| `Dropbox/.../actual_statutory_etr/main.tex` | Overleaf draft |

---

## Open questions for the authors

1. **Headline USMCA scenario**: confirm `usmca_h2avg` as baseline + `usmca_none` as upper bound for the main figures.
2. **§4.5 placement**: keep the daily-vs-monthly overlay in main text or relegate to an appendix as methodology validation?
3. **Section 5 ordering**: the four-tier extension (5.1) vs the partner-group split (5.2) — which leads?
4. **Authorship and Yale Budget Lab branding** for the TBL methodology cross-references — coordinate with Ricco/Gupta on shared series.
5. **Length target**: AEA-style 30 pages or FEDS-Note-style 8? The latter would push §5.3–5.7 into appendices.
