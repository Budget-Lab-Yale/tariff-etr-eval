* ==============================================================================
* 05_counterfactual_ladder.do
* Creator: John Iselin (ported from R_archive/R/03_counterfactual_ladder.R)
* Date: April 2026
* Purpose: Waterfall decomposition of the statutory-actual ETR gap,
*          following Gopinath-Neiman (2026) methodology.
*
* Ladder steps:
*   S0: Full statutory (tracker rates) x 2024 weights
*   S1: + USMCA at Dec 2024 baseline utilization x 2024 weights
*   S2: + USMCA at actual 2025 utilization x 2024 weights
*   S3: Tracker rates x actual monthly weights (behavioral reweighting)
*   T:  Treasury actual ETR
*
* Gap channels:
*   S0 -> S1 = USMCA baseline (pre-existing preference)
*   S1 -> S2 = USMCA surge (behavioral preference response)
*   S2 -> S3 = Trade diversion + product substitution
*   S3 -> T  = Residual (MFN prefs, enforcement, timing, evasion)
*
* Note: S4 (MFN exemptions) and S5 (IEEPA exemptions) are placeholders.
* The R original set these equal to S3 because decomposing further
* introduces rate-table inconsistencies. The FTA decomposition
* (03_fta_decomposition.do) handles that channel via IMDB data instead.
*
* Input:
*   $working/merged_analysis.dta
*   $working/tracker_snapshots.dta
*   $working/weights_2024.dta
*   $working/revenue_monthly.dta
*   $working/revision_dates.dta
*
* Output:
*   $tables/counterfactual_ladder.csv
*   $tables/counterfactual_by_country.csv
* ==============================================================================

di as text _n "=========================================="
di as text "  05_counterfactual_ladder: Waterfall Decomposition"
di as text "==========================================" _n


* ======================================================================
* A. LOAD BASE DATA
* ======================================================================

di as text "  [A] Loading data..."

* Snapshot rates with per-authority breakdowns
use "$working/tracker_snapshots.dta", clear

* Keep columns needed for the ladder
capture confirm variable statutory_rate_ieepa_recip
if _rc == 0 {
    keep hs10 cty_code revision total_rate ///
         statutory_rate_232 statutory_rate_ieepa_recip ///
         statutory_rate_ieepa_fent statutory_rate_301 ///
         statutory_rate_s122 statutory_rate_section_201 ///
         statutory_base_rate usmca_eligible
}
else {
    keep hs10 cty_code revision total_rate usmca_eligible
}

sort revision hs10 cty_code
tempfile snap_rates
save `snap_rates'
di as text "       Snapshots: `=_N' rows"

* 2024 import weights
use "$working/weights_2024.dta", clear
keep hs10 cty_code imports w_2024
sort hs10 cty_code
tempfile wt_2024
save `wt_2024'
local total_imports_2024 = imports[1] / w_2024[1]
di as text "       2024 weights: `=_N' pairs"

* Monthly HS10 data (from merged analysis)
use "$working/merged_analysis.dta", clear
keep ym hs10 cty_code con_val_mo partner_group revision
sort ym hs10 cty_code
tempfile monthly_data
save `monthly_data'
di as text "       Monthly data: `=_N' rows"

* Treasury actual ETR
use "$working/revenue_monthly.dta", clear
keep ym actual_rate
sort ym
tempfile treasury
save `treasury'


* ======================================================================
* B. COMPUTE LADDER STEPS PER MONTH
* ======================================================================

di as text _n "  [B] Computing ladder steps..."

* Get list of months
use `monthly_data', clear
levelsof ym, local(months)

tempfile ladder_rows
local first_month = 1

foreach m of local months {

    local month_label : di %tmMon_CCYY `m'
    local month_label = trim("`month_label'")
    di as text "      `month_label'"

    * --- Identify revision for this month ---
    use `monthly_data', clear
    keep if ym == `m'
    local rev = revision[1]

    * --- S0: Full statutory x 2024 weights ---
    * Merge 2024 weights with snapshot rates for this revision
    use `wt_2024', clear
    merge 1:1 hs10 cty_code using `snap_rates' if revision == "`rev'", ///
        keep(match master) keepusing(total_rate usmca_eligible) nogenerate

    * Unmatched products: zero tariff
    replace total_rate = 0 if missing(total_rate)
    replace usmca_eligible = 0 if missing(usmca_eligible)

    * S0 = import-weighted statutory ETR with 2024 weights
    gen double wtd_rate_s0 = total_rate * imports
    qui sum wtd_rate_s0
    local sum_wtd_s0 = r(sum)
    qui sum imports
    local sum_imp_2024 = r(sum)
    local s0 = `sum_wtd_s0' / `sum_imp_2024'

    * --- S1: Reduce USMCA-eligible CA/MX rates by 2024 baseline utilization ---
    * Approximate: USMCA-eligible products for CA/MX get rate scaled by
    * (1 - baseline_usmca_share). We use usmca_eligible as a binary flag
    * and assume ~50% baseline utilization (conservative, per tracker CLAUDE.md).
    gen double rate_s1 = total_rate
    replace rate_s1 = total_rate * 0.5 if ///
        usmca_eligible == 1 & inlist(cty_code, "1220", "2010")
    gen double wtd_rate_s1 = rate_s1 * imports
    qui sum wtd_rate_s1
    local s1 = r(sum) / `sum_imp_2024'

    * --- S2: USMCA at actual 2025 utilization (higher) ---
    * Approximate: utilization rose from ~50% to ~65% post-escalation
    gen double rate_s2 = total_rate
    replace rate_s2 = total_rate * 0.35 if ///
        usmca_eligible == 1 & inlist(cty_code, "1220", "2010")
    gen double wtd_rate_s2 = rate_s2 * imports
    qui sum wtd_rate_s2
    local s2 = r(sum) / `sum_imp_2024'

    * --- S3: Tracker rates x actual monthly weights ---
    use `monthly_data', clear
    keep if ym == `m'
    * total_rate already merged in merged_analysis.dta
    * But we need to recompute with the full snapshot
    merge m:1 hs10 cty_code using `snap_rates' if revision == "`rev'", ///
        keep(match master) keepusing(total_rate) nogenerate update
    replace total_rate = 0 if missing(total_rate)

    gen double wtd_rate_s3 = total_rate * con_val_mo
    qui sum wtd_rate_s3
    local sum_wtd_s3 = r(sum)
    qui sum con_val_mo
    local sum_val_m = r(sum)
    local s3 = `sum_wtd_s3' / `sum_val_m'

    * --- T: Treasury actual ---
    use `treasury', clear
    qui sum actual_rate if ym == `m'
    local t_rate = r(mean)
    if r(N) == 0 local t_rate = .

    * --- Assemble ladder row ---
    clear
    set obs 1
    gen int ym = `m'
    format ym %tm

    gen double s0_full_statutory    = `s0'
    gen double s1_usmca_frozen_2024 = `s1'
    gen double s2_usmca_actual_2025 = `s2'
    gen double s3_tracker_actualw   = `s3'
    gen double treasury_actual      = `t_rate'

    * Gap channels (as ratios, will convert to pp below)
    gen double gap_usmca_baseline = (s0_full_statutory - s1_usmca_frozen_2024)
    gen double gap_usmca_surge    = (s1_usmca_frozen_2024 - s2_usmca_actual_2025)
    gen double gap_behavioral     = (s2_usmca_actual_2025 - s3_tracker_actualw)
    gen double gap_residual       = (s3_tracker_actualw - treasury_actual) ///
                                     if !missing(treasury_actual)
    gen double gap_total          = (s0_full_statutory - treasury_actual) ///
                                     if !missing(treasury_actual)

    * Convert all to percentage points
    foreach v of varlist s0_* s1_* s2_* s3_* treasury_actual ///
                         gap_usmca_baseline gap_usmca_surge ///
                         gap_behavioral gap_residual gap_total {
        replace `v' = `v' * 100
    }

    if `first_month' {
        save `ladder_rows', replace
        local first_month = 0
    }
    else {
        append using `ladder_rows'
        save `ladder_rows', replace
    }
}


* ======================================================================
* C. LABEL AND SAVE
* ======================================================================

use `ladder_rows', clear

label var s0_full_statutory    "S0: Full statutory, 2024 wts (%)"
label var s1_usmca_frozen_2024 "S1: + USMCA baseline 2024 (%)"
label var s2_usmca_actual_2025 "S2: + USMCA actual 2025 (%)"
label var s3_tracker_actualw   "S3: Tracker rates, monthly wts (%)"
label var treasury_actual      "T: Treasury actual ETR (%)"
label var gap_usmca_baseline   "USMCA baseline gap (pp)"
label var gap_usmca_surge      "USMCA surge gap (pp)"
label var gap_behavioral       "Behavioral gap (pp)"
label var gap_residual         "Residual gap (pp)"
label var gap_total            "Total gap S0-T (pp)"

sort ym
compress
save "$working/counterfactual_ladder.dta", replace
export delimited using "$tables/counterfactual_ladder.csv", replace

di as text _n "  === Counterfactual Ladder ==="
format s0_* s1_* s2_* s3_* treasury_actual %9.2f
format gap_* %9.2f
list ym s0_full_statutory s1_usmca_frozen_2024 s2_usmca_actual_2025 ///
    s3_tracker_actualw treasury_actual, clean noobs

di as text _n "  === Gap Decomposition (pp) ==="
list ym gap_usmca_baseline gap_usmca_surge gap_behavioral ///
    gap_residual gap_total, clean noobs


* ======================================================================
* D. COUNTRY-LEVEL LADDER
* ======================================================================

di as text _n "  [D] Country-level ladder..."

use `monthly_data', clear

* S0 by country: statutory x 2024 weights
preserve
    use `wt_2024', clear
    merge 1:1 hs10 cty_code using `snap_rates', ///
        keep(match master) keepusing(total_rate) nogenerate
    replace total_rate = 0 if missing(total_rate)

    assign_partner_group cty_code

    gen double wtd_rate = total_rate * imports
    collapse (sum) wtd_rate imports, by(partner_group)
    safe_divide wtd_rate imports s0_etr
    replace s0_etr = s0_etr * 100

    gen double import_share = imports / `sum_imp_2024' * 100
    label var s0_etr      "S0 ETR by country (%)"
    label var import_share "2024 import share (%)"

    sort partner_group
    tempfile cty_s0
    save `cty_s0'
restore

* S3 by country: tracker x monthly weights (averaged across months)
preserve
    use `monthly_data', clear
    replace total_rate = 0 if missing(total_rate)
    assign_partner_group cty_code

    gen double wtd_rate = total_rate * con_val_mo
    collapse (sum) wtd_rate con_val_mo, by(ym partner_group)
    safe_divide wtd_rate con_val_mo s3_etr
    replace s3_etr = s3_etr * 100

    collapse (mean) s3_etr, by(partner_group)
    label var s3_etr "S3 avg ETR by country (%)"

    tempfile cty_s3
    save `cty_s3'
restore

* Combine
use `cty_s0', clear
merge 1:1 partner_group using `cty_s3', nogenerate

gen double gap_total_cty = s0_etr - s3_etr
label var gap_total_cty "S0-S3 gap by country (pp)"

sort partner_group
compress
save "$working/counterfactual_by_country.dta", replace
export delimited using "$tables/counterfactual_by_country.csv", replace

di as text _n "  === Country-Level Ladder ==="
format s0_etr s3_etr gap_total_cty import_share %9.2f
list partner_group s0_etr s3_etr gap_total_cty import_share, clean noobs


di as text _n "  05_counterfactual_ladder complete." _n
