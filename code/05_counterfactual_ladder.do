* ==============================================================================
* 05_counterfactual_ladder.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Waterfall decomposition of the statutory-actual ETR gap,
*          following Gopinath-Neiman (2026) methodology.
*
* Ladder steps:
*   S0: Statutory (USMCA @ 2024 shares) x 2024 import weights
*   S1: Statutory (USMCA @ 2024 shares) x actual monthly weights
*   S2: Statutory (USMCA @ monthly shares) x actual monthly weights
*   S3: + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP /
*       other_fta) at monthly IMDB-derived shares
*   T:  Treasury actual ETR
*
* (S4 = Census collected ETR is computed in 02_etr_analysis.do, not here.)
*
* Gap channels:
*   S0 -> S1 = Trade diversion (weight shift, USMCA held at 2024 baseline)
*   S1 -> S2 = USMCA surge (preference claiming response to tariff escalation)
*   S2 -> S3 = All-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
*   S3 -> T  = Residual (AVE failures, AD/CVD, tracker error, timing, evasion)
*
* USMCA methodology:
*   Rates reconstructed from tracker statutory_rate_* components (pre-USMCA)
*   with product-level USMCA utilization shares from USITC DataWeb SPI data.
*   2024 shares: pre-tariff baseline (~38% CA, ~50% MX trade-weighted).
*   Monthly shares: actual 2025 utilization (~67-68% by H2 2025).
*   Day-weighted across revisions within months by the R data pull.
*
* Non-USMCA preference methodology (S3):
*   Per cell delta computed in R section 3g: delta_base = (s_duty_free +
*   s_korus + s_gsp + s_other_fta) * statutory_base_rate_pre, plus
*   delta_recip = s_duty_free * statutory_rate_ieepa_recip_pre. Shares are
*   IMDB-derived (rate_prov + cty_subco). See docs/six_tier_framework_plan.md
*   §6.6 for derivation.
*
* Input:
*   $raw/counterfactual_usmca2024.csv               (from R/00_pull_raw_data.R)
*   $raw/counterfactual_usmca_monthly.csv
*   $raw/counterfactual_other_pref_delta_monthly.csv (from R section 3g)
*   $working/weights_2024.dta
*   $working/merged_analysis.dta
*   $working/revenue_monthly.dta
*
* Output:
*   $working/counterfactual_ladder.dta  + $tables/counterfactual_ladder.csv
*   $working/counterfactual_by_country.dta + $tables/counterfactual_by_country.csv
* ==============================================================================

di as text _n "=========================================="
di as text "  05_counterfactual_ladder: Waterfall Decomposition"
di as text "==========================================" _n


* ======================================================================
* A. LOAD DATA
* ======================================================================

di as text "  [A] Loading data..."

* --- A1. Counterfactual rates: USMCA frozen at 2024 ---

di as text "      Counterfactual rates (USMCA 2024)..."

import delimited using "$raw/counterfactual_usmca2024.csv", ///
    clear stringcols(1 2 3)

capture rename hts10 hs10

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

rename total_rate rate_usmca2024

sort ym hs10 cty_code
compress
tempfile cf_2024
save `cf_2024'
di as text "       `=_N' obs"


* --- A2. Counterfactual rates: USMCA at monthly shares ---

di as text "      Counterfactual rates (USMCA monthly)..."

import delimited using "$raw/counterfactual_usmca_monthly.csv", ///
    clear stringcols(1 2 3)

capture rename hts10 hs10

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

rename total_rate rate_usmca_monthly

sort ym hs10 cty_code
compress
tempfile cf_monthly
save `cf_monthly'
di as text "       `=_N' obs"


* --- A2b. Build cf_all_pref by applying the S2->S3 delta from R ---
*
* The R section 3g writes a sparse delta file (only cells with positive
* non-USMCA preference share). Apply it to cf_monthly to construct the S3
* rate panel: rate_all_pref = max(0, rate_usmca_monthly - delta_base - delta_recip).

di as text "      Counterfactual rates (S3: USMCA monthly + non-USMCA preferences)..."

import delimited using "$raw/counterfactual_other_pref_delta_monthly.csv", ///
    clear stringcols(1 2 3)

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

sort ym hs10 cty_code
tempfile cf_delta
save `cf_delta'
di as text "       `=_N' delta rows"

use `cf_monthly', clear
merge 1:1 ym hs10 cty_code using `cf_delta', keep(match master) nogenerate
replace delta_base  = 0 if missing(delta_base)
replace delta_recip = 0 if missing(delta_recip)
gen double rate_all_pref = max(0, rate_usmca_monthly - delta_base - delta_recip)
keep ym hs10 cty_code rate_all_pref
sort ym hs10 cty_code
compress
tempfile cf_all_pref
save `cf_all_pref'
di as text "       `=_N' obs in cf_all_pref"


* --- A3. 2024 import weights ---

di as text "      2024 import weights..."

use "$working/weights_2024.dta", clear
keep hs10 cty_code imports
sort hs10 cty_code
qui sum imports
local total_imports_2024 = r(sum)
tempfile wt_2024
save `wt_2024'
di as text "       `=_N' pairs"


* --- A4. Monthly trade data (Census HS10 x country x month) ---

di as text "      Monthly trade data..."

use "$working/merged_analysis.dta", clear
keep ym hs10 cty_code con_val_mo partner_group
keep if ym >= $start_ym & ym <= $end_ym
sort ym hs10 cty_code
tempfile monthly_data
save `monthly_data'
di as text "       `=_N' obs"


* --- A5. Treasury actual ETR ---

use "$working/revenue_monthly.dta", clear
keep if ym >= $start_ym
keep ym actual_rate
rename actual_rate treasury_actual
sort ym
tempfile treasury
save `treasury'


* ======================================================================
* B. COMPUTE AGGREGATE LADDER
* ======================================================================

di as text _n "  [B] Computing ladder tiers..."

tempfile tier_s0 tier_s1 tier_s2 tier_s3

* --- S0: USMCA-2024 rates x 2024 weights ---
di as text "      S0: USMCA-2024 x 2024 weights"
compute_tier, ratefile(`cf_2024') ratevar(rate_usmca2024) ///
    weightsrc(2024) outfile(`tier_s0') outvar(s0) ///
    label("S0 (agg) vs cf_2024")

* --- S1: USMCA-2024 rates x actual monthly weights ---
di as text "      S1: USMCA-2024 x monthly weights"
compute_tier, ratefile(`cf_2024') ratevar(rate_usmca2024) ///
    weightsrc(`monthly_data') outfile(`tier_s1') outvar(s1) ///
    label("S1 (agg) vs cf_2024")

* --- S2: USMCA-monthly rates x actual monthly weights ---
di as text "      S2: USMCA-monthly x monthly weights"
compute_tier, ratefile(`cf_monthly') ratevar(rate_usmca_monthly) ///
    weightsrc(`monthly_data') outfile(`tier_s2') outvar(s2) ///
    label("S2 (agg) vs cf_monthly")

* --- S3: USMCA-monthly + non-USMCA preferences x monthly weights ---
di as text "      S3: USMCA-monthly + all preferences x monthly weights"
compute_tier, ratefile(`cf_all_pref') ratevar(rate_all_pref) ///
    weightsrc(`monthly_data') outfile(`tier_s3') outvar(s3) ///
    label("S3 (agg) vs cf_all_pref")


* ======================================================================
* C. COMBINE TIERS, COMPUTE GAPS, LABEL, AND SAVE
* ======================================================================

di as text _n "  [C] Combining tiers and computing gaps..."

use `tier_s0', clear
merge 1:1 ym using `tier_s1', nogenerate
merge 1:1 ym using `tier_s2', nogenerate
merge 1:1 ym using `tier_s3', nogenerate
merge 1:1 ym using `treasury', keep(match master) nogenerate

* Validate
assert _N > 0
foreach v in s0 s1 s2 s3 {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "WARNING: `v' has " r(N) " missing values"
    }
}

* Convert to percentage points
foreach v in s0 s1 s2 s3 treasury_actual {
    replace `v' = `v' * 100
}

* Gap channels (pp). Sequential: each rung subtracts one channel.
gen double gap_diversion = s0 - s1
gen double gap_usmca     = s1 - s2
gen double gap_others    = s2 - s3
gen double gap_residual  = s3 - treasury_actual if !missing(treasury_actual)
gen double gap_total     = s0 - treasury_actual if !missing(treasury_actual)

* Labels
label var s0               "S0: Statutory (USMCA 2024), 2024 wts (%)"
label var s1               "S1: Statutory (USMCA 2024), monthly wts (%)"
label var s2               "S2: Statutory (USMCA monthly), monthly wts (%)"
label var s3               "S3: + non-USMCA preferences, monthly wts (%)"
label var treasury_actual  "T: Treasury actual ETR (%)"
label var gap_diversion    "Trade diversion gap S0-S1 (pp)"
label var gap_usmca        "USMCA surge gap S1-S2 (pp)"
label var gap_others       "All-others preference gap S2-S3 (pp)"
label var gap_residual     "Residual gap S3-T (pp)"
label var gap_total        "Total gap S0-T (pp)"

di as text _n "  === Counterfactual Ladder ==="
format s0 s1 s2 s3 treasury_actual %9.2f
format gap_* %9.2f
list ym s0 s1 s2 s3 treasury_actual, clean noobs

di as text _n "  === Gap Decomposition (pp) ==="
list ym gap_diversion gap_usmca gap_others gap_residual gap_total, clean noobs

sort ym
compress
save "$working/counterfactual_ladder.dta", replace
export delimited using "$tables/counterfactual_ladder.csv", replace


* ======================================================================
* D. COUNTRY-LEVEL LADDER
* ======================================================================

di as text _n "  [D] Country-level ladder..."

tempfile cty_s0 cty_s1 cty_s2 cty_s3

* --- S0 by country: USMCA-2024 x 2024 weights ---
di as text "      S0 by country"
compute_tier, ratefile(`cf_2024') ratevar(rate_usmca2024) ///
    weightsrc(2024) outfile(`cty_s0') outvar(s0_etr) ///
    byvar(partner_group) percent ///
    label("S0 (country) vs cf_2024")

* --- S1 by country: USMCA-2024 x monthly weights ---
di as text "      S1 by country"
compute_tier, ratefile(`cf_2024') ratevar(rate_usmca2024) ///
    weightsrc(`monthly_data') outfile(`cty_s1') outvar(s1_etr) ///
    byvar(partner_group) percent ///
    label("S1 (country) vs cf_2024")

* --- S2 by country: USMCA-monthly x monthly weights ---
di as text "      S2 by country"
compute_tier, ratefile(`cf_monthly') ratevar(rate_usmca_monthly) ///
    weightsrc(`monthly_data') outfile(`cty_s2') outvar(s2_etr) ///
    byvar(partner_group) percent ///
    label("S2 (country) vs cf_monthly")

* --- S3 by country: USMCA-monthly + non-USMCA preferences x monthly wts ---
di as text "      S3 by country"
compute_tier, ratefile(`cf_all_pref') ratevar(rate_all_pref) ///
    weightsrc(`monthly_data') outfile(`cty_s3') outvar(s3_etr) ///
    byvar(partner_group) percent ///
    label("S3 (country) vs cf_all_pref")

* --- Combine country-level tiers ---

use `cty_s0', clear
merge 1:1 ym partner_group using `cty_s1', nogenerate
merge 1:1 ym partner_group using `cty_s2', nogenerate
merge 1:1 ym partner_group using `cty_s3', nogenerate

* Country-level gaps (pp)
gen double gap_diversion = s0_etr - s1_etr
gen double gap_usmca     = s1_etr - s2_etr
gen double gap_others    = s2_etr - s3_etr
gen double gap_s0_s3     = s0_etr - s3_etr

label var s0_etr       "S0: Statutory (USMCA 2024), 2024 wts (%)"
label var s1_etr       "S1: Statutory (USMCA 2024), monthly wts (%)"
label var s2_etr       "S2: Statutory (USMCA monthly), monthly wts (%)"
label var s3_etr       "S3: + non-USMCA preferences, monthly wts (%)"
label var gap_diversion "Trade diversion (pp)"
label var gap_usmca     "USMCA surge (pp)"
label var gap_others    "All-others preferences (pp)"
label var gap_s0_s3     "Total S0-S3 gap (pp)"

sort ym partner_group
compress
save "$working/counterfactual_by_country.dta", replace
export delimited using "$tables/counterfactual_by_country.csv", replace

* Summary: time-averaged by country
preserve
    collapse (mean) s0_etr s1_etr s2_etr s3_etr ///
                    gap_diversion gap_usmca gap_others, ///
        by(partner_group)

    di as text _n "  === Country-Level Ladder (period average) ==="
    format s0_etr s1_etr s2_etr s3_etr ///
           gap_diversion gap_usmca gap_others %9.2f
    list partner_group s0_etr s1_etr s2_etr s3_etr ///
         gap_diversion gap_usmca gap_others, clean noobs
restore


di as text _n "  05_counterfactual_ladder complete." _n
