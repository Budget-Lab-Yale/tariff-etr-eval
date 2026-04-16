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
*   T:  Treasury actual ETR
*
* Gap channels:
*   S0 -> S1 = Trade diversion (weight shift, USMCA held at 2024 baseline)
*   S1 -> S2 = USMCA surge (preference claiming response to tariff escalation)
*   S2 -> T  = Residual (other FTAs, enforcement, timing, evasion)
*
* USMCA methodology:
*   Rates reconstructed from tracker statutory_rate_* components (pre-USMCA)
*   with product-level USMCA utilization shares from USITC DataWeb SPI data.
*   2024 shares: pre-tariff baseline (~38% CA, ~50% MX trade-weighted).
*   Monthly shares: actual 2025 utilization (~67-68% by H2 2025).
*   Day-weighted across revisions within months by the R data pull.
*
* Input:
*   $raw/counterfactual_usmca2024.csv   (from R/00_pull_raw_data.R)
*   $raw/counterfactual_usmca_monthly.csv
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

* --- S0: USMCA2024 rates x 2024 weights ---
* Expand 2024 weights to a monthly panel, merge counterfactual rates.

di as text "      S0: USMCA-2024 x 2024 weights"

use `wt_2024', clear
local n_months = $end_ym - $start_ym + 1
expand `n_months'
bysort hs10 cty_code: gen int ym = $start_ym + _n - 1
format ym %tm

merge 1:1 hs10 cty_code ym using `cf_2024', ///
    keepusing(rate_usmca2024) keep(match master) nogenerate
replace rate_usmca2024 = 0 if missing(rate_usmca2024)

gen double wtd = rate_usmca2024 * imports
collapse (sum) num=wtd den=imports, by(ym)
safe_divide num den s0
keep ym s0
tempfile tier_s0
save `tier_s0'


* --- S1: USMCA2024 rates x actual monthly weights ---

di as text "      S1: USMCA-2024 x monthly weights"

use `monthly_data', clear
merge 1:1 hs10 cty_code ym using `cf_2024', ///
    keepusing(rate_usmca2024) keep(match master) nogenerate
replace rate_usmca2024 = 0 if missing(rate_usmca2024)

gen double wtd = rate_usmca2024 * con_val_mo
collapse (sum) num=wtd den=con_val_mo, by(ym)
safe_divide num den s1
keep ym s1
tempfile tier_s1
save `tier_s1'


* --- S2: USMCA-monthly rates x actual monthly weights ---

di as text "      S2: USMCA-monthly x monthly weights"

use `monthly_data', clear
merge 1:1 hs10 cty_code ym using `cf_monthly', ///
    keepusing(rate_usmca_monthly) keep(match master) nogenerate
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)

gen double wtd = rate_usmca_monthly * con_val_mo
collapse (sum) num=wtd den=con_val_mo, by(ym)
safe_divide num den s2
keep ym s2
tempfile tier_s2
save `tier_s2'


* ======================================================================
* C. COMBINE TIERS, COMPUTE GAPS, LABEL, AND SAVE
* ======================================================================

di as text _n "  [C] Combining tiers and computing gaps..."

use `tier_s0', clear
merge 1:1 ym using `tier_s1', nogenerate
merge 1:1 ym using `tier_s2', nogenerate
merge 1:1 ym using `treasury', keep(match master) nogenerate

* Validate
assert _N > 0
foreach v in s0 s1 s2 {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "WARNING: `v' has " r(N) " missing values"
    }
}

* Convert to percentage points
foreach v in s0 s1 s2 treasury_actual {
    replace `v' = `v' * 100
}

* Gap channels (pp)
gen double gap_diversion = s0 - s1
gen double gap_usmca     = s1 - s2
gen double gap_residual  = s2 - treasury_actual if !missing(treasury_actual)
gen double gap_total     = s0 - treasury_actual if !missing(treasury_actual)

* Labels
label var s0               "S0: Statutory (USMCA 2024), 2024 wts (%)"
label var s1               "S1: Statutory (USMCA 2024), monthly wts (%)"
label var s2               "S2: Statutory (USMCA monthly), monthly wts (%)"
label var treasury_actual  "T: Treasury actual ETR (%)"
label var gap_diversion    "Trade diversion gap S0-S1 (pp)"
label var gap_usmca        "USMCA surge gap S1-S2 (pp)"
label var gap_residual     "Residual gap S2-T (pp)"
label var gap_total        "Total gap S0-T (pp)"

di as text _n "  === Counterfactual Ladder ==="
format s0 s1 s2 treasury_actual %9.2f
format gap_* %9.2f
list ym s0 s1 s2 treasury_actual, clean noobs

di as text _n "  === Gap Decomposition (pp) ==="
list ym gap_diversion gap_usmca gap_residual gap_total, clean noobs

sort ym
compress
save "$working/counterfactual_ladder.dta", replace
export delimited using "$tables/counterfactual_ladder.csv", replace


* ======================================================================
* D. COUNTRY-LEVEL LADDER
* ======================================================================

di as text _n "  [D] Country-level ladder..."

* --- S0 by country: USMCA2024 x 2024 weights ---

use `wt_2024', clear
local n_months = $end_ym - $start_ym + 1
expand `n_months'
bysort hs10 cty_code: gen int ym = $start_ym + _n - 1
format ym %tm

merge 1:1 hs10 cty_code ym using `cf_2024', ///
    keepusing(rate_usmca2024) keep(match master) nogenerate
replace rate_usmca2024 = 0 if missing(rate_usmca2024)

assign_partner_group cty_code

gen double wtd = rate_usmca2024 * imports
collapse (sum) wtd imports, by(ym partner_group)
safe_divide wtd imports s0_etr
replace s0_etr = s0_etr * 100

tempfile cty_s0
save `cty_s0'

* --- S1 by country: USMCA2024 x monthly weights ---

use `monthly_data', clear
merge 1:1 hs10 cty_code ym using `cf_2024', ///
    keepusing(rate_usmca2024) keep(match master) nogenerate
replace rate_usmca2024 = 0 if missing(rate_usmca2024)

gen double wtd = rate_usmca2024 * con_val_mo
collapse (sum) wtd con_val_mo, by(ym partner_group)
safe_divide wtd con_val_mo s1_etr
replace s1_etr = s1_etr * 100

tempfile cty_s1
save `cty_s1'

* --- S2 by country: USMCA-monthly x monthly weights ---

use `monthly_data', clear
merge 1:1 hs10 cty_code ym using `cf_monthly', ///
    keepusing(rate_usmca_monthly) keep(match master) nogenerate
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)

gen double wtd = rate_usmca_monthly * con_val_mo
collapse (sum) wtd con_val_mo, by(ym partner_group)
safe_divide wtd con_val_mo s2_etr
replace s2_etr = s2_etr * 100

tempfile cty_s2
save `cty_s2'

* --- Combine country-level tiers ---

use `cty_s0', clear
merge 1:1 ym partner_group using `cty_s1', nogenerate
merge 1:1 ym partner_group using `cty_s2', nogenerate

* Country-level gaps (pp)
gen double gap_diversion = s0_etr - s1_etr
gen double gap_usmca     = s1_etr - s2_etr
gen double gap_s0_s2     = s0_etr - s2_etr

label var s0_etr       "S0: Statutory (USMCA 2024), 2024 wts (%)"
label var s1_etr       "S1: Statutory (USMCA 2024), monthly wts (%)"
label var s2_etr       "S2: Statutory (USMCA monthly), monthly wts (%)"
label var gap_diversion "Trade diversion (pp)"
label var gap_usmca     "USMCA surge (pp)"
label var gap_s0_s2     "Total S0-S2 gap (pp)"
label var imports       "2024 imports ($)"

sort ym partner_group
compress
save "$working/counterfactual_by_country.dta", replace
export delimited using "$tables/counterfactual_by_country.csv", replace

* Summary: time-averaged by country
preserve
    collapse (mean) s0_etr s1_etr s2_etr gap_diversion gap_usmca, ///
        by(partner_group)

    di as text _n "  === Country-Level Ladder (period average) ==="
    format s0_etr s1_etr s2_etr gap_diversion gap_usmca %9.2f
    list partner_group s0_etr s1_etr s2_etr gap_diversion gap_usmca, ///
        clean noobs
restore


di as text _n "  05_counterfactual_ladder complete." _n
