* ==============================================================================
* 02_etr_analysis.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Four-tier decomposition of the statutory-actual ETR gap, Shapley
*          decomposition by country, and all figures.
*
* Tiers:
*   1. Statutory ETR (tracker rates x 2024 import weights)
*   2. Statutory ETR (tracker rates x actual monthly weights)
*   3. Census calculated ETR (cal_dut / con_val at HS10 x country)
*   4. Treasury actual ETR (customs duties / imports)
*
* Gap channels:
*   T1 -> T2 = Behavioral (trade diversion + product substitution)
*   T2 -> T3 = Exemptions (USMCA, FTA, specific-rate effects)
*   T3 -> T4 = Timing, enforcement, evasion
*
* Input:
*   $working/merged_analysis.dta
*   $working/revenue_monthly.dta
*
* Output:
*   $working/decomp_monthly.dta     + $tables/decomp_monthly.csv
*   $working/decomp_by_country.dta  + $tables/decomp_by_country.csv
*   $figures/figure1_etr_comparison.png
*   $figures/figure2_gap_bars.png
*   $figures/figure2_gap_stacked.png
* ==============================================================================

di as text _n "=========================================="
di as text "  02_etr_analysis: Decomposition & Figures"
di as text "==========================================" _n


* ======================================================================
* A. FOUR-TIER DECOMPOSITION
* ======================================================================

use "$working/merged_analysis.dta", clear

* --- Tier 1: Statutory ETR, 2024 weights ---

di as text "  [A] Four-tier decomposition..."
di as text "      Tier 1: statutory x 2024 weights"

preserve
    keep if imports > 0
    gen double wtd_rev_2024 = total_rate * imports
    collapse (sum) wtd_rev_2024 imports, by(ym)
    safe_divide wtd_rev_2024 imports tier1
    keep ym tier1
    tempfile tier1
    save `tier1'
restore

* --- Tier 2: Statutory ETR, monthly weights ---

di as text "      Tier 2: statutory x monthly weights"

preserve
    gen double wtd_rev_monthly = total_rate * con_val_mo
    collapse (sum) wtd_rev_monthly con_val_mo, by(ym)
    safe_divide wtd_rev_monthly con_val_mo tier2
    keep ym tier2
    tempfile tier2
    save `tier2'
restore

* --- Tier 3: Census calculated ETR ---

di as text "      Tier 3: Census calculated"

preserve
    collapse (sum) cal_dut_mo con_val_mo, by(ym)
    safe_divide cal_dut_mo con_val_mo tier3
    keep ym tier3
    tempfile tier3
    save `tier3'
restore

* --- Tier 4: Treasury actual ETR ---

di as text "      Tier 4: Treasury actual"

preserve
    use "$working/revenue_monthly.dta", clear
    keep if ym >= $start_ym
    keep ym actual_rate
    rename actual_rate tier4
    tempfile tier4
    save `tier4'
restore

* --- Combine tiers ---

use `tier1', clear
merge 1:1 ym using `tier2', nogenerate
merge 1:1 ym using `tier3', nogenerate
merge 1:1 ym using `tier4', keep(match master) nogenerate

* Validate: all four tiers should have non-missing values
assert _N > 0
foreach v in tier1 tier2 tier3 {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "WARNING: `v' has " r(N) " missing values"
    }
}
di as text "      Combined `=_N' months, tiers 1-4"

* Convert to percentage points
foreach v in tier1 tier2 tier3 tier4 {
    replace `v' = `v' * 100
}

* Gaps (pp)
gen double gap_behavioral = tier1 - tier2
gen double gap_exemptions = tier2 - tier3
gen double gap_timing     = tier3 - tier4
gen double gap_total      = tier1 - tier4

label var tier1          "Statutory ETR, 2024 wts (%)"
label var tier2          "Statutory ETR, monthly wts (%)"
label var tier3          "Census calculated ETR (%)"
label var tier4          "Treasury actual ETR (%)"
label var gap_behavioral "Behavioral gap (T1-T2, pp)"
label var gap_exemptions "Exemptions gap (T2-T3, pp)"
label var gap_timing     "Timing/enforcement gap (T3-T4, pp)"
label var gap_total      "Total gap (T1-T4, pp)"

di as text _n "  === Monthly Decomposition ==="
format tier* gap_* %9.2f
list ym tier1 tier2 tier3 tier4 gap_behavioral gap_exemptions gap_timing, ///
    clean noobs

sort ym
save "$working/decomp_monthly.dta", replace
export delimited using "$tables/decomp_monthly.csv", replace


* ======================================================================
* B. SHAPLEY DECOMPOSITION (between- vs. within-country)
* ======================================================================

di as text _n "  [B] Shapley decomposition by country..."

use "$working/merged_analysis.dta", clear

* Country-level under 2024 weights
preserve
    keep if imports > 0
    gen double wtd_rev_c = total_rate * imports
    collapse (sum) wtd_rev_c imports, by(ym partner_group)
    safe_divide wtd_rev_c imports etr_c_2024
    bysort ym: egen double total_imp = total(imports)
    safe_divide imports total_imp share_c_2024
    keep ym partner_group etr_c_2024 share_c_2024
    tempfile country_2024
    save `country_2024'
restore

* Country-level under monthly weights
preserve
    gen double wtd_rev_c = total_rate * con_val_mo
    collapse (sum) wtd_rev_c con_val_mo, by(ym partner_group)
    safe_divide wtd_rev_c con_val_mo etr_c_monthly
    bysort ym: egen double total_val = total(con_val_mo)
    safe_divide con_val_mo total_val share_c_monthly
    keep ym partner_group etr_c_monthly share_c_monthly
    tempfile country_monthly
    save `country_monthly'
restore

* Shapley formula
use `country_2024', clear
merge 1:1 ym partner_group using `country_monthly', nogenerate

gen double between_c = 0.5 * (etr_c_2024 + etr_c_monthly) * ///
                       (share_c_2024 - share_c_monthly)
gen double within_c  = 0.5 * (share_c_2024 + share_c_monthly) * ///
                       (etr_c_2024 - etr_c_monthly)
gen double total_c = between_c + within_c

* Convert to percentage points
foreach v in etr_c_2024 etr_c_monthly between_c within_c total_c {
    replace `v' = `v' * 100
}
foreach v in share_c_2024 share_c_monthly {
    replace `v' = `v' * 100
}

label var between_c "Between-country (pp)"
label var within_c  "Within-country (pp)"
label var total_c   "Total contribution (pp)"

sort ym partner_group
save "$working/decomp_by_country.dta", replace
export delimited using "$tables/decomp_by_country.csv", replace

* Summary
preserve
    collapse (sum) between_total=between_c within_total=within_c, by(ym)
    di as text _n "  === Shapley: Between vs. Within (pp) ==="
    format between_total within_total %9.2f
    list ym between_total within_total, clean noobs
restore


* ======================================================================
* C. FIGURES (S0 -> S1 -> Treasury decomposition)
* ======================================================================
*
* Computes S0/S1/S2 from counterfactual CSVs (produced by R data pull):
*   S0 = USMCA-2024 rates x 2024 weights (statutory baseline)
*   S1 = USMCA-2024 rates x actual monthly weights (+ trade diversion)
*   S2 = USMCA-monthly rates x actual monthly weights (+ USMCA surge)
*   T  = Treasury actual ETR

di as text _n "  [C] Computing counterfactual tiers and generating figures..."

** Import counterfactual rates: USMCA frozen at 2024
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

** Import counterfactual rates: USMCA at monthly shares
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

** Load 2024 weights
use "$working/weights_2024.dta", clear
keep hs10 cty_code imports
sort hs10 cty_code
tempfile wt_2024
save `wt_2024'

** Load monthly trade data
use "$working/merged_analysis.dta", clear
keep ym hs10 cty_code con_val_mo
keep if ym >= $start_ym & ym <= $end_ym
sort ym hs10 cty_code
tempfile monthly_data
save `monthly_data'

** S0: USMCA-2024 x 2024 weights
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
tempfile fig_s0
save `fig_s0'

** S1: USMCA-2024 x monthly weights
di as text "      S1: USMCA-2024 x monthly weights"
use `monthly_data', clear
merge 1:1 hs10 cty_code ym using `cf_2024', ///
    keepusing(rate_usmca2024) keep(match master) nogenerate
replace rate_usmca2024 = 0 if missing(rate_usmca2024)
gen double wtd = rate_usmca2024 * con_val_mo
collapse (sum) num=wtd den=con_val_mo, by(ym)
safe_divide num den s1
keep ym s1
tempfile fig_s1
save `fig_s1'

** S2: USMCA-monthly x monthly weights (for USMCA decomposition)
di as text "      S2: USMCA-monthly x monthly weights"
use `monthly_data', clear
merge 1:1 hs10 cty_code ym using `cf_monthly', ///
    keepusing(rate_usmca_monthly) keep(match master) nogenerate
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)
gen double wtd = rate_usmca_monthly * con_val_mo
collapse (sum) num=wtd den=con_val_mo, by(ym)
safe_divide num den s2
keep ym s2
tempfile fig_s2
save `fig_s2'

** Combine with Treasury actual
use `fig_s0', clear
merge 1:1 ym using `fig_s1', nogenerate
merge 1:1 ym using `fig_s2', nogenerate
merge 1:1 ym using "$working/revenue_monthly.dta", ///
    keep(match master) keepusing(actual_rate) nogenerate
rename actual_rate treasury_actual

** Convert to percentage points
foreach v in s0 s1 s2 treasury_actual {
    replace `v' = `v' * 100
}

** Gap channels
gen double gap_diversion    = s0 - s1
gen double gap_s1_treasury  = s1 - treasury_actual if !missing(treasury_actual)
gen double gap_usmca        = s1 - s2
gen double gap_non_usmca    = s2 - treasury_actual if !missing(treasury_actual)

sort ym
tempfile fig_data
save `fig_data'

di as text _n "  === Counterfactual Decomposition ==="
format s0 s1 s2 treasury_actual gap_* %9.2f
list ym s0 s1 treasury_actual gap_diversion gap_s1_treasury, clean noobs


* --- Figure 1: ETR line chart (S0, S1, Treasury) ---

di as text _n "      Figure 1: ETR comparison"

twoway ///
    (connected s0 ym, ///
        mcolor("$color_statutory") lcolor("$color_statutory") ///
        msymbol(circle) msize(small) lwidth(medthick) ///
        lpattern(solid)) ///
    (connected s1 ym, ///
        mcolor("$color_statutory") lcolor("$color_statutory") ///
        msymbol(diamond) msize(small) lwidth(medium) ///
        lpattern(dash)) ///
    (connected treasury_actual ym, ///
        mcolor("$color_actual") lcolor("$color_actual") ///
        msymbol(triangle) msize(small) lwidth(medthick) ///
        lpattern(solid)) ///
    , ///
    legend(order( ///
        1 "Statutory (USMCA 2024, 2024 wts)" ///
        2 "Statutory (USMCA 2024, monthly wts)" ///
        3 "Actual ETR (Treasury)") ///
        rows(3) size(small) position(6)) ///
    ytitle("Effective Tariff Rate (%)") ///
    xtitle("") ///
    title("Statutory vs. Actual Effective Tariff Rates") ///
    subtitle("Monthly, Jan 2025 - Feb 2026") ///
    note("Source: U.S. Treasury/Census via Haver Analytics;" ///
         "The Budget Lab Tariff Rate Tracker." ///
         "USMCA utilization shares from USITC DataWeb (SPI S/S+).") ///
    xlabel(, format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure1_etr_comparison.png", replace width(2400)


* --- Figure 2: Gap decomposition stacked bar (S0->S1->Treasury) ---

di as text "      Figure 2: Gap decomposition (stacked)"

graph bar (asis) gap_s1_treasury gap_diversion, ///
    over(ym, relabel( ///
        1 `" "Jan" "2025" "' ///
        2 "Feb" 3 "Mar" 4 "Apr" 5 "May" 6 "Jun" ///
        7 "Jul" 8 "Aug" 9 "Sep" 10 "Oct" 11 "Nov" 12 "Dec" ///
        13 `" "Jan" "2026" "' 14 "Feb") ///
        label(angle(0) labsize(small))) ///
    stack ///
    bar(1, color("$color_gap") fintensity(70)) ///
    bar(2, color("$color_statutory") fintensity(70)) ///
    legend(order( ///
        2 "Trade diversion (S0{&rarr}S1)" ///
        1 "Exemptions + residual (S1{&rarr}Treasury)") ///
        rows(1) size(small) position(6)) ///
    ytitle("Gap (percentage points)") ///
    title("Statutory-Actual ETR Gap Decomposition") ///
    subtitle("Stacked components, Jan 2025 - Feb 2026") ///
    note("Source: The Budget Lab analysis") ///
    graphregion(color(white))

graph export "$figures/figure2_gap_stacked.png", replace width(2400)


* --- Figure 3: S1->Treasury decomposed into USMCA vs non-USMCA ---

di as text "      Figure 3: USMCA vs non-USMCA decomposition"

graph bar (asis) gap_usmca gap_non_usmca, ///
    over(ym, relabel( ///
        1 `" "Jan" "2025" "' ///
        2 "Feb" 3 "Mar" 4 "Apr" 5 "May" 6 "Jun" ///
        7 "Jul" 8 "Aug" 9 "Sep" 10 "Oct" 11 "Nov" 12 "Dec" ///
        13 `" "Jan" "2026" "' 14 "Feb") ///
        label(angle(0) labsize(small))) ///
    stack ///
    bar(1, color("$color_canada") fintensity(80)) ///
    bar(2, color("$color_gray") fintensity(70)) ///
    legend(order( ///
        1 "USMCA surge (S1{&rarr}S2)" ///
        2 "Other exemptions + residual (S2{&rarr}Treasury)") ///
        rows(1) size(small) position(6)) ///
    ytitle("Gap (percentage points)") ///
    title("Exemptions Gap: USMCA vs. Non-USMCA") ///
    subtitle("Decomposition of S1{&rarr}Treasury gap, Jan 2025 - Feb 2026") ///
    note("USMCA surge = increase in CA/MX preference claiming" ///
         "relative to 2024 baseline (DataWeb SPI S/S+ shares).") ///
    graphregion(color(white))

graph export "$figures/figure3_usmca_decomp.png", replace width(2400)


* ======================================================================
* D. CENSUS ETR DIAGNOSTIC
* ======================================================================
*
* Compare Census calculated ETR (cal_dut_mo / con_val_mo) at HS10 x country
* with the statutory rate incorporating actual USMCA behavior (USMCA-monthly
* shares from counterfactual_usmca_monthly.csv). This is the "S1 with
* updated USMCA" rate — the best estimate of what duties should be if the
* tracker rates and USMCA utilization are correct.

di as text _n "  [D] Census ETR diagnostic..."

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

** Merge USMCA-monthly counterfactual rate (statutory with actual USMCA behavior)
merge 1:1 hs10 cty_code ym using `cf_monthly', ///
    keepusing(rate_usmca_monthly) keep(match master) nogenerate
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)

** Compute Census ETR if not already present
capture confirm variable census_etr
if _rc != 0 {
    safe_divide cal_dut_mo con_val_mo census_etr
}

** Classification variables (using USMCA-monthly rate as statutory benchmark)
gen byte has_trade      = (con_val_mo > 0 & !missing(con_val_mo))
gen byte has_duty       = (cal_dut_mo > 0 & !missing(cal_dut_mo))
gen byte has_statutory   = (rate_usmca_monthly > 0 & !missing(rate_usmca_monthly))
gen byte census_positive = (census_etr > 0 & !missing(census_etr))

** Gap: Census ETR - statutory rate with actual USMCA (pp)
gen double etr_gap_pp = (census_etr - rate_usmca_monthly) * 100

** Categories
gen str20 category = ""
replace category = "match"            if abs(etr_gap_pp) <= 2 & has_statutory
replace category = "census_higher"    if etr_gap_pp > 2 & has_statutory
replace category = "statutory_higher" if etr_gap_pp < -2 & has_statutory
replace category = "census_zero"      if !census_positive & has_statutory & has_trade
replace category = "no_statutory"     if !has_statutory & has_trade

** Monthly summary
di as text _n "  === Census vs. Statutory ETR by Month ==="
di as text "  (HS10 x country observations, 2pp tolerance)"

preserve
    keep if has_trade

    gen byte is_match      = (category == "match")
    gen byte is_cen_higher = (category == "census_higher")
    gen byte is_stat_higher = (category == "statutory_higher")
    gen byte is_cen_zero    = (category == "census_zero")

    collapse ///
        (count) n_obs = has_trade ///
        (sum)   n_match = is_match ///
                n_census_higher = is_cen_higher ///
                n_statutory_higher = is_stat_higher ///
                n_census_zero = is_cen_zero, ///
        by(ym)

    gen double pct_match       = n_match / n_obs * 100
    gen double pct_cen_higher  = n_census_higher / n_obs * 100
    gen double pct_stat_higher = n_statutory_higher / n_obs * 100
    gen double pct_cen_zero    = n_census_zero / n_obs * 100

    format pct_* %9.1f
    list ym n_obs pct_match pct_cen_higher pct_stat_higher pct_cen_zero, ///
        clean noobs

    export delimited using "$tables/census_etr_diagnostic_monthly.csv", replace
restore

** Value-weighted summary: what share of import VALUE has each anomaly?
di as text _n "  === Value-Weighted Census ETR Anomalies ==="

preserve
    keep if has_trade

    gen double val_match       = con_val_mo * (abs(etr_gap_pp) <= 2 & has_statutory)
    gen double val_cen_higher  = con_val_mo * (etr_gap_pp > 2 & has_statutory)
    gen double val_stat_higher = con_val_mo * (etr_gap_pp < -2 & has_statutory)
    gen double val_cen_zero    = con_val_mo * (!census_positive & has_statutory)

    collapse ///
        (sum) total_val = con_val_mo ///
              val_match val_cen_higher val_stat_higher val_cen_zero, ///
        by(ym)

    foreach v in match cen_higher stat_higher cen_zero {
        gen double pct_`v' = val_`v' / total_val * 100
    }

    format pct_* %9.1f
    list ym pct_match pct_cen_higher pct_stat_higher pct_cen_zero, ///
        clean noobs

    export delimited using "$tables/census_etr_diagnostic_value_weighted.csv", replace
restore

** Zoom in on Census > statutory cases: what's driving them?
di as text _n "  === Census > Statutory: Top Anomalies by Import Value ==="

preserve
    keep if etr_gap_pp > 2 & has_statutory & has_trade

    ** Aggregate to HS2 x partner_group x month for readability
    gen str2 hs2_diag = substr(hs10, 1, 2)
    collapse ///
        (sum)   imports = con_val_mo ///
                census_duty = cal_dut_mo ///
                statutory_duty_impl = tariff_revenue_statutory ///
        (count) n_products = con_val_mo, ///
        by(ym hs2_diag partner_group)

    safe_divide census_duty imports census_etr_agg
    safe_divide statutory_duty_impl imports statutory_etr_agg
    replace census_etr_agg = census_etr_agg * 100
    replace statutory_etr_agg = statutory_etr_agg * 100

    gsort -imports
    di as text "  Top 20 HS2 x country x month (by import value, Census > Statutory + 2pp):"
    format imports %15.0fc
    format census_etr_agg statutory_etr_agg %9.2f
    list ym hs2_diag partner_group n_products imports ///
         census_etr_agg statutory_etr_agg in 1/20, clean noobs

    export delimited using "$tables/census_etr_anomalies_detail.csv", replace
restore

** Census ETR = 0 when statutory > 0: how much trade is this?
di as text _n "  === Census ETR = 0 with Positive Statutory Rate ==="

preserve
    keep if !census_positive & has_statutory & has_trade

    collapse ///
        (sum) imports = con_val_mo ///
        (count) n_products = con_val_mo, ///
        by(ym partner_group)

    gsort ym -imports
    format imports %15.0fc
    list ym partner_group n_products imports, clean noobs sepby(ym)

    export delimited using "$tables/census_etr_zero_anomalies.csv", replace
restore


di as text _n "  02_etr_analysis complete." _n
