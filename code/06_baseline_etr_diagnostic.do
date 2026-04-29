* ==============================================================================
* 06_baseline_etr_diagnostic.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Diagnostic at 2024 trade weights, exposing four orthogonal gaps:
*            (a) USMCA-reconstruction methodology
*                  etr_full - s0_recon
*                  (same panel + weights, only difference is which baseline
*                  USMCA assumption is encoded in the rate column)
*            (b) Zero-rate-dropping effect
*                  etr_full - etr_nonzero
*                  (same rate, restricted to products with nonzero tracker
*                  total_rate -- tests how much zero-rate inclusion matters)
*            (c) Unmatched-product effect
*                  etr_full - etr_matched
*                  (same rate, restricted to products that matched the
*                  tracker snapshot -- tests universe-restriction effects)
*            (d) 2024-weights vs actual-monthly-weights effect
*                  etr_full - etr_tracker_daily
*                  (full 2024 universe in static weights vs the tracker's
*                  daily ETR collapsed to monthly via actual monthly weights)
*
*          By design this script does NOT assert on the gaps -- exposing them
*          is the entire point. Suppressing rate gaps with asserts here would
*          defeat the diagnostic purpose. Range-check warnings are still
*          appropriate at the input stage.
*
*          Universe: the full 2024 import-weight panel
*          ($working/weights_2024.dta, ~333k hs10 x cty_code pairs) crossed with
*          the analysis window. Different from merged_analysis.dta (which keeps
*          monthly-trade cells), so 06 builds its own panel.
*
*          Note: rate_2024 (the S0 reconstruction column) is built upstream in
*          01_etr_clean.do Section B7 and saved to $working/cf_usmca2024.dta;
*          we just merge it in here.
*
* Output:
*   $working/baseline_etr_diagnostic.dta
*   $tables/baseline_etr_diagnostic.csv
*   $figures/figure7_baseline_etr_diagnostic.png
* ==============================================================================

di as text _n "=========================================="
di as text "  06_baseline_etr_diagnostic"
di as text "==========================================" _n


* ======================================================================
* A. MONTH -> REVISION MAP
* ======================================================================

di as text "  [A] Month-revision crosswalk..."

tempfile month_rev_map
build_month_rev_map, saving(`month_rev_map')


* ======================================================================
* B. BUILD 2024-WEIGHT x MONTH PANEL, MERGE BOTH RATE COLUMNS
* ======================================================================
*
* Two rate columns on the same panel:
*   total_rate    tracker snapshot, baseline USMCA already applied
*   rate_2024     our S0-baseline reconstruction (from cf_usmca2024.dta)
* Both use 2024 baseline USMCA, so any difference between them is pure
* reconstruction methodology.

di as text "  [B] Building 2024 weights x months panel..."

use "$working/weights_2024.dta", clear
keep hs10 cty_code imports

local n_months = $end_ym - $start_ym + 1
expand `n_months'
bysort hs10 cty_code: gen int ym = $start_ym + _n - 1
format ym %tm

merge m:1 ym using `month_rev_map', keep(match master) nogenerate

** B1. Tracker snapshot total_rate (already has baseline USMCA applied)
merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) keepusing(total_rate usmca_eligible) ///
    gen(_merge_snap)

qui count if _merge_snap == 3
local n_match = r(N)
local match_rate = 100 * `n_match' / _N
di as text "      Tracker snapshot match: `n_match' of `=_N' (" ///
    string(`match_rate', "%4.1f") "%)"
if `match_rate' < 75 {
    di as error "WARNING: snapshot match rate below 75% — diagnostic suspect"
}

gen byte matched_snap = (_merge_snap == 3)
drop _merge_snap
replace total_rate = 0 if missing(total_rate)

** B2. cf_usmca2024 reconstruction rate (rate_2024) -- from 01 section B7
merge 1:1 hs10 cty_code ym using "$working/cf_usmca2024.dta", ///
    keep(match master) gen(_merge_recon)

qui count if _merge_recon == 3
local n_recon = r(N)
local recon_pct = 100 * `n_recon' / _N
di as text "      cf_usmca2024 match:     `n_recon' of `=_N' (" ///
    string(`recon_pct', "%4.1f") "%)"

drop _merge_recon
replace rate_2024 = 0 if missing(rate_2024)

gen byte is_nonzero = (total_rate > 0 & !missing(total_rate))

qui count
di as text "      Panel obs: " _N
qui count if matched_snap
di as text "      Matched to snapshot: " r(N)
qui count if is_nonzero
di as text "      Nonzero tracker rate: " r(N)

compress


* ======================================================================
* C. MONTHLY AGGREGATES — 4 SLICES
* ======================================================================
*
* All four use 2024 import weights. They differ in (universe, rate):
*   etr_full       full universe, total_rate  (tracker baseline)
*   etr_matched    matched-only,  total_rate
*   etr_nonzero    nonzero-only,  total_rate
*   s0_recon       full universe, rate_2024   (our S0 reconstruction)
*
* Diagnostic gaps:
*   etr_full - s0_recon      pure USMCA-reconstruction methodology
*   etr_full - etr_nonzero   zero-rate-dropping effect
*   etr_full - etr_matched   unmatched-product effect

di as text _n "  [C] Computing monthly ETR under 4 slice definitions..."

tempfile tier_full tier_matched tier_nonzero tier_recon

preserve
    compute_tier, ratevar(total_rate) weightvar(imports) ///
        outfile(`tier_full') outvar(etr_full) percent
restore

preserve
    keep if matched_snap
    compute_tier, ratevar(total_rate) weightvar(imports) ///
        outfile(`tier_matched') outvar(etr_matched) percent
restore

preserve
    keep if is_nonzero
    compute_tier, ratevar(total_rate) weightvar(imports) ///
        outfile(`tier_nonzero') outvar(etr_nonzero) percent
restore

preserve
    compute_tier, ratevar(rate_2024) weightvar(imports) ///
        outfile(`tier_recon') outvar(s0_recon) percent
restore


* ======================================================================
* D. BENCHMARKS: tracker daily (collapsed) + Tier 1 from 02 if present
* ======================================================================

di as text "  [D] Benchmarks..."

** Tracker's own daily ETR, collapsed to monthly (import-weighted, same
** universe the tracker uses — actual monthly imports, not 2024 weights).
** Flag any missing daily values that `collapse (mean)` would silently drop;
** a hole in the daily series would produce a biased monthly mean.
use "$working/tracker_daily.dta", clear
qui count if missing(weighted_etr)
if r(N) > 0 {
    di as error "WARNING: `=r(N)' missing daily weighted_etr values" ///
        " will be dropped from monthly mean (etr_tracker_daily)"
}
gen int ym = mofd(daily_date)
format ym %tm
collapse (mean) weighted_etr, by(ym)
replace weighted_etr = weighted_etr * 100
rename weighted_etr etr_tracker_daily
keep if ym >= $start_ym & ym <= $end_ym
tempfile bench_tracker
save `bench_tracker'


* ======================================================================
* E. COMBINE, PRINT, SAVE
* ======================================================================

di as text _n "  [E] Combining and saving..."

use `tier_full', clear
merge 1:1 ym using `tier_matched',  nogenerate
merge 1:1 ym using `tier_nonzero',  nogenerate
merge 1:1 ym using `tier_recon',    nogenerate
merge 1:1 ym using `bench_tracker', nogenerate keep(match master)

** Channel decomposition (pp)
gen double gap_zero_drop   = etr_nonzero - etr_full
gen double gap_match_drop  = etr_matched - etr_full
gen double gap_recon       = etr_full    - s0_recon
gen double gap_vs_tracker  = etr_full    - etr_tracker_daily

label var etr_full           "ETR, 2024 wts, full universe, total_rate (%)"
label var etr_matched        "ETR, 2024 wts, matched-only, total_rate (%)"
label var etr_nonzero        "ETR, 2024 wts, nonzero-only, total_rate (%)"
label var s0_recon           "S0 reconstruction (rate_2024 x 2024 wts) (%)"
label var etr_tracker_daily  "Tracker daily ETR, monthly avg (%)"
label var gap_zero_drop      "Effect of dropping zero-rate products (pp)"
label var gap_match_drop     "Effect of dropping unmatched products (pp)"
label var gap_recon          "Tracker baseline - S0 reconstruction (pp)"
label var gap_vs_tracker     "Full 2024-wt ETR - tracker daily (pp)"

format etr_* s0_recon gap_* %9.2f

di as text _n "  === Baseline ETR at 2024 weights ==="
list ym etr_full s0_recon etr_matched etr_nonzero etr_tracker_daily, clean noobs

di as text _n "  === Diagnostic gaps (pp) ==="
list ym gap_recon gap_zero_drop gap_match_drop gap_vs_tracker, clean noobs

sort ym
compress
save "$working/baseline_etr_diagnostic.dta", replace
export delimited using "$tables/baseline_etr_diagnostic.csv", replace


* ======================================================================
* F. FIGURE
* ======================================================================

di as text _n "  [F] Figure..."

twoway ///
    (connected etr_full          ym, mcolor("$color_statutory") ///
        lcolor("$color_statutory") msymbol(circle) lwidth(medthick)) ///
    (connected s0_recon          ym, mcolor("$color_canada") ///
        lcolor("$color_canada") msymbol(diamond) lwidth(medium) ///
        lpattern(shortdash)) ///
    (connected etr_nonzero       ym, mcolor("$color_gap") ///
        lcolor("$color_gap") msymbol(square) lwidth(medthick) ///
        lpattern(dash)) ///
    (connected etr_tracker_daily ym, mcolor("$color_actual") ///
        lcolor("$color_actual") msymbol(triangle) lwidth(medthick) ///
        lpattern(solid)) ///
    , ///
    legend(order( ///
        1 "2024 wts, full universe (tracker total_rate)" ///
        2 "2024 wts, full universe (S0 reconstruction)" ///
        3 "2024 wts, nonzero-rate products only" ///
        4 "Tracker daily ETR (actual wts, monthly avg)") ///
        rows(4) size(small) position(6)) ///
    ytitle("Effective Tariff Rate (%)") ///
    xtitle("") ///
    title("Baseline Statutory ETR Diagnostic") ///
    subtitle("Tracker baseline vs S0 reconstruction at 2024 wts; tracker daily benchmark") ///
    xlabel(, format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure7_baseline_etr_diagnostic.png", replace width(2400)


di as text _n "  06_baseline_etr_diagnostic complete." _n
