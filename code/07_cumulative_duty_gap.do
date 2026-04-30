* ==============================================================================
* 07_cumulative_duty_gap.do
* Creator: John Iselin
* Date: April 2026
* Purpose: One-off figure showing the cumulative dollar difference between
*          Census-reported monthly customs duties (sum of cal_dut_mo across
*          cells; the framework's S4 numerator) and Treasury-reported monthly
*          customs duties (the framework's T numerator), starting February
*          2025.
*
*          Census duties = aggregate of importer-declared calculated duties
*          per HS10 x cty x month from the IMDB bulk data.
*          Treasury duties = monthly customs collections from
*          tariff-impact-tracker (Haver mnemonic; in $M monthly).
*
*          Both are direct monthly dollar amounts; the framework's
*          gap_timing = S4 - T is the rate-level analogue of this difference.
*
* Input:
*   $working/merged_analysis.dta    (HS10 x cty x ym; cal_dut_mo in $)
*   $working/revenue_monthly.dta    (customs_duties in $M)
*
* Output:
*   $tables/cumulative_duty_gap.csv
*   $figures/figure_cumulative_duty_gap.png
*
* Standalone -- not in the orchestrator. Run with:
*   do code/utils/globals.do
*   do code/07_cumulative_duty_gap.do
* ==============================================================================

di as text _n "=========================================="
di as text "  07_cumulative_duty_gap"
di as text "==========================================" _n


* ----------------------------------------------------------------------
* A. Build monthly Census duty totals (in $M for direct comparison)
* ----------------------------------------------------------------------

di as text "  [A] Aggregating Census cal_dut_mo per ym..."

use "$working/merged_analysis.dta", clear
collapse (sum) cal_dut_mo, by(ym)

* cal_dut_mo is in actual dollars per cell. Convert to $M to match Treasury.
gen double census_dut_mil = cal_dut_mo / 1e6
drop cal_dut_mo

label var census_dut_mil "Census duties (sum of cal_dut_mo, \$M)"
tempfile census_monthly
save `census_monthly'


* ----------------------------------------------------------------------
* B. Treasury duty per month (already in $M)
* ----------------------------------------------------------------------

di as text "  [B] Treasury monthly customs duties..."

use "$working/revenue_monthly.dta", clear
keep ym customs_duties
rename customs_duties treasury_dut_mil
label var treasury_dut_mil "Treasury duties (\$M)"
tempfile treasury_monthly
save `treasury_monthly'


* ----------------------------------------------------------------------
* C. Merge, filter to Feb 2025+, compute cumulative
* ----------------------------------------------------------------------

di as text "  [C] Computing cumulative S4 - T dollar gap..."

use `census_monthly', clear
merge 1:1 ym using `treasury_monthly', nogenerate keep(match)

sort ym
keep if ym >= ym(2025, 2)

gen double monthly_diff = census_dut_mil - treasury_dut_mil
gen double cumulative_diff = sum(monthly_diff)

label var monthly_diff    "Monthly Census - Treasury duties (\$M)"
label var cumulative_diff "Cumulative Census - Treasury duties (\$M)"

format monthly_diff cumulative_diff %12.0fc

di as text _n "  === Cumulative duty gap (Census - Treasury, \$M) ==="
list ym census_dut_mil treasury_dut_mil monthly_diff cumulative_diff, ///
    clean noobs

export delimited using "$tables/cumulative_duty_gap.csv", replace


* ----------------------------------------------------------------------
* D. Figure
* ----------------------------------------------------------------------

di as text _n "  [D] Building figure..."

* Two-panel: monthly bars + cumulative line.
* The cumulative is the headline; monthly bars contextualize.
twoway ///
    (bar monthly_diff ym, ///
        color("$color_gap") fintensity(60) barwidth(0.7)) ///
    (line cumulative_diff ym, ///
        lcolor("$color_statutory") lwidth(thick) lpattern(solid)) ///
    , ///
    yline(0, lcolor(gs10) lpattern(dot)) ///
    xline(`=$event_liberation', lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
    xline(`=$event_phase2',     lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
    xline(`=$event_scotus_s122', lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
    legend(order( ///
        2 "Cumulative Census - Treasury (\$M)" ///
        1 "Monthly Census - Treasury (\$M)") ///
        rows(2) size(small) position(11) ring(0)) ///
    ytitle("Duty difference (\$M)") ///
    xtitle("") ///
    title("Census-Reported vs Treasury-Collected Duties") ///
    subtitle("Cumulative difference since February 2025") ///
    xlabel(, format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0fc)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure_cumulative_duty_gap.png", replace width(2400)

di as text _n "  Wrote $figures/figure_cumulative_duty_gap.png"
di as text "  07_cumulative_duty_gap complete." _n
