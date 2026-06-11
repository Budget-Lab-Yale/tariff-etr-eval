* ==============================================================================
* XX_gtap_corr_breakdown.do
* Creator: John Iselin (with Claude)
* Date: June 2026
* Purpose: Break down the actual-vs-GTAP-predicted import-share-change correlation
*          by source region, by product (GTAP commodity and aggregate sector) to
*          show where GTAP's predicted reallocation tracks realized trade and
*          where it does not. Reports unweighted and import-value-weighted Pearson
*          (pooled across the 8 policy months within each group).
*
* Input:  results/tables/gtap_actual_cell_compare.csv  (from XX_gtap_trade_validation.do)
* Output: results/figures/figure_gtap_corr_by_region.png
*         results/figures/figure_gtap_corr_by_sector.png
*         results/figures/figure_gtap_corr_by_commodity.png
*         results/tables/gtap_corr_breakdown.csv
* ==============================================================================

version 17.0
clear all
set more off

if "${dir}" == "" global dir "C:/Users/ji252/Documents/GitHub/tariff-etr-eval/"
local tab "${dir}results/tables"
local fig "${dir}results/figures"
cap set scheme plotplainblind
cap graph set window fontface "Times New Roman"

import delimited "`tab'/gtap_actual_cell_compare.csv", varnames(1) clear
destring gchange achange abase_imp, replace force
drop if missing(gchange, achange)

* commodity -> description crosswalk, for readable labels on the commodity figure.
preserve
    keep commodity description
    duplicates drop commodity, force
    rename commodity grp
    replace description = grp if missing(description) | description == "NA"
    tempfile commlabels
    save `commlabels'
restore

* ------------------------------------------------------------------------------
* Helper: correlation (unweighted + weighted by 2024 import value) of actual vs
* predicted share change within each level of `varlist', pooled across months.
* Saves a results dataset: dimension grp n pearson pearson_wtd.
* ------------------------------------------------------------------------------
capture program drop corr_group
program define corr_group
    syntax varname, DIM(string) SAVE(string)
    preserve
        tempname pf
        tempfile out
        postfile `pf' str12 dimension str40 grp long n ///
                double pearson double pearson_wtd using "`out'", replace
        levelsof `varlist', local(gs)
        foreach g of local gs {
            quietly count if `varlist' == "`g'" & !missing(achange, gchange)
            local n = r(N)
            local pe = .
            local pw = .
            if `n' >= 3 {
                quietly correlate achange gchange if `varlist' == "`g'"
                local pe = r(rho)
                quietly correlate achange gchange [aw=abase_imp] ///
                        if `varlist' == "`g'" & abase_imp > 0
                local pw = r(rho)
            }
            post `pf' ("`dim'") ("`g'") (`n') (`pe') (`pw')
        }
        postclose `pf'
        use "`out'", clear
        label var pearson      "Unweighted"
        label var pearson_wtd  "Weighted by import value"
        save "`save'", replace
    restore
end

tempfile r_region r_sector r_comm
corr_group region,           dim("region")    save("`r_region'")
corr_group aggregate_sector, dim("sector")    save("`r_sector'")
corr_group commodity,        dim("commodity") save("`r_comm'")

* Attach commodity descriptions (used by the figure and the combined table).
use "`r_comm'", clear
merge m:1 grp using `commlabels', keep(master match) nogen
save "`r_comm'", replace

* ------------------------------------------------------------------------------
* Figure 1: by source region (unweighted vs weighted, sorted)
* ------------------------------------------------------------------------------
use "`r_region'", clear
graph hbar pearson pearson_wtd, over(grp, sort(1) descending label(labsize(small))) ///
    bargap(10) yline(0, lcolor(gs8)) ///
    bar(1, color(navy)) bar(2, color(cranberry)) ///
    ytitle("Correlation of actual vs GTAP-predicted {&Delta}share", size(small)) ///
    ylabel(, labsize(small)) ///
    title("Where GTAP tracks realized trade: by source region", size(medsmall)) ///
    note("Pearson correlation across commodity x month cells within each region; pooled over 2025m7-2026m2.", size(vsmall)) ///
    legend(order(1 "Unweighted" 2 "Weighted by import value") rows(1) position(6) size(small)) ///
    ysize(5) xsize(8)
graph export "`fig'/figure_gtap_corr_by_region.png", replace width(1800)

* ------------------------------------------------------------------------------
* Figure 2: by aggregate sector (unweighted vs weighted)
* ------------------------------------------------------------------------------
use "`r_sector'", clear
gen lbl = grp + " (n=" + string(n) + ")"
graph hbar pearson pearson_wtd, over(lbl, sort(1) descending label(labsize(small))) ///
    bargap(10) yline(0, lcolor(gs8)) ///
    bar(1, color(navy)) bar(2, color(cranberry)) ///
    ytitle("Correlation of actual vs GTAP-predicted {&Delta}share", size(small)) ///
    ylabel(, labsize(small)) ///
    title("Where GTAP tracks realized trade: by product sector", size(medsmall)) ///
    note("Pearson across commodity x region x month cells within each sector. Utilities (n=8) is too thin to read.", size(vsmall)) ///
    legend(order(1 "Unweighted" 2 "Weighted by import value") rows(1) position(6) size(small)) ///
    ysize(4.5) xsize(8)
graph export "`fig'/figure_gtap_corr_by_sector.png", replace width(1800)

* ------------------------------------------------------------------------------
* Figure 3: by GTAP commodity (unweighted, sorted; only groups with enough cells)
* ------------------------------------------------------------------------------
use "`r_comm'", clear
keep if n >= 10                        // drop thin commodities (noisy correlation)
gen lbl = description
replace lbl = grp if missing(lbl)
replace lbl = substr(lbl, 1, 40) if length(lbl) > 40   // keep labels readable
graph hbar pearson, over(lbl, sort(1) descending label(labsize(tiny))) ///
    yline(0, lcolor(gs8)) bar(1, color(navy)) ///
    ytitle("Unweighted correlation, actual vs predicted {&Delta}share", size(small)) ///
    ylabel(, labsize(small)) ///
    title("Where GTAP tracks realized trade: by GTAP commodity", size(small)) ///
    note("Pearson across region x month cells within each commodity (commodities with >=10 cells).", size(vsmall)) ///
    ysize(10) xsize(9)
graph export "`fig'/figure_gtap_corr_by_commodity.png", replace width(1600)

* ------------------------------------------------------------------------------
* Combined table
* ------------------------------------------------------------------------------
use "`r_region'", clear
append using "`r_sector'"
append using "`r_comm'"
gsort dimension -pearson
export delimited using "`tab'/gtap_corr_breakdown.csv", replace

di as result "Correlation breakdown -> 3 figures + gtap_corr_breakdown.csv"
