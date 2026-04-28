# Trackermiss Diagnostic — Handoff to `tariff-rate-tracker`

**Authored by**: `tariff-etr-eval` (John Iselin, Yale Budget Lab)
**First written**: 2026-04-27 (Round 1, against rev_6 production snapshots)
**Updated**: 2026-04-28 AM (Round 2, after Brazil / India / Section 201 fixes)
**Updated**: 2026-04-28 PM (Round 3, tracker-side code trace + legal-scope correction)
**Companion**: `tracker_over_report.md` — opposite-direction diagnostic (tracker rate too high; first written 2026-04-28). The two reports together bracket the rate-parsing accuracy surface from both directions.

This note describes a diagnostic we built against the tracker's production outputs to identify cases where **the tracker assigns a zero statutory rate but Census shows positive duties were collected**. It is intended as input for the tracker maintainer to localize parsing gaps, stacking bugs, and country-EO carve-out misses. We are not asking for any specific changes — we are providing data and asking you to evaluate.

The report has four parts:

1. **What "trackermiss" means + how the diagnostic is built** — methodology and outputs.
2. **Round 1 (pre-fix, 2026-04-27)** — the initial $14.30 B finding and what it pointed at: missing Brazil EO 14323, India EO 9903.01.84, and Section 201 application.
3. **Round 2 (post-fix, 2026-04-28 AM)** — the impact of the three fixes ($14.30 B → $12.23 B), and what's left in the residual gap. Includes a structured analysis of five remaining patterns with hypothesized causes.
4. **Round 3 (legal correction, 2026-04-28 PM)** — tracker-side code trace confirms the structural cause but research on EO text reverses Round 2's proposed fix. Annex II legally applies to Phase 2 and floor structures, so the residual is *not* a tracker bug under the stated legal interpretation. Revised actionable list.

Round 1 and Round 2 are preserved as-written so the original signals are auditable; Round 3 is the current actionable analysis.

---

## What "trackermiss" means here

We define a *trackermiss* cell as an `(HS10, country, month)` triple where:

```
tracker rate_usmca_monthly == 0   AND   Census cal_dut_mo > 0
```

That is: the tracker's monthly-USMCA-adjusted statutory rate (from `data/timeseries/usmca_monthly/`) is exactly zero in that revision, but the Census IMDB bulk file shows U.S. Customs collected positive duty on the same `(HS10, country, month)` cell.

The criterion is the same one used in Section D5 of `code/02_etr_analysis.do` (the `cmp_2x2_*` outputs). This report drills into one of those four buckets — the `trackermiss` cell — with `rate_prov` context that the existing 2×2 doesn't carry, plus per-country and per-revision breakdowns.

## Pipeline

```
Census IMDB bulk (HS10 × cty × district × rate_prov × month)
  ├─→ aggregate to (HS10, cty, ym, rate_prov) → rp_detail
  └─→ aggregate to (HS10, cty, ym)             → cell-level cal_dut_mo

tariff-rate-tracker production snapshots (h2avg + usmca_monthly scenarios)
  └─→ merged_analysis.dta carries rate_usmca_monthly per (HS10, cty, ym)

Inner-join trackermiss cells (rate_usmca_monthly == 0, cal_dut_mo > 0)
with rp_detail
  → 6 diagnostic CSVs
```

The Stata script that builds these outputs lives at `code/05a_tracker_miss_diagnostic.do` in this repo.

## Files (in `results/tables/`)

| File | Contents | Most useful for |
|---|---|---|
| **`tracker_miss_by_rate_prov.csv`** | All `rate_prov` codes ranked by trackermiss $ | Single most diagnostic file — tells you which IMDB rate-provision codes carry the missing duty |
| `tracker_miss_top_cells.csv` | Top 200 `(HS10, cty, ym)` cells by $ duty, with top-3 `rate_prov` per cell + share | Click-and-fix worst-offenders |
| `tracker_miss_by_hs2.csv` | HS2 chapter ranking | Localizes to product families |
| `tracker_miss_by_country.csv` | Partner-group ranking (8 buckets) | Localizes to country / authority |
| `tracker_miss_by_country_detail.csv` | Top 50 individual countries with names (joined from tracker's `daily_by_country.csv` lookup) | Resolves which countries inside ROW dominate |
| `tracker_miss_by_revision.csv` | The HTS revision in which each `(HS10, cty)` first went trackermiss | Localizes to a specific tracker code change |

All six are plain CSVs; the `top_cells` file is the largest at ~250 KB; the rest are < 10 KB each. The Round 1 outputs are preserved alongside as `*_2026-04-27.csv` for diff purposes.

---

# Round 1 — Pre-fix diagnostic (2026-04-27)

Run against the original rev_6 of 2026 production snapshots, before any fixes were made.

**Total trackermiss**: ~$14.30 B in Census duties across the analysis window (Jan 2025 – Feb 2026), spread over ~132 K `(HS10, cty, ym)` cells.

### By `rate_prov` (the most diagnostic axis)

| `rate_prov` | $ duty | share | rows |
|---|---:|---:|---:|
| **69** (Ch99 dutiable) | $13.82 B | **96.7 %** | 119,438 |
| 61 (MFN dutiable) | $0.47 B | 3.3 % | 15,439 |
| 64 (other MFN) | < $0.01 B | 0.0 % | 34 |
| (others, all $0 trackermiss) | — | — | — |

Almost all trackermiss is in `rate_prov = 69` — entries that **importers themselves filed under Chapter 99** with positive duty, yet the tracker's monthly-USMCA rate is exactly zero on those cells. The IMDB rate_prov code does not pin down *which* specific 9903.xx authority each entry was filed under (that detail is not aggregated into IMDB), but it does confirm the importer's filing classification was a Chapter 99 dutiable line.

### By partner group

| Partner | $ duty | share | cells |
|---|---:|---:|---:|
| **ROW** | $11.16 B | **78.1 %** | 96,999 |
| EU | $1.24 B | 8.7 % | 15,724 |
| Japan | $0.84 B | 5.9 % | 6,387 |
| S. Korea | $0.42 B | 2.9 % | 3,858 |
| UK | $0.36 B | 2.5 % | 5,535 |
| Mexico | $0.16 B | 1.1 % | 1,314 |
| China | $0.06 B | 0.4 % | 1,010 |
| Canada | $0.05 B | 0.3 % | 1,470 |

ROW dominates at 78 %. CA + MX combined are 1.4 %, which weakens any "USMCA-saturation" hypothesis (i.e. the trackermiss criterion artificially zeroing rates from CA/MX cells with a 100 % USMCA claim share).

### By HS2 chapter (top 5)

| HS2 | $ duty | share |
|---|---:|---:|
| 85 (electrical machinery) | $5.13 B | 35.9 % |
| 84 (machinery / computers) | $3.22 B | 22.6 % |
| 90 (precision instruments) | $1.16 B | 8.1 % |
| 09 (coffee, tea, spices) | $0.89 B | 6.2 % |
| 91 (clocks / watches) | $0.83 B | 5.8 % |

Chapters 84/85 are 58 % of trackermiss.

### By first-miss revision

| Revision | First-miss $ | Share |
|---|---:|---:|
| **rev_6** | $462 M | **47.4 %** |
| rev_13 | $154 M | 15.8 % |
| basic | $113 M | 11.6 % |
| rev_17 | $87 M | 9.0 % |
| rev_3 | $53 M | 5.4 % |
| rev_15 | $32 M | 3.3 % |

47 % of cells first went trackermiss at **rev_6** — mid-2025, around the IEEPA Phase 1 reciprocal rollout.

### Top cells preview (Round 1)

| Rank | HS10 | Country | ym | $ duty | Implied rate | Top `rate_prov` |
|---:|---|---|---|---:|---:|---|
| 1 | 8518.30.20.00 (mics / headphones) | Vietnam (5520) | 2025-09 | $84.6 M | 14.92 % | 69 |
| 2 | 8518.30.20.00 | Vietnam (5520) | 2025-12 | $77.8 M | 19.65 % | 69 |
| 3 | 8541.43.00.10 (PV cells) | Indonesia (5600) | 2025-11 | $66.1 M | 18.96 % | 69 |
| 4 | 0901.11.00.25 (coffee) | **Brazil (3510)** | 2025-10 | $54.9 M | **49.97 %** | 69 |
| 5 | 8517.13.00.00 (smartphones) | **India (5330)** | 2025-12 | $52.1 M | 2.20 % | 69 |

The rank-4 cell was the smoking gun for the missing Brazil EO: 49.97 % matches IEEPA Phase 2 reciprocal +10 % (9903.02.09) on top of EO 14323 +40 % (9903.01.77) almost exactly. The rank-5 cell is the same pattern for India's +25 % country EO (9903.01.84) on Annex II products.

### Country detail (top 10, with country names) — Round 1

| Rank | Country | Partner group | $ duty | Share |
|---:|---|---|---:|---:|
| 1 | Vietnam | ROW | $1.78 B | 12.45 % |
| 2 | **India** | ROW | **$1.07 B** | **7.46 %** |
| 3 | Switzerland | ROW | $997 M | 6.98 % |
| 4 | Thailand | ROW | $902 M | 6.31 % |
| 5 | Germany | EU | $857 M | 6.00 % |
| 6 | Japan | Japan | $844 M | 5.91 % |
| 7 | Indonesia | ROW | $763 M | 5.34 % |
| 8 | Taiwan | ROW | $688 M | 4.82 % |
| 9 | Malaysia | ROW | $601 M | 4.21 % |
| 10 | **Brazil** | ROW | **$531 M** | 3.72 % |

### Round 1 conclusions

Three clear stories emerged:

- **India** ($1.07 B) and **Brazil** ($531 M) at ranks 2 and 10 — both with implied rates that matched their respective country EOs almost exactly. EO 9903.01.84 (India, +25 %) and EO 14323 / 9903.01.77 (Brazil, +40 %) appeared not to be in the tracker's authority list at all.
- **Section 201** (washing machines, solar PV cells) — implied by the rank-3 Indonesia PV-cells cell at 19 %.
- A broader, more diffuse pattern across **non-FTA Asia and EU** that wasn't tied to any single missing authority.

The first three were addressed by the tracker maintainer's afternoon rebuild on 2026-04-27 (snapshots dated 17:16–17:37, scenarios + daily ETRs rebuilt overnight through 23:16). Round 2 measures the result.

---

# Round 2 — Post-fix re-evaluation (2026-04-28)

Run against the rebuilt tracker outputs reflecting the Brazil EO 14323, India EO 9903.01.84, and Section 201 application fixes.

## The fixes worked, in aggregate

**Trackermiss duties**: $14.30 B → **$12.23 B**, a drop of **−$2.07 B (−14.5 %)**.

**Trackermiss cells**: ~132 K → 128.7 K (−3 %).

The cell-count change is tiny relative to the dollar change because the fixes targeted a small number of high-value cells (e.g. 0901 from Brazil, 8541.43 from Indonesia, 8517.13 from India) rather than broad swaths of small-value cells.

## Where the drop concentrated — by country

| Country | Pre-fix | Post-fix | Δ | % drop |
|---|---:|---:|---:|---:|
| **India** | $1,065 M | **$186 M** | **−$879 M** | **−83 %** |
| Indonesia | $763 M | $381 M | −$382 M | −50 % |
| **Brazil** | $531 M | $300 M | −$231 M | −44 % |
| S. Korea | $417 M | $353 M | −$64 M | −15 % |
| Vietnam | $1,779 M | $1,727 M | −$52 M | −3 % |
| Thailand | $902 M | $833 M | −$70 M | −8 % |
| Malaysia | $601 M | $545 M | −$56 M | −9 % |
| Switzerland, Germany, Japan, UK | (effectively unchanged) | | | |

India alone moved from rank #2 ($1.07 B) to rank #16 ($186 M). India + Brazil + Indonesia collectively dropped **$1.49 B = 72 % of the total $2.07 B reduction**.

The Indonesia drop (−$382 M) is larger than expected from Section 201 alone; some of it is likely the Section 232 / IEEPA Phase 2 stacking around PV cells being more correctly handled by the recalculation.

## Where the drop concentrated — by `rate_prov`

| `rate_prov` | Pre-fix | Post-fix | Δ |
|---|---:|---:|---:|
| **69** (Ch99 dutiable) | $13.82 B | **$11.76 B** | **−$2.06 B (−14.9 %)** |
| 61 (MFN dutiable) | $471 M | $469 M | unchanged |
| 64 (other MFN) | < $1 M | < $1 M | unchanged |

99.4 % of the drop is in `rate_prov = 69`, which is exactly where the Brazil/India/Section 201 fixes should land (those are all Chapter 99 authorities). The MFN-dutiable bucket (`rate_prov = 61`) at $469 M did **not** move at all — that bucket contains specific-duty AVE failures and AD/CVD, neither addressed by the three fixes.

## Where the drop concentrated — by HS2 chapter

| HS2 | Pre-fix | Post-fix | Δ | Likely driver |
|---|---:|---:|---:|---|
| 85 (electrical) | $5.13 B | $3.82 B | **−$1.32 B (−26 %)** | Indonesia PV cells (Section 201), India smartphones |
| 84 (machinery) | $3.22 B | $2.97 B | −$255 M (−8 %) | India machinery |
| 09 (coffee) | $886 M | $681 M | −$205 M (−23 %) | Brazil coffee (EO 14323) |
| 90 (precision) | $1.16 B | $1.12 B | −$40 M | (small) |

Chapter 85 ($1.32 B) and chapter 09 ($205 M) drops map directly to the Round 1 smoking guns. Chapter 90 (Switzerland-heavy) didn't move — consistent with the Switzerland framework being a separate issue.

---

# What's left — five patterns in the residual $12.23 B

After the Round 2 fixes, the remaining gap is no longer dominated by a small number of obvious missing authorities. It has a more structural shape: five distinct patterns, each with a different likely cause and a different scale.

> **Round 3 update**: the patterns below were the working hypotheses as of Round 2 AM. A subsequent tracker-side code trace + legal-scope research (Round 3, below) confirmed the structural cause of Patterns 1 and 3 but reversed the proposed fix. See "Round 3 — Legal-scope correction" further down for the revised diagnosis and the updated summary table.

## Pattern 1 — IEEPA Phase 2 reciprocal coverage gaps (~$5–7 B)

**The largest remaining signal.** Look at the recurring top cells in the post-fix data:

| HS10 | Product | From | Implied rate | Country's Phase 2 rate |
|---|---|---|---:|---:|
| 8518.30.20.00 | mics / headphones | Vietnam | 15–20 % | +20 % |
| 1511.90.00.00 | palm oil | Indonesia | 18 % | +19 % |
| 8411.91.90.85 | turbine parts | France | 4–7 % | +15 % w/ floor |
| 0901.21.00.20 | roasted coffee | Switzerland | 36–38 % | floor structure |
| 0901.11.00.25 | unroasted coffee | Colombia | 10 % | +10 % universal floor |

The **implied Census rates closely track each country's Phase 2 reciprocal rate**. The Vietnam 8518.30 cell appears at ranks 1, 2, 3, 4, 5, 6, 9, 10, 18 in the post-fix top cells — every month from 2025-06 through 2026-02 — at a stable ~15–20 % implied rate that matches Vietnam's +20 % Phase 2. So importers *are* paying Phase 2; the tracker's `rate_usmca_monthly` is just zero on that (HS10, country) pair.

**Most plausible cause**: certain HS10s are silently excluded from the Phase 2 product application — either via the IEEPA exempt list (~4,325 HTS10s), via a country-EO product list, or via a stacking-side-effect that zeroes out Phase 2 when Section 232 partially applies.

**Affected countries** (Phase 2 reciprocal countries with no other major exemption mechanism): Vietnam ($1.73 B), Thailand ($833 M), Malaysia ($545 M), Taiwan ($683 M), Indonesia ($381 M residual), Philippines ($259 M), Colombia ($157 M). **Joint ~$4.6 B.**

**Suggested action**: a product-list audit on a handful of HS6 families (8518, 8411, 0901, 1511, 8517) would likely close 30–50 % of this. Equivalently, check whether 9903.01.43–.75 (Phase 1) and the Phase 2 country-EO 9903.02.xx families have complete product coverage on those HS6 lines.

## Pattern 2 — Switzerland 15 % floor not applied (~$1 B)

Switzerland is rank #2 in the post-fix data at $997 M (essentially unchanged from Round 1). Concentrated in HS Chapter 91 (clocks/watches, $829 M chapter total) and Chapter 90 (precision instruments, $1.12 B chapter total of which a substantial chunk is Swiss).

Per the project memory and tracker config: the **Swiss framework (EO 14346) carries `finalized: false` in `swiss_framework` config** with an expiry of March 31, 2026. If the tracker is treating the framework as inactive and not applying the 15 % floor to Swiss imports, this is the explanation.

**Suggested action**: a single config-flag change, then verify the floor is applied to Swiss watches/precision instruments as expected.

## Pattern 3 — EU / Japan / Korea floor structure leaking on MFN-zero products (~$2.5 B)

| Country | Trackermiss $ |
|---|---:|
| Germany | $857 M |
| Japan | $843 M |
| France | $444 M |
| Italy | $369 M |
| UK | $359 M |
| S. Korea | $353 M |
| Spain | $217 M |
| Netherlands | $158 M |

All have the **15 % floor structure** rather than a simple country surcharge. Their joint $2.6 B is consistent with the floor failing to apply to MFN-zero products: the implementation in step 6d may only "lift" rates that are already positive, leaving MFN-zero products from these countries at 0 %. Importers pay 15 % at the border (Census collects); tracker records 0.

**Suggested action**: confirm the floor logic in step 6d applies `max(country_rate, floor)` to all products from floor-structure countries, not only positive-base ones.

For S. Korea specifically: per memory, the +15 % KR floor was added at rev_32 (Nov 15, 2025). KR cells from before rev_32 are likely a different cause (Section 232 country-override interactions); KR cells at rev_32+ should now be at the floor — confirm they are.

## Pattern 4 — Specific-duty AVE failures (~$469 M, `rate_prov = 61`)

The `rate_prov = 61` bucket — $469 M, **unchanged across Round 2** — is **MFN-dutiable entries** the tracker scores at 0. For non-FTA partners, `rate_usmca_monthly = 0` on an MFN-dutiable line means the tracker's MFN base rate is 0 — but the entry actually paid duty. Diagnostic signature of a **specific-duty AVE failure**: the HTS10 has a "$X per kg" or compound duty, the tracker couldn't compute an ad-valorem equivalent (2024 unit value missing), so it scored 0.

The HS2 distribution corroborates: chapters 15 (fats/oils, $302 M), 18 (cocoa, $353 M), 19 (cereal preparations, $198 M), 20 (vegetable preparations, $155 M), 04 (dairy, $68 M), 28 (inorganic chemicals, $110 M) all have specific or compound duties on parts of their tariff lines.

**Suggested action**: audit HS10s in chapters 15, 18, 19, 20, 28 with specific duties + missing 2024 unit values. A fallback AVE method (e.g. average across the HS6 family, or use 2025 unit values when 2024 is missing) would close most of this.

## Pattern 5 — Country-specific residuals after Round 2 fixes (~$870 M)

After the Brazil / India / Section 201 fixes, residuals remain:

| Country | Pre | Post | Residual |
|---|---:|---:|---:|
| India | $1,065 M | $186 M | $186 M |
| Indonesia | $763 M | $381 M | $381 M |
| Brazil | $531 M | $300 M | $300 M |

These residuals are likely products **outside** the EO 14323 / 9903.01.84 / Section 201 product lists:

- **Brazil's $300 M** is concentrated in coffee (HS 09) at lower implied rates than the rank-4 Round 1 cell — suggesting these are products *not* covered by EO 14323's Annex II, paying just IEEPA Phase 2 +10 % rather than the full +50 % stack.
- **India's $186 M** includes smartphones (HS 8517) — possibly products on Annex II that the +25 % country EO logic doesn't fully cover, or a stacking nuance with Phase 2 reciprocal that the EO fix didn't address.
- **Indonesia's $381 M** is heavily PV-cell-adjacent (HS 84/85) — likely Section 232 derivative interactions or Phase 2 product-list incompleteness rather than the Section 201 fix.

**Suggested action**: spot-check the rank-1 cells from these three countries against the relevant Chapter 99 product lists; verify the EO product lists in the tracker config match the proclamation annexes.

---

# rev_6 persistence

51 % of first-miss-revision $ is still at **rev_6** (was 47 % pre-fix; the share *grew* slightly because rev_6 cells were less responsive to the fixes than later-revision cells).

| Revision | First-miss $ (post-fix) | Share |
|---|---:|---:|
| **rev_6** | $447.7 M | **51.3 %** |
| basic | $113.4 M | 13.0 % |
| rev_17 | $83.6 M | 9.6 % |
| rev_13 | $74.7 M | 8.6 % |
| rev_3 | $53.0 M | 6.1 % |
| rev_15 | $32.2 M | 3.7 % |

rev_6 is the locus where the gap was originally introduced (mid-2025, IEEPA Phase 1 reciprocal rollout). Whatever logic landed at rev_6 still has the largest unaddressed footprint and is the most likely place to find the cause of Pattern 1.

**Best single signal for the next round**: if Pattern 1 (Phase 2 product-list completeness) and Pattern 3 (15 % floor on MFN-zero products) are correctly addressed, rev_6 should drop from 51 % to well below 30 % of first-miss $. If it stays at 50 %+, the gaps are elsewhere and a more targeted audit per HS6 family is needed.

---

# Summary table

| Pattern | Likely $ | Status | Suggested fix |
|---|---:|---|---|
| **1. IEEPA Phase 2 reciprocal product-list / stacking gaps** | $5–7 B | Open | Audit Phase 2 / IEEPA exempt list / country-EO product lists for HS6 families 8518, 8411, 0901, 1511, 8517 |
| **2. Switzerland framework not applied (15 % floor)** | $1.0 B | Open | Set `swiss_framework.finalized: true` in tracker config (or finalize and verify) |
| **3. EU/Japan/Korea 15 % floor not lifting MFN-zero products** | $2–3 B | Open | Floor logic in step 6d should apply `max(country_rate, floor)` to all products, not only positive-base ones |
| **4. Specific-duty AVE failures (rate_prov 61)** | $469 M | Open | Audit HS10s in chapters 15, 18, 19, 20, 28; consider fallback AVE method |
| **5. Brazil/India/Indonesia residuals (post-Round 2)** | $870 M | Open | Verify EO product lists are complete; check stacking on 232+IEEPA for these countries |
| AD/CVD + genuinely outside HTS scope | unknown, < $500 M | Permanent | Cannot fix in tracker (out of scope) |
| **Total** | **~$12.23 B** | | |

| Pattern | Resolved | What we already validated |
|---|---:|---|
| **Brazil EO 14323 (9903.01.77, +40 %)** | $231 M | Round 2 fix landed |
| **India EO (9903.01.84, +25 %)** | $879 M | Round 2 fix landed |
| **Section 201 (washing machines, solar)** | ~$382 M (within Indonesia) | Round 2 fix landed |
| **Total resolved in Round 2** | **$2.07 B (−14.5 %)** | |

---

# Round 3 — Legal-scope correction and revised diagnosis (2026-04-28, PM)

After the Round 2 handoff, a tracker-side investigation traced the residual gap into the IEEPA exempt-list code path and confirmed the structural cause. Subsequent research on the underlying EO text **reverses Round 2's hypothesized fix** for Patterns 1 and 3.

## What the tracker code actually does

`src/06_calculate_rates.R:1015–1029` builds `rate_ieepa_recip` with a `case_when` whose surcharge branch is:

```r
ieepa_type == 'surcharge' ~
  if_else(is_universally_exempt, 0, ieepa_country_rate - country_eo_rate) +
  if_else(is_country_eo_exempt, 0, country_eo_rate),
ieepa_type == 'floor' & is_universally_exempt ~ 0,
ieepa_type == 'floor' ~ pmax(0, ieepa_country_rate - base_rate),
```

- `is_universally_exempt` (a product on `resources/ieepa_exempt_products.csv`, 4,326 HTS10s) zeros the surcharge portion that combines universal baseline + Phase 1 + Phase 2 country-specific.
- `is_universally_exempt` also zeros the floor entirely for floor-structure countries (EU/JP/KR/CHE/LIE).
- The country-EO branch uses a *separate* per-EO exempt list (`country_eo_exempt_products.csv`) and bypasses the universal flag.

This explains the Round 1 → Round 2 fix asymmetry exactly: Brazil and India fixes worked because they added country EOs (which bypass the universal exempt list). Vietnam, Thailand, Indonesia, Colombia, etc. lack country EOs, so their Phase 2 surcharge is zeroed by the universal Annex II list whenever the product appears on it.

All Round 2 spot-check cells are confirmed on the universal exempt list:

| HS10 | Product | Round 2 country | On `ieepa_exempt_products.csv` |
|---|---|---|---|
| 8518.30.20.00 | mics / headphones | Vietnam | line 3677 |
| 1511.90.00.00 | palm oil | Indonesia | line 534 |
| 8411.91.90.85 | turbine parts | France | line 3141 |
| 0901.11.00.25 | unroasted coffee | Brazil / Colombia | line 380 |
| 8541.43.00.10 | PV cells | Indonesia | line 3851 |
| 8517.13.00.00 | smartphones | India | line 3657 |

The architecture is exactly as Round 2 described — `is_universally_exempt` is a kill-switch on Phase 2 reciprocal and the floor structure. The question is whether that architecture is correct.

## What the EO text says

Annex II of EO 14257 (April 2, 2025) is a **single, evolving carve-out list**, claimed by importers via HTSUS **9903.01.32**. Per:

- **EO 14326 §3** (July 31, 2025): *"Excluding the changes set forth in subsections (a) through (d) of this section, the terms of Executive Order 14257, as amended, shall continue to apply."* This preserves Annex II across the Phase 2 reinstatement.
- **EO 14346** (September 5, 2025): further amends the *contents* of Annex II (adds chs 25, 26, 28, 29, 47, 71, 72, 75) but does not change its scope of application.
- **CBP CSMS #65829726** (Aug 7 reciprocal guidance): confirms 9903.01.32 as the single exemption code across the reciprocal authority.
- **EO 14326 floor language**: *"For a good of the European Union with a Column 1 Duty Rate that is less than 15 percent, the sum of its Column 1 Duty Rate and the additional ad valorem rate of duty pursuant to this order shall be 15 percent."* A 0% MFN good is subject to the full 15% reciprocal add-on **unless it is on Annex II**.

There is **no separate Phase 2 exemption list**. Annex II applies uniformly to:

1. Universal baseline (9903.01.25, +10%)
2. Phase 1 country-specific (9903.01.43–.75, when active)
3. Phase 2 country-specific (9903.02.xx)
4. 15% floor structure (EU / Japan / S. Korea / Switzerland / Liechtenstein)

Tariff-ETRs (Yale Budget Lab) uses the same scope. The tracker's current behavior matches both the EO text and the Tariff-ETRs methodology.

**Implication**: the Round 2 hypothesis ("the tracker should not apply Annex II to Phase 2 / floor structures") is *legally* incorrect. Census trackermiss on these cells is **not a tracker bug** under the stated legal interpretation. The tracker is producing the rate the EOs prescribe; Census is recording duties paid on entries that did not claim the exemption they were eligible for.

## What is actually causing the trackermiss signal

Three remaining candidates — only the second is genuinely actionable inside the tracker:

1. **Importer non-claim of 9903.01.32 (most likely, largest share).** Annex II is *eligibility*, not automatic. `rate_prov = 69` ("Ch99 dutiable") in IMDB means the entry was filed under a Ch99 dutiable code rather than 9903.01.32. Some non-zero share of legally-eligible imports pay duty because the importer didn't claim the exemption — a behavioral / utilization gap. Any model that assumes 100% take-up of Annex II will miss this; Tariff-ETRs presumably has the same gap vs. Census. **Not addressable on the tracker side without claim-rate data.**
2. **Over-broad expansion in `src/expand_ieepa_exempt.R` (genuinely actionable).** `ieepa_exempt_products.csv` (4,326 HTS10s) was built from four expansion sources: HTS8→10 (+1,993), Ch98 (+101), ITA prefixes (+59), Berman ch49/ch97 (Fixes 4-5). The ITA-prefix path in particular can pull in HTS10s not actually on Annex II at the proclamation level (ITA-Expansion goes broader than Annex II's electronics carve-out). High-suspicion candidates from the Round 2 list: 8518.30 (likely ITA-pulled), 8517.13, 8541.43. An audit of `expand_ieepa_exempt.R` against the literal Annex II HTS list would tighten the exempt list.
3. **Annex II amendments not fully reflected (low-yield).** EO 14346 (Sep 5, 2025) added chs 25, 26, 28, 29, 47, 71, 72, 75 to Annex II. Round 2 trackermiss is concentrated in chs 84, 85, 90, 91, 09, 11 — *not* the new chapters — so this is unlikely to explain Pattern 1. Worth confirming the Sep 5 update is reflected, but not high-yield.

## Pattern-by-pattern revision

| Round 2 pattern | Round 3 revision |
|---|---|
| **Pattern 1** ($5–7 B). "Phase 2 product-list / stacking gaps." Tracker bug. | Tracker behavior is legally correct. Signal is real, split between (a) importer 9903.01.32 non-claim — not addressable in tracker — and (b) possible over-expansion of `ieepa_exempt_products.csv` via ITA-prefix / HTS8→10 paths. **Action moves to auditing `expand_ieepa_exempt.R`**, not changing the case_when scope. |
| **Pattern 2** ($1.0 B). "Set `swiss_framework.finalized: true`." | Flipping the flag does NOT help in the analysis window. The flag only matters after the framework expiry (March 31, 2026) — outside Jan 2025 – Feb 2026. The window-active behavior already promotes Swiss surcharge → 15% floor. The Swiss residual is more likely (a) Swiss-specific 9903.02.82–.91 entries not yielding a general Swiss surcharge for non-exempt categories, leaving Swiss imports falling through to the 10% baseline; (b) Annex II zeroing chapter 90 ITA-eligible instruments — same root as Pattern 1. **Action**: trace `extract_ieepa_rates()` output for census_code = 4419 across revisions. |
| **Pattern 3** ($2.5 B). "Floor not applied to MFN-zero products." | The floor IS applied at step 2 (`pmax(0, floor − base_rate)` = 15% for MFN-zero). `is_universally_exempt` zeros it. Per EO 14326 floor language, Annex II goods *are* legally exempt from the floor. Same root cause as Pattern 1: importer non-claim + possible over-expansion. The step 6d `> 0` gate exists but is only relevant to the post-MFN-exemption recompute, not the original floor application. |
| **Pattern 4** ($469 M, AVE failures). | Unchanged. Different code path (specific-duty AVE, not IEEPA exempt). Still actionable: audit chs 15, 18, 19, 20, 28 with specific duties + missing 2024 unit values. |
| **Pattern 5** ($870 M, country residuals). | Brazil / Indonesia residuals likely also reflect non-claim + ITA-expansion bleed-through. India residual ($186 M) more likely a stacking nuance with Phase 2 reciprocal worth a separate look. |

## Revised actionable list

1. **`expand_ieepa_exempt.R` audit** *(tracker-side, real fix)*. Compare each of the 4,326 entries to the literal Annex II HTS list across EO 14257 + EO 14326 + EO 14346 amendments. Highest-suspicion entries: ITA-prefix expansion (~59) and HTS8→10 expansion (~1,993). Likely outcome: a smaller, tighter exempt list that closes some Pattern 1 / 3 gap *without* changing the architectural treatment.
2. **Quantify the importer non-claim ceiling** *(diagnostic-only)*. A `ieepa_exempt_scope: 'baseline_only'` config flag has been drafted with an explicit legal warning — **not for production**. Running the tracker once with this scope produces an upper bound on how much of Pattern 1 / 3 is *not* explained by the tracker's intended behavior. The difference between that upper bound and Census = importer non-claim share, which must then live in `tariff-etr-eval`'s four-tier decomposition rather than in the tracker.
3. **Switzerland trace** *(Pattern 2 follow-up)*. Read `extract_ieepa_rates()` output for CHE in pre-Nov-14 revisions; check whether 9903.02.82–.91 produces a general Swiss surcharge or only category-specific exemptions.
4. **Pattern 4 (AVE)** and **Pattern 5 (Indonesia)** unchanged from Round 2.

## Revised summary table

| Pattern | Likely $ | Revised diagnosis | Action |
|---|---:|---|---|
| **1. Annex II zeros Phase 2 surcharges** | $5–7 B | Tracker behavior is legally correct (EO 14326 §3, CBP CSMS #65829726). Cause split between importer 9903.01.32 non-claim and possible over-expansion in `expand_ieepa_exempt.R`. | Audit exempt-list expansion; quantify non-claim ceiling via diagnostic flag |
| **2. Switzerland** | $1.0 B | `finalized: true` does not help in window. Likely 9903.02.82–.91 parsing issue + Annex II zeroing ITA-eligible ch90 items. | Trace `extract_ieepa_rates()` output for CHE |
| **3. EU/JP/KR floor on MFN-zero** | $2.5 B | Same root as Pattern 1. Floor IS applied in step 2; Annex II zeros the result (legally correct). | Same as Pattern 1 |
| **4. AVE failures** | $469 M | Unchanged. Specific-duty parsing, not IEEPA. | Audit chs 15, 18, 19, 20, 28 |
| **5. Brazil/India/Indonesia residuals** | $870 M | Mix: non-claim + over-expansion + India stacking nuance | Spot-check |
| AD/CVD + outside HTS scope | <$500 M | Permanent | Out of scope |
| **Total** | **~$12.23 B** | | |

## Implications for `tariff-etr-eval`

The largest residual ($5–7 B Pattern 1, ~$2.5 B Pattern 3, parts of Pattern 5) is now best understood as an **importer 9903.01.32 non-claim channel** — eligible-but-not-claimed Annex II exemptions. This is exactly the kind of behavioral channel the four-tier decomposition is built to attribute: it sits between Tier 1 (statutory ETR with assumed-100%-claim Annex II) and Tier 3 (Census collected duty), and is conceptually sibling to the USMCA utilization channel already modeled in the counterfactual ladder.

A natural next step on the `tariff-etr-eval` side is to add an **Annex II claim-rate channel** to the decomposition, parallel to USMCA shares, sourced from IMDB rate_prov decomposition (count of 9903.01.32 vs. 9903.01.25/.43–.75/02.xx claims by HS6 × country × month). The tracker can support this by exposing per-product per-country statutory-vs-claimable rate split in its outputs.

Tracker-side patches drafted as of this round:

- `config/policy_params.yaml`: new `ieepa_exempt_scope: 'all'` flag (default = current; `'baseline_only'` = diagnostic with legal warning)
- `src/06_calculate_rates.R`: tags `country_ieepa` rows with `is_universal_baseline_country`; gates `is_universally_exempt` per scope
- Pending: `expand_ieepa_exempt.R` line-by-line audit against EO 14257 / 14326 / 14346 Annex II text

---

## Caveats and known biases (unchanged from Round 1)

- **`rate_usmca_monthly` criterion** can over-include cells where the underlying production statutory rate is positive but the realized USMCA claim share is modeled at 100 %, zeroing the cell. Given that USMCA partners are < 1.5 % of trackermiss $, the bias is small here. For a cleaner "tracker really missed the authority" set, a second pass with `total_rate == 0` (production / h2avg scenario, before USMCA-share adjustment) would isolate genuinely-missed authorities. We can produce that on request.
- **Implied rate** = `cal_dut_mo / con_val_mo`. Entry-level, pre-refund, pre-post-entry-adjustment. For ad-valorem tariffs the implied rate maps cleanly to the statutory rate; for specific or compound duties the implied AVE fluctuates with unit value.
- **`rate_prov`** is a 2-character IMDB classification (`69` = "Ch99 dutiable", `61` = "MFN dutiable", etc.) and does not give the specific 9903.xx code each entry was filed under. The diagnostic narrows to "filed under Chapter 99 with duty"; the specific authority is not directly recoverable from this aggregate.
- **Universe coverage**: `merged_analysis.dta` is the IMDB monthly universe (cells with positive monthly trade). Cells with imports in 2024 but no monthly trade in a given month are excluded — fine for the trackermiss criterion (which requires positive duties) but means the *base rate* of trackermiss is computed over an active subset.

## Reproducing this diagnostic

```bash
# In tariff-etr-eval/
do 00_etr_eval.do                          # produces all working/.dta files
do code/05a_tracker_miss_diagnostic.do     # emits the 6 CSVs to results/tables/
```

Round 1 outputs are preserved as `tracker_miss_*_2026-04-27.csv` for diff purposes. We can rerun this against fresh tracker outputs after every refresh; happy to share updated files on request, or wire the diagnostic into a periodic task on the tracker side.

---

## Contact

Questions, requests for additional cuts (e.g. by HS6 family, by specific country, by month-revision interactions), or pointers about what would be most useful in this format: please reach out to `tariff-etr-eval` maintainers.
