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
*   $figures/figure2_gap_stacked.png
*   $figures/figure3_usmca_decomp.png
*
*   Section D -- Census vs statutory-monthly-USMCA comparison:
*     $figures/figure_A_overall.png
*     $figures/figure_B_partner_facets.png
*     $figures/figure_C_gap_by_partner.png
*     $tables/cmp_overall_monthly.csv
*     $tables/cmp_partner_monthly.csv
*     $tables/cmp_hs2_ranking.csv
*     $tables/cmp_top_hs10_anomalies.csv
*     $tables/cmp_2x2_monthly.csv           (D5: 2x2 zero-pattern, overall)
*     $tables/cmp_2x2_partner_monthly.csv   (D5: 2x2 zero-pattern, by partner)
*     $tables/cmp_2x2_hs2_monthly.csv       (D5: 2x2 zero-pattern, by HS2)
*     $tables/cmp_gap_quantiles_monthly.csv (D6: value-weighted |gap| quantiles)
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

* Validate: Tiers 1-3 are by construction non-missing; assert.
* Tier 4 may be short if Treasury revenue lags — warn and flag.
assert _N > 0
foreach v in tier1 tier2 tier3 {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "ERROR: `v' has " r(N) " missing values (should be 0)"
        error 459
    }
}
qui count if missing(tier4)
if r(N) > 0 {
    di as error "WARNING: tier4 (Treasury) missing for " r(N) ///
        " of `=_N' months — gap_total will be missing for those months"
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

** Import counterfactual rates: USMCA at monthly shares
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
    graphregion(color(white))

graph export "$figures/figure3_usmca_decomp.png", replace width(2400)


* ======================================================================
* D. CENSUS vs STATUTORY (MONTHLY USMCA) COMPARISON
* ======================================================================
*
* Clean comparison between:
*   ETR_stat   = rate_usmca_monthly weighted by monthly con_val (statutory
*                rate with USMCA applied at the month's actual utilization)
*   ETR_census = cal_dut_mo / con_val_mo (duties Census reports as collected)
*
* Three aggregation levels:
*   (i)  Overall monthly
*   (ii) Partner group x month
*   (iii) HS2 chapter x month (and HS2 x partner)
*
* Outputs:
*   Fig A -- results/figures/figure_A_overall.png
*   Fig B -- results/figures/figure_B_partner_facets.png
*   Fig C -- results/figures/figure_C_gap_by_partner.png
*   Tbl 1 -- results/tables/cmp_overall_monthly.csv
*   Tbl 2 -- results/tables/cmp_partner_monthly.csv
*   Tbl 3a -- results/tables/cmp_hs2_ranking.csv (HS2 contribution to gap)
*   Tbl 3b -- results/tables/cmp_top_hs10_anomalies.csv

di as text _n "  [D] Census vs. Statutory (monthly USMCA) comparison..."

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

** Sanity: rate_usmca_monthly comes from 01 (merge with cf_usmca_monthly.dta).
capture confirm variable rate_usmca_monthly
if _rc != 0 {
    di as error "ERROR: rate_usmca_monthly not found. Re-run 01_etr_clean.do."
    error 111
}

** Recompute census_etr at the row level to be safe
safe_divide cal_dut_mo con_val_mo census_etr

** Numerators/denominators for collapsed ETRs
gen double stat_rev_row = rate_usmca_monthly * con_val_mo
gen double cens_rev_row = cal_dut_mo


* ----------------------------------------------------------------------
* D1. Overall monthly comparison (Tbl 1 + Fig A)
* ----------------------------------------------------------------------

di as text "      D1. Overall monthly..."

preserve
    collapse (sum) stat_num=stat_rev_row cens_num=cens_rev_row ///
                   total_val=con_val_mo, ///
        by(ym)

    safe_divide stat_num total_val etr_stat
    safe_divide cens_num total_val etr_census

    ** Bring in Treasury actual for reference
    merge 1:1 ym using "$working/revenue_monthly.dta", ///
        keep(match master) keepusing(actual_rate) nogenerate
    rename actual_rate etr_treasury

    foreach v in etr_stat etr_census etr_treasury {
        replace `v' = `v' * 100
    }

    gen double gap_stat_census       = etr_stat - etr_census
    gen double gap_census_treasury   = etr_census - etr_treasury
    gen double gap_stat_treasury     = etr_stat - etr_treasury

    label var etr_stat             "Statutory ETR, monthly USMCA (%)"
    label var etr_census            "Census calculated ETR (%)"
    label var etr_treasury          "Treasury actual ETR (%)"
    label var gap_stat_census       "Statutory - Census (pp)"
    label var gap_census_treasury   "Census - Treasury (pp)"
    label var gap_stat_treasury     "Statutory - Treasury (pp)"

    format etr_* gap_* %9.2f
    di as text "  === Tbl 1: Overall monthly comparison ==="
    list ym etr_stat etr_census etr_treasury ///
         gap_stat_census gap_census_treasury, clean noobs

    save "$working/cmp_overall_monthly.dta", replace
    export delimited using "$tables/cmp_overall_monthly.csv", replace

    ** --- Fig A: overall line chart ---
    twoway ///
        (connected etr_stat ym, ///
            mcolor("$color_statutory") lcolor("$color_statutory") ///
            msymbol(circle) msize(small) lwidth(medthick) lpattern(solid)) ///
        (connected etr_census ym, ///
            mcolor("$color_gap") lcolor("$color_gap") ///
            msymbol(diamond) msize(small) lwidth(medium) lpattern(solid)) ///
        (connected etr_treasury ym, ///
            mcolor("$color_actual") lcolor("$color_actual") ///
            msymbol(triangle) msize(small) lwidth(medium) lpattern(dash)) ///
        , ///
        legend(order( ///
            1 "Statutory (tracker, monthly USMCA)" ///
            2 "Census (cal. duty / cons. value)" ///
            3 "Treasury actual") ///
            rows(3) size(small) position(6)) ///
        ytitle("Effective Tariff Rate (%)") ///
        xtitle("") ///
        title("Statutory vs. Census vs. Actual ETR") ///
        subtitle("Monthly, Jan 2025 - Feb 2026") ///
        xlabel(, format(%tmMon_CCYY) angle(45)) ///
        ylabel(, format(%9.0f)) ///
        yscale(range(0)) ///
        graphregion(color(white)) plotregion(margin(small))

    graph export "$figures/figure_A_overall.png", replace width(2400)
restore


* ----------------------------------------------------------------------
* D2. Partner group x month (Tbl 2 + Fig B + Fig C)
* ----------------------------------------------------------------------

di as text "      D2. Partner group x month..."

preserve
    collapse (sum) stat_num=stat_rev_row cens_num=cens_rev_row ///
                   total_val=con_val_mo, ///
        by(ym partner_group)

    safe_divide stat_num total_val etr_stat
    safe_divide cens_num total_val etr_census

    foreach v in etr_stat etr_census {
        replace `v' = `v' * 100
    }
    gen double gap_pp = etr_stat - etr_census

    label var etr_stat  "Statutory ETR, monthly USMCA (%)"
    label var etr_census "Census calculated ETR (%)"
    label var gap_pp    "Gap: Statutory - Census (pp)"

    save "$working/cmp_partner_monthly.dta", replace
    export delimited using "$tables/cmp_partner_monthly.csv", replace

    ** Clean short partner-group code (safe for variable names)
    gen str2 pg_short = ""
    replace pg_short = "CN" if partner_group == "China"
    replace pg_short = "CA" if partner_group == "Canada"
    replace pg_short = "MX" if partner_group == "Mexico"
    replace pg_short = "EU" if partner_group == "EU"
    replace pg_short = "JP" if partner_group == "Japan"
    replace pg_short = "KR" if partner_group == "S. Korea"
    replace pg_short = "UK" if partner_group == "UK"
    replace pg_short = "RW" if partner_group == "ROW"

    ** --- Fig B: 8-panel facet by partner group ---
    encode partner_group, gen(pg_id)

    twoway ///
        (connected etr_stat ym, ///
            mcolor("$color_statutory") lcolor("$color_statutory") ///
            msymbol(circle) msize(vsmall) lwidth(medium) lpattern(solid)) ///
        (connected etr_census ym, ///
            mcolor("$color_gap") lcolor("$color_gap") ///
            msymbol(diamond) msize(vsmall) lwidth(medium) lpattern(solid)) ///
        , ///
        by(pg_id, ///
            cols(4) ///
            title("Statutory (monthly USMCA) vs. Census ETR by Partner") ///
            subtitle("Monthly, Jan 2025 - Feb 2026") ///
            note("") ///
            graphregion(color(white))) ///
        legend(order( ///
            1 "Statutory (monthly USMCA)" ///
            2 "Census") rows(1) size(small) position(6)) ///
        ytitle("ETR (%)") xtitle("") ///
        xlabel(, format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
        ylabel(, labsize(vsmall))

    graph export "$figures/figure_B_partner_facets.png", replace width(3000)

    ** --- Fig C: overall gap decomposed by partner group contribution ---
    ** Partner p's pp contribution to overall gap =
    **   100 * (stat_num_p - cens_num_p) / total_val_all
    bysort ym: egen double total_val_all = total(total_val)
    gen double gap_contrib_pp = 100 * (stat_num - cens_num) / total_val_all

    keep ym pg_short gap_contrib_pp
    reshape wide gap_contrib_pp, i(ym) j(pg_short) string

    ** All 8 partner columns are created by reshape (gap_contrib_ppCN, etc.).
    ** Rename for convenience.
    foreach pg in CN CA MX EU JP KR UK RW {
        capture rename gap_contrib_pp`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
    }

    graph bar (asis) pg_CN pg_CA pg_MX pg_EU pg_JP pg_KR pg_UK pg_RW, ///
        over(ym, label(angle(45) labsize(vsmall))) ///
        stack ///
        bar(1, color("$color_china"))  ///
        bar(2, color("$color_canada")) ///
        bar(3, color("$color_mexico")) ///
        bar(4, color("$color_eu"))     ///
        bar(5, color("$color_japan"))  ///
        bar(6, color("$color_skorea")) ///
        bar(7, color("$color_uk"))     ///
        bar(8, color("$color_row"))    ///
        legend(order(1 "China" 2 "Canada" 3 "Mexico" 4 "EU" ///
                     5 "Japan" 6 "S. Korea" 7 "UK" 8 "ROW") ///
               rows(1) size(vsmall) position(6)) ///
        ytitle("Gap contribution (pp of overall ETR)") ///
        title("Statutory - Census gap, by partner group") ///
        subtitle("Monthly contribution to overall-ETR gap, pp") ///
        graphregion(color(white))

    graph export "$figures/figure_C_gap_by_partner.png", replace width(2400)
restore


* ----------------------------------------------------------------------
* D3. HS2 chapter ranking (Tbl 3a)
* ----------------------------------------------------------------------

di as text "      D3. HS2 chapter ranking..."

preserve
    ** Aggregate over the whole window for a single ranked table
    gen double stat_num_row = rate_usmca_monthly * con_val_mo
    collapse (sum) stat_num = stat_num_row ///
                   cens_num = cal_dut_mo ///
                   total_val = con_val_mo, ///
        by(hs2)

    destring hs2, gen(hs2_num) force
    label values hs2_num hs2_lbl

    safe_divide stat_num total_val etr_stat
    safe_divide cens_num total_val etr_census
    replace etr_stat = etr_stat * 100
    replace etr_census = etr_census * 100

    gen double gap_pp = etr_stat - etr_census
    ** Dollar-weighted contribution to overall gap (in USD)
    gen double gap_usd = stat_num - cens_num

    label var etr_stat   "Statutory ETR, monthly USMCA (%)"
    label var etr_census "Census ETR (%)"
    label var gap_pp     "Chapter-level gap (pp)"
    label var gap_usd    "Chapter-level gap in $ (stat - census)"
    label var total_val  "Total imports, analysis window (USD)"

    gsort -gap_usd
    format total_val gap_usd %20.0fc
    format etr_stat etr_census gap_pp %9.2f

    di as text "  === Tbl 3a: HS2 chapter gap ranking (top 25 by $ gap) ==="
    list hs2_num total_val etr_stat etr_census gap_pp gap_usd in 1/25, ///
        clean noobs

    export delimited using "$tables/cmp_hs2_ranking.csv", replace
restore


* ----------------------------------------------------------------------
* D4. Top HS10 x country anomalies (Tbl 3b)
* ----------------------------------------------------------------------

di as text "      D4. Top HS10 x country anomalies..."

preserve
    ** Aggregate over the window at HS10 x country
    collapse (sum) stat_num = stat_rev_row ///
                   cens_num = cens_rev_row ///
                   total_val = con_val_mo, ///
        by(hs10 cty_code partner_group)

    safe_divide stat_num total_val etr_stat
    safe_divide cens_num total_val etr_census
    replace etr_stat = etr_stat * 100
    replace etr_census = etr_census * 100

    gen double gap_pp  = etr_stat - etr_census
    gen double gap_usd = stat_num - cens_num
    gen double abs_usd = abs(gap_usd)

    keep if total_val > 0

    gsort -abs_usd
    format total_val gap_usd %20.0fc
    format etr_stat etr_census gap_pp %9.2f

    di as text "  === Tbl 3b: Top 30 HS10 x country by |gap x value| ==="
    list hs10 partner_group total_val etr_stat etr_census gap_pp gap_usd ///
        in 1/30, clean noobs

    keep in 1/500
    export delimited using "$tables/cmp_top_hs10_anomalies.csv", replace
restore


* ----------------------------------------------------------------------
* D5. 2x2 cross-tab: {stat = 0 / > 0} x {cens = 0 / > 0}
* ----------------------------------------------------------------------
*
* Restricted to active trade cells (con_val_mo > 0). Four mutually
* exclusive buckets:
*   bothzero     stat = 0, cens = 0    True MFN-free trade
*   bothpos      stat > 0, cens > 0    Direct rate gap (preference / exemption)
*   trackermiss  stat = 0, cens > 0    Unmodeled duties (AD/CVD, AVE errors,
*                                      Section 201, etc.)
*   impfriction  stat > 0, cens = 0    Implementation friction (timing,
*                                      exemption, Ch 98, evasion)
*
* Outputs (count and value-weighted shares):
*   $tables/cmp_2x2_monthly.csv           by ym
*   $tables/cmp_2x2_partner_monthly.csv   by ym x partner_group
*   $tables/cmp_2x2_hs2_monthly.csv       by ym x HS2

di as text "      D5. 2x2 cross-tab (stat-zero x cens-zero)..."

preserve
    keep if con_val_mo > 0 & !missing(con_val_mo)

    gen byte stat_pos = (rate_usmca_monthly > 0 & !missing(rate_usmca_monthly))
    gen byte cens_pos = (cal_dut_mo > 0 & !missing(cal_dut_mo))

    gen str12 bucket = ""
    replace bucket = "bothzero"    if stat_pos == 0 & cens_pos == 0
    replace bucket = "bothpos"     if stat_pos == 1 & cens_pos == 1
    replace bucket = "trackermiss" if stat_pos == 0 & cens_pos == 1
    replace bucket = "impfriction" if stat_pos == 1 & cens_pos == 0

    gen byte  one   = 1
    gen double w_val = con_val_mo

    tempfile base
    save `base', replace

    * --- D5a. Overall, by ym ---
    use `base', clear
    collapse (sum) n = one val = w_val, by(ym bucket)
    reshape wide n val, i(ym) j(bucket) string

    foreach b in bothzero bothpos trackermiss impfriction {
        foreach p in n val {
            capture confirm variable `p'`b'
            if _rc != 0 gen double `p'`b' = 0
            replace `p'`b' = 0 if missing(`p'`b')
        }
    }
    gen double n_total   = nbothzero + nbothpos + ntrackermiss + nimpfriction
    gen double val_total = valbothzero + valbothpos + valtrackermiss + valimpfriction
    foreach b in bothzero bothpos trackermiss impfriction {
        gen double pct_n_`b'   = 100 * n`b'   / n_total
        gen double pct_val_`b' = 100 * val`b' / val_total
    }

    order ym n_total val_total ///
          nbothzero nbothpos ntrackermiss nimpfriction ///
          valbothzero valbothpos valtrackermiss valimpfriction ///
          pct_n_bothzero pct_n_bothpos pct_n_trackermiss pct_n_impfriction ///
          pct_val_bothzero pct_val_bothpos pct_val_trackermiss pct_val_impfriction

    format val* n_total %20.0fc
    format pct_* %6.2f

    di as text "  === Tbl D5a: 2x2 cross-tab, overall (% of $) ==="
    list ym pct_val_bothzero pct_val_bothpos ///
             pct_val_trackermiss pct_val_impfriction, clean noobs

    export delimited using "$tables/cmp_2x2_monthly.csv", replace

    * --- D5b. By partner_group x ym ---
    use `base', clear
    collapse (sum) n = one val = w_val, by(ym partner_group bucket)
    reshape wide n val, i(ym partner_group) j(bucket) string

    foreach b in bothzero bothpos trackermiss impfriction {
        foreach p in n val {
            capture confirm variable `p'`b'
            if _rc != 0 gen double `p'`b' = 0
            replace `p'`b' = 0 if missing(`p'`b')
        }
    }
    gen double n_total   = nbothzero + nbothpos + ntrackermiss + nimpfriction
    gen double val_total = valbothzero + valbothpos + valtrackermiss + valimpfriction
    foreach b in bothzero bothpos trackermiss impfriction {
        gen double pct_n_`b'   = 100 * n`b'   / n_total
        gen double pct_val_`b' = 100 * val`b' / val_total
    }

    format val* n_total %20.0fc
    format pct_* %6.2f

    export delimited using "$tables/cmp_2x2_partner_monthly.csv", replace

    * --- D5c. By HS2 x ym ---
    use `base', clear
    collapse (sum) n = one val = w_val, by(ym hs2 bucket)
    reshape wide n val, i(ym hs2) j(bucket) string

    foreach b in bothzero bothpos trackermiss impfriction {
        foreach p in n val {
            capture confirm variable `p'`b'
            if _rc != 0 gen double `p'`b' = 0
            replace `p'`b' = 0 if missing(`p'`b')
        }
    }
    gen double n_total   = nbothzero + nbothpos + ntrackermiss + nimpfriction
    gen double val_total = valbothzero + valbothpos + valtrackermiss + valimpfriction
    foreach b in bothzero bothpos trackermiss impfriction {
        gen double pct_n_`b'   = 100 * n`b'   / n_total
        gen double pct_val_`b' = 100 * val`b' / val_total
    }

    format val* n_total %20.0fc
    format pct_* %6.2f

    export delimited using "$tables/cmp_2x2_hs2_monthly.csv", replace
restore


* ----------------------------------------------------------------------
* D6. Value-weighted |gap| distribution by month
* ----------------------------------------------------------------------
*
* At the HS10 x country x month cell,
*     gap_pp = 100 * (rate_usmca_monthly - census_etr).
* Restricted to cells with positive trade (con_val_mo > 0). Quantiles
* and share-within-threshold are weighted by con_val_mo.
*
* "X% of import $ fall within Y pp of the statutory rate" is the
* headline validity statistic for T3 as a cell-level rate proxy.
*
* Output:
*   $tables/cmp_gap_quantiles_monthly.csv

di as text "      D6. |gap| distribution by month (value-weighted)..."

preserve
    keep if con_val_mo > 0 & !missing(con_val_mo)
    safe_divide cal_dut_mo con_val_mo census_etr
    gen double gap_pp  = 100 * (rate_usmca_monthly - census_etr)
    replace   gap_pp   = 0 if missing(gap_pp)
    gen double abs_gap = abs(gap_pp)

    tempname pf
    tempfile qres
    postfile `pf' ym total_val n_cells ///
                  p10 p25 p50 p75 p90 p95 p99 ///
                  sh_lt_0p5 sh_lt_1 sh_lt_2 sh_lt_5 sh_lt_10 ///
                  using `qres', replace

    levelsof ym, local(months)
    foreach m of local months {
        quietly {
            summarize con_val_mo if ym == `m'
            local tv = r(sum)
            local nc = r(N)

            _pctile abs_gap if ym == `m' [aw=con_val_mo], ///
                percentiles(10 25 50 75 90 95 99)
            local p10 = r(r1)
            local p25 = r(r2)
            local p50 = r(r3)
            local p75 = r(r4)
            local p90 = r(r5)
            local p95 = r(r6)
            local p99 = r(r7)

            summarize con_val_mo if ym == `m' & abs_gap <= 0.5
            local sh_0p5 = 100 * r(sum) / `tv'
            summarize con_val_mo if ym == `m' & abs_gap <= 1
            local sh_1   = 100 * r(sum) / `tv'
            summarize con_val_mo if ym == `m' & abs_gap <= 2
            local sh_2   = 100 * r(sum) / `tv'
            summarize con_val_mo if ym == `m' & abs_gap <= 5
            local sh_5   = 100 * r(sum) / `tv'
            summarize con_val_mo if ym == `m' & abs_gap <= 10
            local sh_10  = 100 * r(sum) / `tv'

            post `pf' (`m') (`tv') (`nc') ///
                      (`p10') (`p25') (`p50') (`p75') (`p90') (`p95') (`p99') ///
                      (`sh_0p5') (`sh_1') (`sh_2') (`sh_5') (`sh_10')
        }
    }
    postclose `pf'

    use `qres', clear
    format ym %tm
    format total_val %20.0fc
    format p* sh_* %7.2f

    label var total_val  "Imports in active cells (USD)"
    label var n_cells    "HS10 x country cells (active)"
    label var p10        "p10 |gap| (pp)"
    label var p25        "p25 |gap| (pp)"
    label var p50        "Median |gap| (pp)"
    label var p75        "p75 |gap| (pp)"
    label var p90        "p90 |gap| (pp)"
    label var p95        "p95 |gap| (pp)"
    label var p99        "p99 |gap| (pp)"
    label var sh_lt_0p5  "Share of $ with |gap| < 0.5 pp"
    label var sh_lt_1    "Share of $ with |gap| < 1 pp"
    label var sh_lt_2    "Share of $ with |gap| < 2 pp"
    label var sh_lt_5    "Share of $ with |gap| < 5 pp"
    label var sh_lt_10   "Share of $ with |gap| < 10 pp"

    di as text "  === Tbl D6: |gap| quantiles by month (value-weighted) ==="
    list ym p50 p90 sh_lt_1 sh_lt_5 sh_lt_10, clean noobs

    save "$working/cmp_gap_quantiles_monthly.dta", replace
    export delimited using "$tables/cmp_gap_quantiles_monthly.csv", replace
restore


di as text _n "  02_etr_analysis complete." _n
