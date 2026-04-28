# Trackerover Diagnostic — Handoff to `tariff-rate-tracker`

**Authored by**: `tariff-etr-eval` (John Iselin, Yale Budget Lab)
**First written**: 2026-04-28 (Round 1, against current production snapshots)

This is the companion to `tracker_miss_report.md`. The trackermiss report covers cells where the tracker rate is **zero but Census collected duty** (false negatives). This report covers the opposite error: cells where the **tracker rate is positive but Census collected far less than the tracker implies** (false positives / over-statement).

The two diagnostics catch complementary tracker errors:

| | Trackermiss (05a) | Trackerover (05b) |
|---|---|---|
| Signature | `rate_usmca_monthly == 0` & `cal_dut_mo > 0` | `rate_usmca_monthly > 0` & `con_val_mo · rate > cal_dut_mo` |
| Error | False negative — tracker missed a rate | False positive — tracker over-stated a rate |

Together they bracket the rate-parsing accuracy surface from both directions.

---

## What "trackerover" means here

We define an over-stating *entry* (HS10 × country × month × rate_prov × cty_subco) as one where:

```
rate_usmca_monthly > 0
AND  con_val_mo * rate_usmca_monthly  >  cal_dut_mo
```

The over-statement amount is `over_dollars = max(0, statutory_duty − actual_duty)`.

Working at entry granularity (rate_prov × cty_subco within the cell, not just at the cell) lets us attribute the over-statement to a specific **preference / rate-provision channel** using the same nine-channel classifier as `03_fta_decomposition.do`. That classification is what separates *bugs* from *legitimate preference use*.

### Channel partition

| Group | Channels | Diagnosis |
|---|---|---|
| **LEGIT** (preference-claimed; expected gap, **not a tracker bug**) | `usmca`, `korus`, `other_fta`, `gsp_agoa` | Importers correctly claimed an FTA / GSP preference. Tracker rate is the statutory rate before the preference; the gap is intended. Possible signal for the tracker's USMCA-share modeling (if USMCA gap is concentrated, the share inputs may be too low) but not a rate-parsing bug. |
| **BUG-LIKELY** (tracker error candidates) | `duty_free` (rate_prov 10/18/19), `mfn_dutiable` (61/62/64/70), `ch99_dutiable` (69/79) | Importer's filing classification implies a rate ≤ tracker rate. Tracker should match what was actually paid. |
| **NOISE** | `ftz_bonded` (rate_prov 00), `other` | FTZ deferred duties or unclassified residual. Excluded from the actionable ranking. |

The five ranking outputs (`top_cells`, `by_rate_prov`, `by_hs2`, `by_country`, `by_country_detail`, `by_revision`) filter to **BUG-LIKELY only**. `tracker_over_by_channel.csv` shows the full split for sanity-checking.

## Pipeline

```
Census IMDB bulk (HS10 × cty × district × rate_prov × cty_subco × month)
  ├─→ classify_pref_channel(cty_subco, rate_prov, cty_code)
  ├─→ collapse over districts → (HS10, cty, ym, rate_prov, pref_channel)
  └─→ merge tracker rate_usmca_monthly per (HS10, cty, ym)

Filter to over-stating entries (rate > 0, statutory_duty > cal_dut_mo)
  Tag legit / buglike / noise from pref_channel
  → 7 diagnostic CSVs
```

The Stata script lives at `code/05b_tracker_over_diagnostic.do`. The classifier program is shared with `03_fta_decomposition.do` (`code/utils/programs.do::classify_pref_channel`).

## Files (in `results/tables/`)

| File | Contents | Most useful for |
|---|---|---|
| **`tracker_over_by_rate_prov.csv`** | All `rate_prov` codes ranked by BUG-LIKELY over-$ | Single most diagnostic file — 7 rate_prov codes, total $161 B |
| **`tracker_over_by_channel.csv`** | Full pref_channel breakdown (legit + bug + noise) | Sanity-check the partition; size of each bug class |
| `tracker_over_top_cells.csv` | Top BUG-LIKELY cells by over-$ (rank 1–200 plus all > $1 M), top-3 rate_prov per cell with channel tags | Click-and-fix worst-offenders |
| `tracker_over_by_hs2.csv` | HS2 chapter ranking (BUG-LIKELY) | Localizes to product families |
| `tracker_over_by_country.csv` | Partner-group ranking (BUG-LIKELY) | Country-level prioritization |
| `tracker_over_by_country_detail.csv` | Top 50 individual countries with names | Resolves which countries inside ROW dominate |
| `tracker_over_by_revision.csv` | Revision in which each `(HS10, cty)` first over-stated | Localizes to a tracker code change |

---

# Round 1 — Initial findings (2026-04-28)

Run against current production snapshots (h2avg + usmca_monthly), Jan 2025 – Feb 2026.

**Total over-statement**: $216.15 B across 1,388,642 over-stating entries.

| Group | Over-$ | Share |
|---|---:|---:|
| **BUG-LIKELY** | **$161.32 B** | **74.6 %** |
| LEGIT (preference-claimed) | $49.26 B | 22.8 % |
| NOISE (FTZ + other) | $5.56 B | 2.6 % |

The LEGIT $49 B is dominated by USMCA ($43.3 B); KORUS ($2.5 B), GSP/AGOA ($1.8 B), and other FTAs ($1.7 B) are the rest. That is **not a rate-parsing bug** — the tracker correctly applies pre-preference statutory rates and importers correctly claim the preferences. It is, however, a useful signal for USMCA-share modeling: if specific HS10×country pairs show large `usmca` over-statement, the tracker's monthly share inputs are likely too low for those pairs.

The remainder of this report focuses on the **$161 B BUG-LIKELY** surface.

## By `rate_prov` — the most diagnostic axis

| `rate_prov` | Channel | Over-$ | Share | Cell-rows |
|---|---|---:|---:|---:|
| **19** | duty_free | **$64.56 B** | **40.0 %** | 193,946 |
| **10** | duty_free | **$45.54 B** | **28.2 %** | 93,654 |
| **69** | ch99_dutiable | $32.94 B | 20.4 % | 524,981 |
| 79 | ch99_dutiable | $9.26 B | 5.7 % | 97,228 |
| 61 | mfn_dutiable | $7.81 B | 4.8 % | 152,517 |
| 18 | duty_free | $0.85 B | 0.5 % | 29,488 |
| 70 | mfn_dutiable | $0.37 B | 0.2 % | 585 |

**Aggregating by channel:**

- **`duty_free`** (rate_prov 10/18/19): **$110.9 B = 68.7 %** of BUG-LIKELY. Importers declared duty-free under entries claiming an HTS exemption (typically Ch98, ITA / 9903.01.32, Berman), but the tracker is applying a positive rate. Either the tracker is missing the product-level exemption, or it is over-applying a higher-level authority that should have been pre-empted by the exemption.
- **`ch99_dutiable`** (rate_prov 69/79): **$42.2 B = 26.2 %**. Importer filed under a Chapter 99 dutiable line and paid that line's rate; tracker rate is higher than what was actually paid. Suggests wrong rate parsed on a Ch99 line, or stacking that adds an authority the importer did not.
- **`mfn_dutiable`** (rate_prov 61/62/64/70): **$8.2 B = 5.1 %**. Importer filed MFN, paid MFN; tracker rate is higher. Either tracker MFN base rate is wrong, or tracker is layering an authority that doesn't apply to this product.

**Note on the duty_free direction.** This is the *mirror image* of the trackermiss Round 3 finding. Trackermiss Round 3 concluded that a large fraction of "tracker = 0, Census > 0" cells reflected importer **non-claim of 9903.01.32** (i.e., the tracker is correct, importers didn't claim eligible exemptions). The trackerover signal in `duty_free` is the opposite: importers **did claim** the exemption (rate_prov 10/18/19), but the tracker still applied a positive rate. Where trackermiss flagged eligibility-without-claim, trackerover flags claim-without-eligibility-recognition in the tracker's product-rate map.

## By HS2 chapter (BUG-LIKELY top 10)

| HS2 | Description | Over-$ | Share |
|---|---|---:|---:|
| **84** | Machinery / computers | **$63.83 B** | **39.6 %** |
| **85** | Electrical machinery | **$19.59 B** | **12.1 %** |
| 98 | Special imports (Ch98) | $10.89 B | 6.8 % |
| 87 | Motor vehicles | $7.28 B | 4.5 % |
| 73 | Steel articles | $5.68 B | 3.5 % |
| 27 | Mineral fuels | $4.80 B | 3.0 % |
| 72 | Iron & steel | $4.57 B | 2.8 % |
| 94 | Furniture | $3.73 B | 2.3 % |
| 90 | Optical / medical | $3.68 B | 2.3 % |
| 71 | Precious metals | $2.47 B | 1.5 % |

**Chapters 84 + 85 alone are 51.7 % of all BUG-LIKELY over-$.** Both are heavy in ITA-covered products (computers, semiconductors, telecom equipment). This is consistent with the rate_prov-19 / 10 dominance at the rate-provision axis — the same products from a different angle.

Chapter 98 ($10.9 B, 6.8 %) at rank 3 is on its face suspicious: HS Chapter 98 is itself the U.S. special-imports chapter (American goods returned, non-commercial, etc.) that is almost always duty-free. Tracker over-statement on Ch98 lines suggests the tracker is applying chapter-99 surcharges to Ch98 imports without recognizing the Ch98 exemption.

## By country (BUG-LIKELY top 10, with names)

| Rank | Country | Partner group | Cells | Over-$ | Share |
|---:|---|---|---:|---:|---:|
| 1 | China | China | 119,268 | **$30.28 B** | 18.8 % |
| 2 | Taiwan | ROW | 33,274 | **$26.19 B** | 16.2 % |
| 3 | Mexico | Mexico | 34,053 | $25.85 B | 16.0 % |
| 4 | Canada | Canada | 41,800 | $21.62 B | 13.4 % |
| 5 | Vietnam | ROW | 46,384 | $11.43 B | 7.1 % |
| 6 | India | ROW | 60,623 | $9.38 B | 5.8 % |
| 7 | Thailand | ROW | 24,252 | $7.07 B | 4.4 % |
| 8 | Germany | EU | 53,205 | $3.35 B | 2.1 % |
| 9 | Japan | Japan | 42,902 | $3.25 B | 2.0 % |
| 10 | Brazil | ROW | 12,486 | $2.48 B | 1.5 % |
| 11 | South Korea | S. Korea | 22,657 | $1.93 B | 1.2 % |

The top 4 (China, Taiwan, Mexico, Canada) at $104 B = 64.4 % of BUG-LIKELY is the same set of countries that dominates total U.S. imports of HS84/85 — these are the major sources of computers, telecom equipment, and semiconductors. The Mexico / Canada signal is interesting given that USMCA already exempts much of their imports; the BUG-LIKELY ranking is **after** filtering out `usmca`-channel entries, so this is genuinely tracker over-rate on non-USMCA-claimed CA/MX entries.

## By first-over revision

| Revision | Cells first-over | First-over $ | Share |
|---|---:|---:|---:|
| **rev_2** | 22,313 | **$8.37 B** | **41.7 %** |
| **rev_6** | 62,289 | **$5.46 B** | **27.2 %** |
| basic | 31,337 | $2.61 B | 13.0 % |
| 2026_basic | 6,859 | $1.01 B | 5.0 % |
| rev_3 | 16,359 | $0.77 B | 3.8 % |
| rev_17 | 25,278 | $0.74 B | 3.7 % |
| 2026_rev_2 | 9,622 | $0.49 B | 2.4 % |

**rev_2 + rev_6 together account for 68.9 %** of cells first over-stating. rev_2 (Feb 2025, fentanyl + early reciprocal additions) and rev_6 (Apr 2025, Liberation Day Phase 1 reciprocal rollout) are exactly the revisions where authorities started landing on broad chapter ranges. The over-statement signal here suggests that whatever applied those new authorities to HS Ch 84/85 did not also recognize the ITA / Ch98 exemptions on those products.

This rev_2 / rev_6 finding mirrors the trackermiss diagnosis ("rev_6 is the locus where the gap was originally introduced"). Same revisions, opposite direction of error.

## Top cells preview

The top 14 cells by over-$ are dominated by a single HS10:

| Rank | HS10 | Description | Country | ym | Tracker rate | Imports | Census duty | Over-$ | Top rate_prov |
|---:|---|---|---|---|---:|---:|---:|---:|---|
| 1 | 8471.50.01.50 | Other digital ADPM | Taiwan | 2026-02 | 25.00 % | $11.86 B | $1.8 M | $2.96 B | 19 (99.8 %) |
| 2 | 8471.50.01.50 | " | Taiwan | 2025-12 | 23.76 % | $10.46 B | $0.8 M | $2.48 B | 19 (99.6 %) |
| 3 | 8471.50.01.50 | " | Taiwan | 2026-01 | 24.40 % | $9.74 B | $0 | $2.38 B | 19 (99.7 %) |
| 4 | 8471.50.01.50 | " | Taiwan | 2025-11 | 23.76 % | $9.37 B | $0 | $2.23 B | 19 (99.9 %) |
| 5 | 8471.50.01.50 | " | Taiwan | 2025-07 | 23.76 % | $8.94 B | $2.0 M | $2.12 B | 19 (99.5 %) |
| 8 | 8471.50.01.50 | " | Mexico | 2025-05 | 23.76 % | $6.85 B | $0 | $1.63 B | 10 (99.9 %) |
| 10 | 8471.50.01.50 | " | Mexico | 2025-06 | 23.76 % | $6.58 B | $0 | $1.56 B | 19 (94.0 %) |
| 12 | 8471.50.01.50 | " | Mexico | 2025-03 | 25.00 % | $5.63 B | $0 | $1.41 B | 10 (99.5 %) |
| 13 | 8471.50.01.50 | " | Mexico | 2025-04 | 24.18 % | $5.69 B | $0 | $1.38 B | 10 (99.1 %) |

**HS10 8471.50.01.50 alone accounts for ~$20 B of over-statement** across nine top-15 cells, on imports from Taiwan, Mexico, and Canada. This is "other digital automatic data-processing machines" — a core ITA-covered product. **99 %+ of import value is declared under rate_prov 10 or 19 (duty_free)**, which means importers are correctly claiming the ITA exemption (9903.01.32) at the entry level, but the tracker is applying the full reciprocal rate (~24–25 %) to these cells.

This is the smoking-gun signal for an ITA / Annex II coverage gap on chapter 84 computer products. It is structurally identical to the trackermiss Round 3 finding ("possible over-expansion in `expand_ieepa_exempt.R`"), but in the opposite direction: there, ITA-related HTS10s pulled into the exempt list were *over*-exempting (zero rate when full rate should apply); here, ITA-covered HTS10s **not** pulled into the exempt list are being *under*-exempted (full rate when zero rate should apply).

A tighter, more accurate `ieepa_exempt_products.csv` should reduce both signals simultaneously: removing over-broad inclusions reduces trackermiss bleed-through, and adding currently-missing legitimate inclusions reduces this trackerover signal.

---

# Suggested actions

## Action 1 — `expand_ieepa_exempt.R` audit, second direction (highest priority)

**Scope**: $80–110 B of BUG-LIKELY over-statement (HS84 + HS85 combined, weighted toward duty_free rate_prov).

The trackermiss Round 3 conclusion called for an audit of `expand_ieepa_exempt.R` against the literal Annex II HTS list to remove over-broad inclusions. This trackerover finding adds the second half of that audit: **identify ITA / Annex II / Ch98 / Berman HTS10s that are missing from the exempt list and should be added**. The HTS10 8471.50.01.50 family is a natural starting point — confirm this code is on the literal Annex II / ITA list, then sweep its HS6 family (8471.50, 8471.80, 8473.30) and adjacent ITA-covered headings.

A single audit pass over the exempt-list expansion logic addresses both directions of error, scoped to the same chapter families (84, 85, 90).

## Action 2 — Chapter 98 over-application audit (~$11 B, BUG-LIKELY)

**Scope**: $10.89 B in HS2 chapter 98.

HS Chapter 98 is the U.S. special-imports chapter (American goods returned, non-commercial, etc.) — almost always duty-free by HTS structure. Trackerover on Ch98 lines suggests the tracker is layering Chapter 99 surcharges on top of Ch98 imports without recognizing the Ch98 exemption. Likely fix: ensure Ch98 products are universally treated as exempt from chapter-99 surcharges (analogous to the Annex II treatment but at the HTS-chapter level).

Note: per project memory, `expand_ieepa_exempt.R` already includes Ch98 (+101 entries from Fix 4-5). The remaining Ch98 over-statement implies either (a) some Ch98 HTS10s are not in the +101, or (b) Ch98 is being correctly added to the IEEPA exempt list but Section 232 / 301 / 122 are not also applying the exemption.

## Action 3 — Ch99 dutiable rate parsing audit (~$42 B)

**Scope**: $42.2 B BUG-LIKELY in rate_prov 69/79.

These are entries where importers filed a Ch99 dutiable line and paid that line's rate, but the tracker over-states. Two candidate causes:
- **Wrong rate** parsed from a Ch99 entry (e.g., picked the wrong sub-line's rate).
- **Stacking error**: tracker is summing two authorities the importer applied only one of.

The `tracker_over_by_country` file shows this signal concentrated in China, Mexico, Canada, Vietnam, and India. The China bucket ($30 B) overlaps with the universe of products subject to multiple stackable authorities (IEEPA recip + 232 + 301 + fent). For a starting point: spot-check the top 25 cells in `tracker_over_top_cells.csv` filtered to `rp_top1_chan == "ch99_dutiable"` against tracker rate decomposition and the IMDB-declared 9903.xx code (when available).

## Action 4 — MFN-dutiable over-rate (~$8 B)

**Scope**: $8.2 B BUG-LIKELY in rate_prov 61/70.

Lower priority. These are entries the importer filed under an MFN dutiable line (no preference, no Ch99 surcharge), paid the MFN rate, but the tracker rate is higher. Likely cause: tracker is applying a Section 232 / 301 / 122 layer that the importer's filing does not include — possibly because the filing uses a different HTS subline that is not on the affected products list. Lower yield than Actions 1–3 but worth a check after the bigger fixes land.

## Action 5 — USMCA share calibration (~$43 B, LEGIT, **not a rate-parsing bug**)

**Scope**: $43.3 B LEGIT-channel over-statement on USMCA-claimed CA/MX entries.

Outside the actionable rate-parsing surface, but worth flagging: the LEGIT-USMCA bucket of $43 B over 14 months suggests the tracker's monthly USMCA-share inputs are systematically lower than realized claim shares for some HS10×country pairs. This is the same direction as the `tariff-etr-eval` counterfactual ladder's "USMCA surge" channel (S1 → S2). A drill-down by HS6×country×month, comparing tracker monthly shares to IMDB-derived claim shares, would identify which pairs need share refresh.

---

## Summary table

| Action | Channels | $ scope | Suggested fix |
|---|---|---:|---|
| **1. ITA / Annex II inclusion audit** (chs 84/85) | duty_free | ~$80–110 B | Add missing ITA HTS10s to `ieepa_exempt_products.csv`; tighten over-broad inclusions same pass |
| **2. Chapter 98 over-application** | duty_free | $10.9 B | Ensure Ch98 universally exempt from Ch99 surcharges across IEEPA / 232 / 301 / 122 paths |
| **3. Ch99 rate parsing / stacking** | ch99_dutiable | $42.2 B | Spot-check top-25 ch99_dutiable cells; verify rate selection and stacking |
| **4. MFN-dutiable over-rate** | mfn_dutiable | $8.2 B | Audit 232 / 301 / 122 product-list scope for chs 84/85 outside core lists |
| 5. USMCA share calibration (not a parsing bug) | usmca (LEGIT) | $43.3 B | Refresh monthly DataWeb USMCA shares for high-impact HS10×country pairs |
| **Total BUG-LIKELY** | | **$161.3 B** | |

---

## Caveats and known biases

- **Over-statement is computed at the entry grain**, then aggregated. The cell-level over-statement is the sum of entry-level over-statements within the cell. This correctly attributes the gap to the channel responsible — a USMCA-claimed entry in a mostly-MFN cell shows up as `usmca` (LEGIT), not as a bug.
- **`rate_usmca_monthly` is in decimal** (e.g., 0.25 = 25%), assumed in the over-statement calculation. The top-cell preview confirms this — cells at "25 %" show rates of 0.25 in the underlying data.
- **`con_val_mo`** in IMDB detail is consumption value (the standard ad-valorem denominator). For ad-valorem authorities the over-statement is well-defined; for specific or compound duties the entry-level statutory_duty is an approximation against the Census-collected duty.
- **`pref_channel` priority**: preference codes (`cty_subco` = S, S+, KR, A, A+, etc.) take precedence over rate-provision codes. A row tagged `usmca` by `cty_subco` stays `usmca` even if its `rate_prov` would otherwise classify it as `duty_free`. This avoids double-counting USMCA-claimed entries as duty-free.
- **The BUG-LIKELY filter is opinionated**. Some `mfn_dutiable` over-statement may reflect data-quality issues in IMDB (e.g., rate_prov mismatch with HS10) rather than tracker bugs. The Round 1 ranking is a starting point; cells should be confirmed against tracker rate decomposition before a fix lands.
- **Universe coverage**: `merged_analysis.dta` is the IMDB monthly universe. Cells with positive monthly trade are included; cells with zero monthly trade in a given month are excluded. The diagnostic does not claim coverage of products outside this universe.

## Reproducing this diagnostic

```bash
# In tariff-etr-eval/
do 00_etr_eval.do                          # produces all working/.dta files
do code/05b_tracker_over_diagnostic.do     # emits the 7 CSVs to results/tables/
```

Round 1 outputs are dated 2026-04-28. We can rerun this against fresh tracker outputs after every refresh; happy to share updated files on request, or wire the diagnostic into a periodic task on the tracker side.

---

## Cross-link with `tracker_miss_report.md`

The two reports are complementary. After Round 3 of the trackermiss report concluded that the largest missing-rate signal was structurally driven by importer non-claim and possibly over-expansion of `expand_ieepa_exempt.R`, this trackerover report finds the **opposite** signal in the same code path: HS10s that should be on Annex II but aren't, with importers correctly claiming duty-free at the entry level.

| Report | Direction | Same code path | Suggested action |
|---|---|---|---|
| `tracker_miss_report.md` | Tracker rate too **low** (= 0) on Annex II-eligible products | `expand_ieepa_exempt.R` over-broad ITA / HTS8→10 inclusions | Tighten the exempt list (remove products not literally on Annex II) |
| `tracker_over_report.md` (this) | Tracker rate too **high** on Annex II-eligible products | `expand_ieepa_exempt.R` missing ITA / Ch98 inclusions | Expand the exempt list (add products literally on Annex II / ITA but currently missed) |

A single Annex II audit pass — comparing `ieepa_exempt_products.csv` to the literal Annex II / ITA / Ch98 / Berman text — addresses both directions.

---

## Contact

Questions, requests for additional cuts (e.g. by HS6 family, by specific country, by month-revision interactions), or pointers about what would be most useful in this format: please reach out to `tariff-etr-eval` maintainers.
