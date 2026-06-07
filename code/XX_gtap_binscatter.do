* ==============================================================================
* XX_gtap_binscatter.do
* Creator: John Iselin (with Claude)
* Date: June 2026
* Purpose: Binned-scatter version of figure_gtap_actual_scatter, built with the
*          binscatter command (Stepner). For each policy month, binscatter plots
*          20-quantile bin means of actual vs GTAP-predicted import-share change
*          plus a linear fit; we loop over months and graph-combine into facets.
*          One unweighted figure and one weighted by 2024 import value.
*
* Requires: binscatter (ssc install binscatter).
* Input:    results/tables/gtap_actual_cell_compare.csv  (from XX_gtap_trade_validation.do)
* Output:   results/figures/figure_gtap_actual_binscatter.png      (unweighted)
*           results/figures/figure_gtap_actual_binscatter_wtd.png  (value-weighted)
*
* Note: binscatter has no addplot option, so the 45-degree reference line from the
* raw scatter is not drawn here; the per-panel linear fit (orange) shows the slope.
* ==============================================================================

version 17.0
clear all
set more off

if "${dir}" == "" global dir "C:/Users/ji252/Documents/GitHub/tariff-etr-eval/"
local tab "${dir}results/tables"
cap set scheme plotplainblind
cap graph set window fontface "Times New Roman"

* --- Load the cell-level comparison ---
import delimited "`tab'/gtap_actual_cell_compare.csv", varnames(1) clear
destring gchange achange abase_imp, replace force   // "NA" tokens -> missing
drop if missing(gchange, achange)

* Month string ("2025m7") -> numeric monthly date for ordered facets + labels.
gen ymn = monthly(ym, "YM")
capture label drop ymlab
levelsof ymn, local(ms)
foreach m of local ms {
    local yy = year(dofm(`m'))
    local mm = month(dofm(`m'))
    label define ymlab `m' "`yy'm`mm'", add
}
label values ymn ymlab

* --- Helper: one faceted binscatter (loop months, then graph combine) ---
*     `wt' = "" or "[aw=abase_imp]" ; `suffix' = file tag ; `note' = footnote
capture program drop draw_bs
program define draw_bs
    args wt suffix note
    local glist
    levelsof ymn, local(ms)
    foreach m of local ms {
        local lab : label ymlab `m'
        * binscatter color options take style NAMES, not RGB triples.
        binscatter achange gchange if ymn == `m' `wt', ///
            linetype(lfit) mcolors(navy) lcolors(cranberry) msymbols(O) ///
            title("`lab'", size(medium)) xtitle("") ytitle("") ///
            xscale(range(-.3 .3)) yscale(range(-.3 .3)) ///
            xlabel(-.3 0 .3) ylabel(-.3 0 .3) ///
            name(bs_`m', replace) nodraw
        local glist `glist' bs_`m'
    }
    graph combine `glist', cols(3) imargin(small) ///
        title("Actual vs GTAP-predicted import-share change (binscatter)") ///
        subtitle("20-quantile bins of predicted {&Delta}share per month; line = linear fit") ///
        b1title("GTAP predicted {&Delta}share") l1title("Actual {&Delta}share") ///
        note("`note'") xsize(9) ysize(7)
    graph export "${dir}results/figures/figure_gtap_actual_binscatter`suffix'.png", ///
          replace width(1800)
    graph drop `glist'
end

draw_bs "" "" ///
    "Unweighted bins. Share change vs 2024 baseline; merchandise; 8 source regions."
draw_bs "[aw=abase_imp]" "_wtd" ///
    "Bins weighted by 2024 import value. Share change vs 2024 baseline; merchandise; 8 source regions."

di as result "Binscatters -> figure_gtap_actual_binscatter[_wtd].png"
