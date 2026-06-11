* ==============================================================================
* 05_max_district_crosscheck.do
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
*   $working/max_district_comparisons.dta -- full HS10 x cty x ym panel
*       (kept for downstream debugging; not re-exported as CSV by default)
*
* Tunable thresholds live in code/utils/globals.do:
*   $rate_extreme_cutoff        (line-level extreme rate filter, default 2.0)
*   $match_tol_pp               (strict match band, default 2pp)
*   $match_tol_loose_pp         (loose match band, default 5pp)
*   $divergence_pp_cutoff       (divergence flag in pp, default 5)
*   $divergence_value_cutoff    (divergence flag in $, default 1e8)
* ==============================================================================

di as text _n "=========================================="
di as text "  05_max_district_crosscheck: Tracker Rate Validation"
di as text "==========================================" _n


* ======================================================================
* A. LOAD IMDB DETAIL AND COMPUTE ENTRY-LEVEL RATES
* ======================================================================

di as text "  [A] Loading IMDB detail data..."

import delimited using "$raw/imdb_detail.csv", clear stringcols(1 2 3 4 5 6)
destring con_val_mo dut_val_mo cal_dut_mo, replace force

** Warn on coercion failures: `force` silently converts non-numeric to missing.
qui count if missing(con_val_mo)
if r(N) > 0 {
    di as error "WARNING: `=r(N)' rows have missing con_val_mo after destring force"
}

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

* Filter extreme rates per Gopinath-Neiman convention; China and Russia are
* exempted because their entry rates can legitimately exceed the cutoff.
* Threshold defined as $rate_extreme_cutoff in globals.do.
drop if entry_rate >= $rate_extreme_cutoff & !inlist(cty_code, "$cty_china", "$cty_russia")

* Classify preference channels (program from programs.do); has_preference is
* any non-residual classification.
classify_pref_channel cty_subco rate_prov cty_code
gen byte has_preference = (pref_channel != "other")

assign_partner_group cty_code

di as text "       `=_N' entries after filtering"


* ======================================================================
* B. MAX RATE ACROSS DISTRICTS PER HS10 x COUNTRY x MONTH
* ======================================================================

di as text "  [B] Computing max-across-districts rates..."

* Weighted mean computed manually so collapse can run unweighted
* (Stata collapse doesn't accept a mid-list [aw=] and applying it globally
*  would disturb the min/max/sum stats).
gen double _wtd_rate = entry_rate * con_val_mo

collapse ///
    (max)   max_rate = entry_rate ///
    (min)   min_rate = entry_rate ///
    (sum)   _wtd_rate ///
    (sum)   total_imports = con_val_mo ///
            total_duties = cal_dut_mo ///
    (max)   has_preference ///
    (first) partner_group, ///
    by(ym hs10 cty_code)

gen double mean_rate = _wtd_rate / total_imports
drop _wtd_rate

di as text "       `=_N' HS10 x country x month cells"


* ======================================================================
* C. MAP TO REVISIONS AND MERGE TRACKER RATES
* ======================================================================

di as text "  [C] Merging tracker statutory rates..."

** Build month -> revision mapping (program from programs.do).
** preserve/restore is needed here -- unlike in 01 where build_month_rev_map
** runs before any analysis data is loaded, here we already have the collapsed
** HS10 x cty x ym panel in memory and build_month_rev_map clears it.
tempfile month_rev_map
preserve
    build_month_rev_map, saving(`month_rev_map')
restore

** Merge revision onto collapsed data via month
merge m:1 ym using `month_rev_map', keep(match master) nogenerate

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
gen byte   match_2pp   = (abs_diff_pp <= $match_tol_pp) if !missing(tracker_rate)
gen byte   match_5pp   = (abs_diff_pp <= $match_tol_loose_pp) if !missing(tracker_rate)

gen str20 category = ""
replace category = "no_tracker_rate" if missing(tracker_rate)
replace category = "match"           if !missing(tracker_rate) & abs_diff_pp <= $match_tol_pp
replace category = "tracker_higher"  if !missing(tracker_rate) & diff_pp >  $match_tol_pp
replace category = "observed_higher" if !missing(tracker_rate) & diff_pp < -$match_tol_pp

label var tracker_rate "Tracker statutory rate"
label var max_rate     "Max observed rate across districts"
label var mean_rate    "Import-weighted mean observed rate"
label var diff_pp      "Tracker - max observed (pp)"
label var category     "Match category"
label var match_2pp    "Within 2pp"
label var match_5pp    "Within 5pp"
label var imports_2024 "2024 import value ($)"

compress
* Persist the full comparison panel (HS10 x cty x ym) for downstream debugging
* and ad-hoc slicing -- not just the filtered divergence subset Section F saves.
save "$working/max_district_comparisons.dta", replace
tempfile comparisons
save `comparisons'


* ======================================================================
* E. MONTHLY SUMMARY STATISTICS
* ======================================================================

di as text "  [E] Computing monthly summary statistics..."

preserve
    keep if !missing(tracker_rate)

    * Weighted means computed manually (collapse can't mix weighted mean
    * with unweighted count/sum in one command).
    gen double _wtd_tracker   = tracker_rate * imports_2024
    gen double _wtd_max       = max_rate     * imports_2024
    gen double _wtd_collected = mean_rate    * imports_2024

    collapse ///
        (count) n_with_tracker = tracker_rate ///
        (sum)   n_match_2pp    = match_2pp ///
                n_match_5pp    = match_5pp ///
                _wtd_tracker _wtd_max _wtd_collected ///
                total_wt       = imports_2024, ///
        by(ym)

    gen double agg_tracker_etr   = _wtd_tracker   / total_wt
    gen double agg_max_etr       = _wtd_max       / total_wt
    gen double agg_collected_etr = _wtd_collected / total_wt
    drop _wtd_tracker _wtd_max _wtd_collected total_wt

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

* Large divergences worth manual review: thresholds in globals.do.
keep if abs_diff_pp > $divergence_pp_cutoff ///
        & imports_2024 > $divergence_value_cutoff ///
        & !missing(tracker_rate)
gsort -imports_2024

gen str2 hs2 = substr(hs10, 1, 2)

di as text "       `=_N' large divergences (>${divergence_pp_cutoff}pp, " ///
    ">$" string(${divergence_value_cutoff}/1e6, "%9.0f") "M)"

if _N > 0 {
    compress
    save "$working/max_district_divergences.dta", replace
    export delimited using "$tables/max_district_divergences.csv", replace
}
else {
    di as text "       No large divergences found"
}


di as text _n "  05_max_district_crosscheck complete." _n
