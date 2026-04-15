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
* C. FIGURES
* ======================================================================

di as text _n "  [C] Generating figures..."

use "$working/decomp_monthly.dta", clear

* --- Figure 1: ETR comparison ---

di as text "      Figure 1: ETR comparison"

twoway ///
    (connected tier1 ym, ///
        mcolor("$color_statutory") lcolor("$color_statutory") ///
        msymbol(circle) msize(small) lwidth(medthick) ///
        lpattern(solid)) ///
    (connected tier2 ym, ///
        mcolor("$color_statutory") lcolor("$color_statutory") ///
        msymbol(diamond) msize(small) lwidth(medium) ///
        lpattern(dash)) ///
    (connected tier3 ym, ///
        mcolor("$color_gap") lcolor("$color_gap") ///
        msymbol(square) msize(small) lwidth(medthick) ///
        lpattern(solid)) ///
    (connected tier4 ym, ///
        mcolor("$color_actual") lcolor("$color_actual") ///
        msymbol(triangle) msize(small) lwidth(medthick) ///
        lpattern(solid)) ///
    , ///
    legend(order( ///
        1 "Statutory (tracker), 2024 wts" ///
        2 "Statutory (tracker), monthly wts" ///
        3 "Census calculated ETR" ///
        4 "Actual ETR (Treasury)") ///
        rows(2) size(small) position(6)) ///
    ytitle("Effective Tariff Rate (%)") ///
    xtitle("") ///
    title("Actual vs. Statutory Effective Tariff Rates") ///
    subtitle("Monthly, Jan 2025 - Feb 2026") ///
    note("Source: U.S. Treasury/Census via Haver Analytics;" ///
         "The Budget Lab Tariff Rate Tracker") ///
    xlabel(, format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure1_etr_comparison.png", replace width(2400)

* --- Figure 2: Gap bars (grouped) ---

di as text "      Figure 2: Gap bars"

twoway ///
    (bar gap_behavioral ym, ///
        barwidth(0.6) color("$color_statutory") fintensity(80)) ///
    (bar gap_exemptions ym, ///
        barwidth(0.4) color("$color_gap") fintensity(80)) ///
    (bar gap_timing ym, ///
        barwidth(0.2) color("$color_actual") fintensity(80)) ///
    , ///
    legend(order( ///
        1 "Behavioral (weight shift)" ///
        2 "Exemptions (USMCA, FTA)" ///
        3 "Timing / enforcement") ///
        rows(1) size(small) position(6)) ///
    ytitle("Gap (percentage points)") ///
    xtitle("") ///
    title("Decomposing the Statutory-Actual ETR Gap") ///
    subtitle("Monthly gap components, Jan 2025 - Feb 2026") ///
    note("Source: The Budget Lab analysis") ///
    xlabel(, format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.1f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure2_gap_bars.png", replace width(2400)

* --- Figure 2 (stacked version) ---

di as text "      Figure 2: Gap bars (stacked)"

graph bar (asis) gap_timing gap_exemptions gap_behavioral, ///
    over(ym, relabel( ///
        1 "Jan" 2 "Feb" 3 "Mar" 4 "Apr" 5 "May" 6 "Jun" ///
        7 "Jul" 8 "Aug" 9 "Sep" 10 "Oct" 11 "Nov" 12 "Dec" ///
        13 "Jan" 14 "Feb") ///
        label(angle(0) labsize(small))) ///
    stack ///
    bar(1, color("$color_actual") fintensity(70)) ///
    bar(2, color("$color_gap") fintensity(70)) ///
    bar(3, color("$color_statutory") fintensity(70)) ///
    legend(order( ///
        3 "Behavioral" ///
        2 "Exemptions" ///
        1 "Timing/enforcement") ///
        rows(1) size(small) position(6)) ///
    ytitle("Gap (percentage points)") ///
    title("Statutory-Actual ETR Gap Decomposition") ///
    subtitle("Stacked components, Jan 2025 - Feb 2026") ///
    note("Source: The Budget Lab analysis") ///
    graphregion(color(white))

graph export "$figures/figure2_gap_stacked.png", replace width(2400)


di as text _n "  02_etr_analysis complete." _n
