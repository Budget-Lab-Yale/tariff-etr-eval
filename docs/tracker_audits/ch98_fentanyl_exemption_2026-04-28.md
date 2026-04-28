# Ch98 exemption from IEEPA fentanyl

**Date**: 2026-04-28
**Triggered by**: `tracker_over_report.md` Round 1 chapter 98 finding (~$10.9 B)
**Status**: bug confirmed and patched

## Finding

Trackerover Round 1 ranked HS Chapter 98 third in BUG-LIKELY ($10.89 B). Top cells were Canada × HS 9801.00.10.66 and 9801.00.10.98 — "American goods returned" — at tracker rate 25 % pre-rev_17 and 40 % from rev_17 onward, with Census collection of $0.

Tracker-side trace:

- `data/timeseries/snapshot_rev_32.rds` for 9801.00.10.66 × Canada (1220):
  - `base_rate = 0`, `rate_232 = 0`, `rate_301 = 0`, `rate_ieepa_recip = 0`
  - **`rate_ieepa_fent = 0.40`** ← the 40 % is entirely Canada IEEPA fentanyl
- `ieepa_exempt_products.csv` line check: 9801.00.10.66 IS present (line in the 121 Ch98 exempt entries from `expand_ieepa_exempt.R` Fix 2).
- `06_calculate_rates.R:1175-1213` (the fentanyl application block): joins `general_fent` and `carveout_lookup` to set `rate_ieepa_fent`. **Never references `ieepa_exempt_products`.**

The tracker correctly excludes Ch98 from IEEPA reciprocal (Annex II / Annex A path zeros it via `is_universally_exempt`), but the fentanyl path skips that gate entirely. So Canada-origin US goods returned (9801) get charged 40 % IEEPA fentanyl in the tracker, while Census collects $0.

## Source authority

US Note 2(v)(i) (HTSUS Chapter 99, Subchapter III): Chapter 98 is exempt from IEEPA, except subheadings 9802.00.40, 9802.00.50, 9802.00.60, 9802.00.80. This applies across all IEEPA authorities — universal baseline, reciprocal, AND fentanyl. The original IEEPA fentanyl EOs (14193 Canada, 14194 China, 14195 Mexico — Feb 2025) reference standard customs procedure including the Ch98 carve-out.

`expand_ieepa_exempt.R` Fix 2 already encodes this with the 4 exceptions excluded; the resulting Ch98 entries in `ieepa_exempt_products.csv` should apply to fentanyl too.

## Scope of fix

Apply only the **Ch98 subset** of `ieepa_exempt_products.csv` to `rate_ieepa_fent`. Do not apply the full Annex II list, because US Note 2(v)(iii) (Annex II) lists only reciprocal-related ch99 codes (9903.01.25, .35, .39, .63, 9903.02.01–.73, etc.) — fentanyl codes (9903.01.01–.24) are not in that list. So Annex II / ITA / Berman exemptions do not legally extend to fentanyl, but the Ch98 carve-out under US Note 2(v)(i) does.

## Patch

`src/06_calculate_rates.R` — after the fentanyl application block (after line 1213, inside the `has_fentanyl` branch), add:

```r
# Apply Ch98 exemption (US Note 2(v)(i)) to fentanyl rate.
# Annex II (Note 2(v)(iii)) does NOT apply to fentanyl — only to reciprocal —
# so we filter the universal exempt list to Ch98 specifically. The 4 Ch98
# exceptions (9802.00.40/50/60/80) are already excluded from
# ieepa_exempt_products.csv by expand_ieepa_exempt.R Fix 2.
ch98_exempt_products <- ieepa_exempt_products[substr(ieepa_exempt_products, 1, 2) == '98']
if (length(ch98_exempt_products) > 0) {
  ch98_mask <- rates$hts10 %in% ch98_exempt_products
  n_zeroed <- sum(ch98_mask & rates$rate_ieepa_fent > 0)
  if (n_zeroed > 0) {
    rates$rate_ieepa_fent[ch98_mask] <- 0
    message('  Ch98 fentanyl exemption: zeroed rate_ieepa_fent for ', n_zeroed,
            ' product-country pairs')
  }
}
```

## Expected impact

| Metric | Pre-patch | Post-patch (estimate) |
|---|---|---|
| Trackerover BUG-LIKELY chapter 98 | $10.9 B | est. ~$1–3 B (residual on 9802.00.40/50/60/80 valuation-special subheadings, if any) |
| Total trackerover BUG-LIKELY | $161 B | est. $151–155 B |
| Tariff-ETRs gap (Feb 2026) | +1.67 pp | likely narrows by 0.05–0.20 pp |
| Census denominator effect | minor (Ch98 imports are a small slice) | minor |

The trackermiss diagnostic should not be affected (this is a one-direction fix — zeros a too-high rate, doesn't introduce any new positive rates).

## Caveats

- **§232 / §301 / §122 paths are not patched.** This audit only addresses fentanyl. If subsequent trackerover refreshes show Ch98 over-statement on §232 / §301 / §122 cells, those need their own patch. The current top-cell evidence points only at fentanyl.
- **The 4 Ch98 exceptions stay liable.** 9802.00.40/.50/.60/.80 are intentionally excluded from `ieepa_exempt_products.csv` and remain subject to fentanyl. Confirmed correct per the literal Note text.
- **Carve-out interaction.** Canada has fentanyl carve-outs at +10 % for energy/minerals (9903.01.13) and +10 % for potash (9903.01.15). Ch98 imports are not energy/minerals or potash, so carve-outs and Ch98 exemption don't overlap. No interaction risk.
- **USMCA share interaction.** Step 7 in `06_calculate_rates.R` scales `rate_ieepa_fent` by `(1 - usmca_share)` for CA/MX. Zeroing in this patch happens before step 7, so the zero stays zero through USMCA scaling. No interaction risk.
