* ==============================================================================
* 04_max_district_crosscheck.do
* Creator: John Iselin (ported from R_archive/R/02c_max_district_crosscheck.R)
* Date: April 2026
* Purpose: Cross-check tracker statutory rates against max observed ETR across
*          customs districts. For each HS10 x country, the max effective rate
*          across districts approximates the statutory rate (lower districts
*          reflect FTA/preference utilization).
*
* Categories:
*   match            -- tracker and max observed agree (within 2pp)
*   tracker_higher   -- tracker > max: all importers use preferences
*   observed_higher  -- max > tracker: possible tracker error or compound rates
*   no_tracker_rate  -- product not in tracker snapshot
*
* Input:
*   $raw/imdb_detail.csv           (from R/00_pull_raw_data.R, rich parse)
*   $working/tracker_snapshots.dta
*   $working/weights_2024.dta
*   $working/revision_dates.dta
*
* Output:
*   $tables/max_district_summary.csv      -- monthly match statistics
*   $tables/max_district_divergences.csv  -- flagged large discrepancies
* ==============================================================================

di as text _n "=========================================="
di as text "  04_max_district_crosscheck: Tracker Rate Validation"
di as text "==========================================" _n


* ======================================================================
* A. LOAD IMDB DETAIL AND COMPUTE ENTRY-LEVEL RATES
* ======================================================================

di as text "  [A] Loading IMDB detail data..."

import delimited using "$raw/imdb_detail.csv", clear stringcols(1 2 3 4 5 6)
destring con_val_mo dut_val_mo cal_dut_mo, replace force

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm

keep if ym >= $start_ym & ym <= $end_ym

* Exclude FTZ/bonded (not real duty payments) and zero-value entries
drop if rate_prov == "00"
drop if con_val_mo <= 0 | missing(con_val_mo)

* Entry-level effective rate
gen double entry_rate = cal_dut_mo / con_val_mo

* Filter extreme rates (following Gopinath-Neiman: drop rate >= 2.0
* unless China or Russia where rates can legitimately exceed 100%)
drop if entry_rate >= 2.0 & !inlist(cty_code, "5700", "4621")

* Flag whether any preference was claimed
gen byte has_preference = (cty_subco != "0" & cty_subco != "" & cty_subco != "00")

assign_partner_group cty_code

di as text "       `=_N' entries after filtering"


* ======================================================================
* B. MAX RATE ACROSS DISTRICTS PER HS10 x COUNTRY x MONTH
* ======================================================================

di as text "  [B] Computing max-across-districts rates..."

collapse ///
    (max)   max_rate = entry_rate ///
    (mean)  mean_rate = entry_rate [aw = con_val_mo] ///
    (min)   min_rate = entry_rate ///
    (sum)   total_imports = con_val_mo ///
            total_duties = cal_dut_mo ///
    (max)   has_preference ///
    (first) partner_group, ///
    by(ym hs10 cty_code)

* Note: weighted mean uses con_val_mo as analytic weights

di as text "       `=_N' HS10 x country x month cells"


* ======================================================================
* C. MAP TO REVISIONS AND MERGE TRACKER RATES
* ======================================================================

di as text "  [C] Merging tracker statutory rates..."

* Month -> revision mapping
gen first_of_month = dofm(ym)
format first_of_month %td
cross using "$working/revision_dates.dta"
keep if eff_date <= first_of_month
bysort ym hs10 cty_code (eff_date): keep if _n == _N
drop first_of_month eff_date eff_ym policy_event

* Merge statutory rates
merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) keepusing(total_rate) gen(_merge_snap)

qui count if _merge_snap == 3
local n_matched = r(N)
qui count if _merge_snap == 1
local n_unmatched = r(N)
di as text "       Tracker match: `n_matched', no tracker: `n_unmatched'"

rename total_rate tracker_rate
drop _merge_snap

* Merge 2024 import weights
merge m:1 hs10 cty_code using "$working/weights_2024.dta", ///
    keep(match master) keepusing(imports) nogenerate
replace imports = 0 if missing(imports)
rename imports imports_2024


* ======================================================================
* D. COMPARISON METRICS AND CLASSIFICATION
* ======================================================================

di as text "  [D] Classifying comparisons..."

gen double diff_pp     = (tracker_rate - max_rate) * 100
gen double abs_diff_pp = abs(diff_pp)
gen byte   match_2pp   = (abs_diff_pp <= 2) if !missing(tracker_rate)
gen byte   match_5pp   = (abs_diff_pp <= 5) if !missing(tracker_rate)

gen str20 category = ""
replace category = "no_tracker_rate" if missing(tracker_rate)
replace category = "match"           if !missing(tracker_rate) & abs_diff_pp <= 2
replace category = "tracker_higher"  if !missing(tracker_rate) & diff_pp > 2
replace category = "observed_higher" if !missing(tracker_rate) & diff_pp < -2

label var tracker_rate "Tracker statutory rate"
label var max_rate     "Max observed rate across districts"
label var mean_rate    "Import-weighted mean observed rate"
label var diff_pp      "Tracker - max observed (pp)"
label var category     "Match category"
label var match_2pp    "Within 2pp"
label var match_5pp    "Within 5pp"
label var imports_2024 "2024 import value ($)"

compress
tempfile comparisons
save `comparisons'


* ======================================================================
* E. MONTHLY SUMMARY STATISTICS
* ======================================================================

di as text "  [E] Computing monthly summary statistics..."

preserve
    keep if !missing(tracker_rate)

    * Unweighted match rates
    collapse ///
        (count) n_with_tracker = tracker_rate ///
        (sum)   n_match_2pp = match_2pp ///
                n_match_5pp = match_5pp ///
        (sum)   n_tracker_higher = tracker_rate ///
                n_observed_higher = tracker_rate ///
        (mean)  agg_tracker_etr = tracker_rate [aw = imports_2024] ///
        (mean)  agg_max_etr = max_rate [aw = imports_2024] ///
        (mean)  agg_collected_etr = mean_rate [aw = imports_2024], ///
        by(ym)

    * Fix: need proper counts for tracker_higher / observed_higher
    drop n_tracker_higher n_observed_higher
    tempfile summary_shell
    save `summary_shell'
restore

* Count categories properly
preserve
    keep if !missing(tracker_rate)
    gen byte is_tracker_higher  = (category == "tracker_higher")
    gen byte is_observed_higher = (category == "observed_higher")
    collapse (sum) n_tracker_higher = is_tracker_higher ///
                   n_observed_higher = is_observed_higher, by(ym)
    merge 1:1 ym using `summary_shell', nogenerate
restore

* Weighted match rates
preserve
    keep if !missing(tracker_rate) & imports_2024 > 0
    gen double wt_match_2pp = match_2pp * imports_2024
    gen double wt_match_5pp = match_5pp * imports_2024
    collapse (sum) wt_match_2pp wt_match_5pp imports_2024, by(ym)
    gen double weighted_match_2pp = wt_match_2pp / imports_2024 * 100
    gen double weighted_match_5pp = wt_match_5pp / imports_2024 * 100
    keep ym weighted_match_2pp weighted_match_5pp
    tempfile wt_match
    save `wt_match'
restore

use `summary_shell', clear
merge 1:1 ym using `wt_match', nogenerate

gen double pct_match_2pp = n_match_2pp / n_with_tracker * 100

* Convert ETRs to percentage
foreach v in agg_tracker_etr agg_max_etr agg_collected_etr {
    replace `v' = `v' * 100
}

label var n_with_tracker    "HS10 x country pairs with tracker rate"
label var pct_match_2pp     "Unweighted match rate (2pp, %)"
label var weighted_match_2pp "Import-weighted match rate (2pp, %)"
label var weighted_match_5pp "Import-weighted match rate (5pp, %)"
label var agg_tracker_etr   "Aggregate tracker ETR (%)"
label var agg_max_etr       "Aggregate max-district ETR (%)"
label var agg_collected_etr "Aggregate collected ETR (%)"

sort ym
compress
save "$working/max_district_summary.dta", replace
export delimited using "$tables/max_district_summary.csv", replace

di as text _n "  === Max-District Cross-Check Summary ==="
format pct_match_2pp weighted_match_2pp weighted_match_5pp %9.1f
format agg_tracker_etr agg_max_etr agg_collected_etr %9.2f
list ym n_with_tracker pct_match_2pp weighted_match_2pp ///
    agg_tracker_etr agg_max_etr, clean noobs


* ======================================================================
* F. FLAG LARGE DIVERGENCES
* ======================================================================

di as text _n "  [F] Flagging large divergences..."

use `comparisons', clear

* Large divergences: >5pp gap, >$100M in 2024 imports, has tracker rate
keep if abs_diff_pp > 5 & imports_2024 > 1e8 & !missing(tracker_rate)
gsort -imports_2024

gen str2 hs2 = substr(hs10, 1, 2)

di as text "       `=_N' large divergences (>5pp, >$100M)"

if _N > 0 {
    compress
    save "$working/max_district_divergences.dta", replace
    export delimited using "$tables/max_district_divergences.csv", replace
}
else {
    di as text "       No large divergences found"
}


di as text _n "  04_max_district_crosscheck complete." _n
