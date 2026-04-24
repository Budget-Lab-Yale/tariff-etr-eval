* ==============================================================================
* 06_baseline_etr_diagnostic.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Diagnostic recomputation of the statutory ETR at 2024 trade weights,
*          using the tracker's own `total_rate` (which already has the tracker's
*          baseline USMCA assumption applied). Intended to isolate why the
*          Tier 1 series in 02_etr_analysis looks too high by separately
*          quantifying two suspects:
*            (a) USMCA handling — our reconstruction vs tracker baseline
*            (b) Zero-rate products dropped — universe restriction effects
*
*          Universe used here: the full 2024 import-weight universe
*          ($working/weights_2024.dta, ~333k hs10 x cty_code pairs) crossed with
*          the analysis window and merged to the active HTS revision snapshot.
*
* Output:
*   $working/baseline_etr_diagnostic.dta
*   $tables/baseline_etr_diagnostic.csv
*   $figures/figure6_baseline_etr_diagnostic.png
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
* B. BUILD 2024-WEIGHT x MONTH PANEL, MERGE TRACKER BASELINE RATES
* ======================================================================

di as text "  [B] Building 2024 weights x months x tracker baseline rates..."

use "$working/weights_2024.dta", clear
keep hs10 cty_code imports

local n_months = $end_ym - $start_ym + 1
expand `n_months'
bysort hs10 cty_code: gen int ym = $start_ym + _n - 1
format ym %tm

merge m:1 ym using `month_rev_map', keep(match master) nogenerate

** Merge tracker snapshot total_rate (already has baseline USMCA applied)
merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) keepusing(total_rate usmca_eligible) ///
    gen(_merge_snap)

qui count if _merge_snap == 3
local n_match = r(N)
local match_rate = 100 * `n_match' / _N
di as text "      Snapshot match: `n_match' of `=_N' (" ///
    string(`match_rate', "%4.1f") "%)"
if `match_rate' < 75 {
    di as error "WARNING: snapshot match rate below 75% — diagnostic suspect"
}

gen byte matched_snap = (_merge_snap == 3)
drop _merge_snap

** Fill unmatched snapshots with zero (same treatment as tracker daily series)
gen double rate = total_rate
replace rate = 0 if missing(rate)

gen byte is_nonzero = (rate > 0 & !missing(rate))

qui count
di as text "      Panel obs: " _N
qui count if matched_snap
di as text "      Matched to snapshot: " r(N)
qui count if is_nonzero
di as text "      Nonzero rate:        " r(N)

compress


* ======================================================================
* C. MONTHLY AGGREGATES (3 UNIVERSE DEFINITIONS)
* ======================================================================

di as text _n "  [C] Computing monthly ETR under 3 universe definitions..."

** C1. Full 2024 universe (all pairs with imports > 0 in 2024)
preserve
    gen double num = rate * imports
    collapse (sum) num_full=num den_full=imports ///
             (count) n_full=rate, by(ym)
    safe_divide num_full den_full etr_full
    replace etr_full = etr_full * 100
    tempfile tier_full
    save `tier_full'
restore

** C2. Matched-only (drop products with no tracker snapshot match)
preserve
    keep if matched_snap
    gen double num = rate * imports
    collapse (sum) num_m=num den_m=imports ///
             (count) n_matched=rate, by(ym)
    safe_divide num_m den_m etr_matched
    replace etr_matched = etr_matched * 100
    tempfile tier_matched
    save `tier_matched'
restore

** C3. Nonzero-only (isolate "zero products dropped" hypothesis)
preserve
    keep if is_nonzero
    gen double num = rate * imports
    collapse (sum) num_n=num den_n=imports ///
             (count) n_nonzero=rate, by(ym)
    safe_divide num_n den_n etr_nonzero
    replace etr_nonzero = etr_nonzero * 100
    tempfile tier_nonzero
    save `tier_nonzero'
restore


* ======================================================================
* D. BENCHMARKS: tracker daily (collapsed) + Tier 1 from 02 if present
* ======================================================================

di as text "  [D] Benchmarks..."

** Tracker's own daily ETR, collapsed to monthly (import-weighted, same
** universe the tracker uses — actual monthly imports, not 2024 weights)
use "$working/tracker_daily.dta", clear
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
merge 1:1 ym using `bench_tracker', nogenerate keep(match master)

** Channel decomposition (pp)
gen double gap_zero_drop   = etr_nonzero - etr_full
gen double gap_match_drop  = etr_matched - etr_full
gen double gap_vs_tracker  = etr_full - etr_tracker_daily

label var etr_full           "ETR, 2024 wts, full universe (%)"
label var etr_matched        "ETR, 2024 wts, matched-only (%)"
label var etr_nonzero        "ETR, 2024 wts, nonzero-only (%)"
label var etr_tracker_daily  "Tracker daily ETR, monthly avg (%)"
label var gap_zero_drop      "Effect of dropping zero-rate products (pp)"
label var gap_match_drop     "Effect of dropping unmatched products (pp)"
label var gap_vs_tracker     "Full 2024-wt ETR - tracker daily (pp)"
label var n_full             "N pairs, full universe"
label var n_matched          "N pairs, matched to snapshot"
label var n_nonzero          "N pairs, nonzero rate"

format etr_* gap_* %9.2f

di as text _n "  === Baseline ETR at 2024 weights ==="
list ym etr_full etr_matched etr_nonzero etr_tracker_daily, clean noobs

di as text _n "  === Diagnostic gaps (pp) ==="
list ym gap_zero_drop gap_match_drop gap_vs_tracker, clean noobs

di as text _n "  === Pair counts ==="
list ym n_full n_matched n_nonzero, clean noobs

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
    (connected etr_nonzero       ym, mcolor("$color_gap") ///
        lcolor("$color_gap") msymbol(square) lwidth(medthick) ///
        lpattern(dash)) ///
    (connected etr_tracker_daily ym, mcolor("$color_actual") ///
        lcolor("$color_actual") msymbol(triangle) lwidth(medthick) ///
        lpattern(solid)) ///
    , ///
    legend(order( ///
        1 "2024 wts, full universe (tracker baseline USMCA)" ///
        2 "2024 wts, nonzero-rate products only" ///
        3 "Tracker daily ETR (actual wts, monthly avg)") ///
        rows(3) size(small) position(6)) ///
    ytitle("Effective Tariff Rate (%)") ///
    xtitle("") ///
    title("Baseline Statutory ETR Diagnostic") ///
    subtitle("2024-weight reconstructions vs tracker daily, Jan 2025 - Feb 2026") ///
    xlabel(, format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure6_baseline_etr_diagnostic.png", replace width(2400)


di as text _n "  06_baseline_etr_diagnostic complete." _n
