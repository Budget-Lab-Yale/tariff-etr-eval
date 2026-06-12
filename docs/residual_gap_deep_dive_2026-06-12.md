# Residual-Gap Deep Dive — Handoff to `tariff-rate-tracker`

**Authored by**: `tariff-etr-eval` (John Iselin, Yale Budget Lab)
**Date**: 2026-06-12
**Against**: panel vintage `2026-06-11-17` (R pipeline, full S0–S4+T ladder run of 2026-06-12, SLURM job 14981609) — i.e. **after** the 2026-06-04 tracker fix pass (incl. `c471770`, 8471 auto-parts scoping) and all Round 1–3 fixes from `tracker_miss_report.md` / `tracker_over_report.md`.
**Companions**: `tracker_miss_report.md`, `tracker_over_report.md`, `tracker_audits/*` — patterns documented there are treated as *explained* and excluded; this note ranks what is still large and **unexplained** in the S3−S4 residual.

## Method

Residual channel = ladder tier S3 (statutory after all modeled preferences, `rate_all_pref`) minus S4 (Census collected), attributed at flow level: `res_usd = rate_all_pref × con_val_mo − cal_dut_mo` per (HS10, country, month). Flow sums reproduce the ladder's `gap_residual` to machine precision (sanity-checked).

Window: the April 2025 spike (7.8 pp; China shipping-lag + Geneva, documented) is excluded. The steady-state window **LATE = 2025-09 … 2026-03** carries **$23.2 B of residual on $1,898 B of imports (1.22 pp)**, running $2.7–4.5 B/month with an uptick to 1.50 pp in 2026-03. Within LATE, the patterns below account for roughly half of the dollars; the rest is diffuse (<$50 M per HS4×country over 7 months).

Reproduce: `Rscript scripts/residual_deep_dive.R` (+ `..._deep_dive2.R`, `..._deep_dive3.R`); cell-level extracts in `results/diagnostics/residual_*.csv`.

---

## Ranked findings

### 1. Section 232 pharmaceuticals: statutory applied, ~nothing collected (~$5.2 B in LATE; $779 M/mo and growing in 2026Q1)

Chapter 30 statutory ETR ramps 0.65 % (pre-Aug 2025) → 2.8 % (Aug) → 5.3 % (Sep) → 8.1 % (Feb 2026), while Census-collected stays **0.2–0.5 % throughout**. The signature cells are formulated dosage forms (3004.90.92.xx) at **exactly 25.0 % statutory and exactly 0.0 % collected**, persisting 4–7 consecutive months:

| Country | LATE res $ | stat | collected | max rate seen |
|---|---:|---:|---:|---:|
| Ireland | $0.98 B | 5.2 % | 0.03 % | 25 % |
| India | $0.90 B | 13.7 % | 0.10 % | 51 % |
| Switzerland | $0.76 B | 11.1 % | 0.03 % | 39 % |
| France | $0.49 B | 8.8 % | 0.12 % | 25 % |
| UK | $0.36 B | 12.3 % | 0.47 % | 25 % |
| Singapore | $0.34 B | 8.4 % | 0.01 % | 25 % |

This is now the **single largest unexplained residual block** and it is growing. The collections evidence says the pharma §232 duty is, in practice, almost never collected — consistent with the company-level carve-outs (US-manufacturing-commitment deals announced from Oct 2025 onward) and/or agreement ceilings zeroing pharma, none of which the tracker models. Structurally identical to the 8471 case: a legally-real authority whose *realized applicability* is ~0.

**Suggested action**: a pharma applicability share (per the `qualifying_share` precedent in `semi_qualifying_shares.csv`), calibrated by origin or by company-deal coverage; or an explicit effective-date / deal-exemption layer for the pharma §232. At current run-rate this single fix moves the statutory ETR more than any remaining item (~0.3 pp of the ~1.2 pp steady-state residual).

### 2. Section 232 steel/aluminum applied to upstream & scrap headings (~$2.5 B in LATE; $386 M/mo in 2026Q1)

Headings **7201 (pig iron), 7202 (ferroalloys), 7204 (ferrous scrap), 7602 (aluminum scrap)** show ~49–50 % statutory vs **0.2–8.5 % collected** — radically unlike genuine §232 mill/derivative headings (7308: 53 vs 29; 7326: 59 vs 43; 7601 primary aluminum: 49.9 vs 46.5, i.e. collected ≈ statutory). Concentrated: Canada scrap $939 M (49.9 % vs 0.1 %), Brazil pig iron $290 M (49.2 % vs 8.8 %), India ferroalloys $86 M (48.4 % vs 1.1 %).

Where 7601 collects at full rate, scrap and ferroalloys collect at ~zero — strongly suggesting these headings are **outside the operative §232 product scope** (or carry an exemption importers uniformly file) and the tracker is over-applying the 50 % metals rate to them. Same dual-use/list-membership failure mode as the 8471 auto-parts memo.

**Suggested action**: audit the §232 steel/aluminum product lists for 7201/7202/7204/7216/7602 against the proclamation annex text (incl. the Aug 2025 inclusions); apply per-heading applicability where membership is conditional.

### 3. Medical devices 9018–9022: the Nairobi Protocol channel (~$2.0 B in LATE; ~$300 M/mo)

Implants, orthopedics, hearing aids, and instruments from Ireland ($594 M in ch90 ROW cells; 9021 at 13.9 % vs 0.9 %), Costa Rica (9018: 13.7 % vs 4.9 %), Denmark (9021: 13.9 % vs 0.2 %), Singapore (9019/9021: 9.9 % vs 0.03–0.05 %), Switzerland (9021: 22.1 % vs 6.7 %), Germany (13.8 % vs 4.4 %).

These are 15 %-floor / reciprocal-rate countries; importers are paying ~zero. The likely vehicle is the **Nairobi Protocol secondary classification (9817.00.96, articles for the handicapped — duty-free, and CBP guidance exempts it from IEEPA reciprocal)**, which maps exactly onto implants/pacemakers/orthopedics/hearing aids but is invisible at the primary-HS10 level the tracker prices. This is a *distinct exemption channel* from Annex II (which the trackermiss Round 3 already covers) — Annex II non-claim produces duty *paid*; here duty is *not* paid.

**Suggested action**: model a Nairobi exemption share on the 9018–9022 family (IMDB `rate_prov` duty-free shares per HS10×country give the realized claim rate directly); alternatively flag these HS10s in an exemptions sidecar so the eval can move them from "residual" to a modeled preference channel.

### 4. Chapter 98 round 2: still leaking, now growing (~$1.1 B in LATE; $384 M/mo in 2026Q1)

The 2026-04-28 Ch98-fentanyl patch killed the 25–40 % cells, but 98xx lines still carry **1.2–2.1 % statutory vs 0.0 % collected**, spread across *all* partners (9801.00.10.xx US-goods-returned from Germany, Canada, Bahamas, Ireland, Italy, Switzerland, Mexico…), plus **9802.00.50.60 China at 25 % vs 2.9 %** (repairs/alterations — duty is legally owed on the *repair value only*, not full value) and 9817.00.50/.60 (agricultural-use machinery, 2.0–2.1 % vs ~0.1 %). Q1 2026 run-rate tripled vs late 2025 — something added rate to ch98 again in 2026 revisions.

**Suggested action**: extend the US Note 2(v)(i) exemption to *every* authority path (it was patched for fentanyl only); treat 9802 lines on a repair-value basis (or applicability ≈ 0.1); check what changed in 2026 revisions to triple the ch98 statutory load.

### 5. Canada gas/electricity and Mexico crude, Nov 2025–Feb 2026 (~$1.4 B, window-bounded)

From 2025-11 the tracker carries **10 % on Canadian natural gas (2711.21), 40 % on Canadian electricity (2716.00), 7.9 % on Mexican crude (2709)** — Census collects **exactly $0.00** on all three, every month. Peaks at $300 M/mo (Jan 2026); ends 2026-03 when the statutory drops back to zero (post-SCOTUS IEEPA unwind). Two distinct issues: (a) the 40 % electricity figure looks like a stacking error on its face (4× the 10 % Canadian-energy carve-out rate); (b) electricity and pipeline-gas imports largely do not generate conventional customs entries, so even a correct positive rate will never appear in collections — a *structural* non-collection the eval would otherwise misread as residual.

**Suggested action**: trace the Nov-2025 Canada surcharge application to energy HS codes; consider an explicit entry-coverage flag for 2716/2711 so statutory-vs-collected comparisons skip them.

### 6. Korea autos under-stated since Dec 2025 (−$127 M/mo, residual in the *opposite* direction)

8703 from Korea: Census collects a rock-steady **15.0 %** from Dec 2025 on, while tracker statutory is **10.1 %**. (Aug–Nov 2025 the mismatch ran the other way: stat 21.3 vs collected 25.0.) The tracker's Korea-agreement implementation appears to land ~5 pp below what CBP actually charges — possibly netting out the MFN base (2.5 %) or an offset that CBP doesn't apply. Mirror image in Japan 8703 for Feb–Mar 2026: stat 15.0 vs collected 12.5 → 9.6 — consistent with §232 import-adjustment offset credits reducing realized duty below the deal rate.

**Suggested action**: verify the Korea deal rate is implemented as a 15 % *total* (MFN-inclusive) rate; for Japan, the offset-credit mechanism may warrant an applicability haircut from 2026-02.

### 7. Smaller / contextual

- **China ch84/85 stacking** (batteries 8507.60, telecom 8517.62): still the top single cells ($430 M, $387 M LATE) but the aggregate is down to $113 M/mo with stat 31.1 vs collected 29.5 — the documented timing/FTZ/derivative-share explanation (ch99_dutiable audit) covers most of what remains. No new action.
- **Nov-14 food-exemption retroactivity**: beef/coffee/cocoa/banana collections kept arriving ~6 weeks *after* the exemption EO (0202: stat 0.3 %, collected 12.7 % in Dec 2025; ~$230 M total negative residual Nov–Dec) then stopped in Jan — an entry-lag artifact, useful for the eval's timing channel, not a tracker bug. Note 0202 stat pops back to 12 % in Feb–Mar 2026 with collections at 9.4 % (TRQ over-quota mix?) — low priority, watch.
- **Undervaluation overlap**: $1.97 B of LATE residual sits in flows the VMR classifier marks `B2_misreport_suspect` — behavioral undervaluation, belongs in the eval's compliance channel, not in the tracker.

---

## Summary table

| # | Area | LATE $ (2025-09…2026-03) | 2026Q1 run-rate | stat vs collected | Suggested tracker action |
|---|---|---:|---:|---|---|
| 1 | §232 pharma (ch30) | $5.2 B | $779 M/mo | 6.7 % vs 0.4 % | Applicability/deal-exemption share, per semi precedent |
| 2 | Steel/alu upstream+scrap (7201/02/04, 7602) | $2.5 B | $386 M/mo | 49 % vs 2.7 % | Product-scope audit vs proclamation annexes |
| 3 | Medical devices 9018–9022 (Nairobi 9817.00.96) | $2.0 B | $296 M/mo | 11 % vs 6 % | Model Nairobi claim share from IMDB rate_prov |
| 4 | Chapter 98 (round 2) | $1.1 B | $384 M/mo | 3.8 % vs 0.1 % | Exempt ch98 across all authorities; 9802 repair-value basis |
| 5 | CA gas/electricity, MX crude (Nov 25–Feb 26) | $1.4 B | $163 M/mo (ended 03/26) | 9–40 % vs 0.0 % | Trace Nov-25 energy application; entry-coverage flag |
| 6 | Korea autos (negative) | −$0.7 B | −$127 M/mo | 10.1 % vs 15.0 % | Korea deal rate MFN-inclusive check |
| — | China 84/85 stacking (documented) | $1.6 B | $113 M/mo | 31 % vs 29.5 % | none new |
| — | VMR B2 undervaluation (eval-side) | $2.0 B | — | — | n/a (compliance channel) |

Items 1–4 alone are ~$1.9 B/mo of the ~$3.4 B/mo steady-state residual; closing them would roughly halve the unexplained S3−S4 gap and (item 1 especially) bend its current upward trend.
