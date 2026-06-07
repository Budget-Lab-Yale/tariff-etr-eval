* ==============================================================================
* XX_gtap_trade_validation.do
* Creator: John Iselin (with Claude)
* Date: June 2026
* Purpose: Validate GTAP-predicted import-share reallocation against realized
*          trade. For each monthly tariff policy in the GTAP output, compare the
*          GTAP-predicted change in source-region import shares to the actual
*          change (each month vs the 2024 baseline), and correlate them.
*
* Inputs:
*   data/gtap_output/trade_weights_by_month.csv   (GTAP predicted shares)
*   data/gtap_output/gtap_commodity_dictionary.csv (commodity labels)
*   data/gtap_output/hs10_gtap_crosswalk.csv       (HS10 -> GTAP commodity)
*   data/gtap_output/country_partner_mapping.csv   (cty_code -> GTAP region)
*   data/working/merged_analysis.dta               (actual HS10 x cty x month trade)
*
* Outputs:
*   results/tables/gtap_actual_cell_compare.csv    (cell-level merged comparison)
*   results/tables/gtap_actual_corr.csv            (per-month + pooled correlations)
*   results/figures/figure_gtap_actual_scatter.png (by-month scatter)
*
* Notes on design choices:
*  - REGION MATCH. GTAP reports 8 source regions {china, canada, mexico, eu, uk,
*    japan, ftrow (other FTA partners), row}. We map the panel's Census cty_code
*    to those 8 regions with country_partner_mapping.csv (the concordance GTAP
*    itself uses); any cty_code not listed is "row". This gives a full 8-region
*    match, with ftrow and row separated.
*  - BASELINE. GTAP baseline_share is a fixed pre-tariff equilibrium. The actual
*    analog is the 2024 fixed basket (`imports`, constant across months in the
*    panel). Actual "post" is each month's consumption value (`con_val_mo`).
*  - We compare CHANGES IN SHARES (region's share of total US imports of the
*    commodity), the object GTAP reports as share_change.
*  - Comparison universe is merchandise only: the ~20 GTAP services commodities
*    have no HS codes and drop out at the crosswalk merge, as do Ch.98/99 lines.
* ==============================================================================

version 17.0
clear all
set more off

* --- Paths (works standalone or under the 00_etr_eval.do orchestrator) ---
if "${dir}" == "" global dir "C:/Users/ji252/Documents/GitHub/tariff-etr-eval/"
local gtap "${dir}data/gtap_output"
local work "${dir}data/working"
local tab  "${dir}results/tables"
local fig  "${dir}results/figures"
cap mkdir "`tab'"
cap mkdir "`fig'"
cap set scheme plotplainblind

* ==============================================================================
* 1. GTAP predictions: load and label (all 8 source regions kept)
* ==============================================================================
* 1a. Commodity dictionary -> tempfile keyed on lowercase commodity code.
import delimited "`gtap'/gtap_commodity_dictionary.csv", varnames(1) clear
gen commodity = lower(gtap_code)
keep commodity description aggregate_sector is_manufacturing is_durable ///
     is_nondurable is_advanced
tempfile dict
save `dict'

* 1b. Trade weights + labels.
import delimited "`gtap'/trade_weights_by_month.csv", varnames(1) clear
* write_csv encodes NA as the literal "NA", so the non-traded `dwe` commodity's
* blank shares force these columns to import as string -> destring them.
destring baseline_share postsim_share share_change baseline_imports ///
         postsim_imports, replace force
merge m:1 commodity using `dict', keep(master match) nogen

* Calendar month -> Stata monthly date.
gen yr = real(substr(month, 1, 4))
gen mo = real(substr(month, 6, 2))
gen ym = ym(yr, mo)
format ym %tm

* Keep all 8 GTAP source regions; the country mapping (Section 2) lets the actual
* side match ftrow and row separately. trade_weights is already one row per cell.
rename source_region region
rename (baseline_share postsim_share share_change baseline_imports postsim_imports) ///
       (gbase_share gpost_share gchange gbase_imp gpost_imp)
keep ym commodity region gbase_share gpost_share gchange gbase_imp gpost_imp ///
     description aggregate_sector is_manufacturing

tempfile gtap_pred
save `gtap_pred'

* ==============================================================================
* 2. Actual trade: aggregate HS10 x country x month up to commodity x region
* ==============================================================================
* 2a. HS10 -> GTAP commodity crosswalk (force string to keep leading zeros).
import delimited "`gtap'/hs10_gtap_crosswalk.csv", varnames(1) stringcols(_all) clear
keep hs10 gtap_code_lc
* "NA" is the literal write_csv missing token (Ch.98/99 lines: no GTAP mapping).
drop if gtap_code_lc == "NA" | gtap_code_lc == ""
rename gtap_code_lc commodity
duplicates drop hs10, force          // one GTAP commodity per HS10
tempfile xwalk
save `xwalk'

* 2a'. Census cty_code -> GTAP's 8 regions (anything not listed = row).
import delimited "`gtap'/country_partner_mapping.csv", varnames(1) clear
tostring cty_code, replace
keep cty_code partner
tempfile ctymap
save `ctymap'

* 2b. Load the realized panel (keep only what we need) and map to GTAP cells.
use hs10 cty_code ym con_val_mo imports using "`work'/merged_analysis.dta", clear

* cty_code -> GTAP region; unmatched countries fall into "row".
capture confirm string variable cty_code
if _rc tostring cty_code, replace
merge m:1 cty_code using `ctymap', keep(master match) nogen
gen region = partner
replace region = "row" if missing(region) | region == ""
drop partner

merge m:1 hs10 using `xwalk', keep(match) nogen   // keep merchandise only

* 2c. Actual 2024 baseline shares (imports is the fixed 2024 value; dedup the
*     hs10 x cty cell so months with missing rows don't distort the base).
preserve
    collapse (mean) imports, by(hs10 cty_code commodity region)
    collapse (sum)  imports, by(commodity region)
    bysort commodity (region): egen base_tot = total(imports)
    gen abase_share = imports / base_tot
    rename imports abase_imp
    keep commodity region abase_share abase_imp
    tempfile actual_base
    save `actual_base'
restore

* 2d. Actual monthly shares.
collapse (sum) con_val_mo, by(ym commodity region)
bysort ym commodity (region): egen post_tot = total(con_val_mo)
gen apost_share = con_val_mo / post_tot
rename con_val_mo apost_imp

merge m:1 commodity region using `actual_base', keep(master match) nogen
gen achange = apost_share - abase_share

tempfile actual
save `actual'

* ==============================================================================
* 3. Merge actual to GTAP and assemble the cell-level comparison
* ==============================================================================
use `gtap_pred', clear
merge 1:1 ym commodity region using `actual', keep(match) nogen

label var gchange  "GTAP predicted share change"
label var achange  "Actual share change (vs 2024)"
order ym commodity region aggregate_sector description ///
      gbase_share gpost_share gchange abase_share apost_share achange
sort ym commodity region

export delimited using "`tab'/gtap_actual_cell_compare.csv", replace
di as txt "Cell-level comparison -> `tab'/gtap_actual_cell_compare.csv (" _N " rows)"

* ==============================================================================
* 4. Correlate actual vs GTAP-predicted share change, per policy month
* ==============================================================================
* Unweighted Pearson + Spearman, and a Pearson weighted by 2024 import value
* (so large trade cells count more). One row per GTAP policy month + a pooled row.
tempname pf
postfile `pf' str8 month int ym_n long n double pearson double spearman ///
        double pearson_wtd using "`tab'/_corr_tmp.dta", replace

levelsof ym, local(months)
foreach m of local months {
    local lbl : display %tm `m'
    quietly count if ym == `m' & !missing(achange, gchange)
    local n = r(N)
    local pe = .
    local sp = .
    local pw = .
    if `n' > 2 {
        quietly correlate achange gchange if ym == `m'
        local pe = r(rho)
        quietly spearman achange gchange if ym == `m'
        local sp = r(rho)
        quietly correlate achange gchange [aw=abase_imp] if ym == `m' & abase_imp > 0
        local pw = r(rho)
    }
    post `pf' ("`lbl'") (`m') (`n') (`pe') (`sp') (`pw')
}
* Pooled across all months.
quietly count if !missing(achange, gchange)
local n = r(N)
quietly correlate achange gchange
local pe = r(rho)
quietly spearman achange gchange
local sp = r(rho)
quietly correlate achange gchange [aw=abase_imp] if abase_imp > 0
local pw = r(rho)
post `pf' ("pooled") (.) (`n') (`pe') (`sp') (`pw')
postclose `pf'

use "`tab'/_corr_tmp.dta", clear
format pearson spearman pearson_wtd %6.3f
list month n pearson spearman pearson_wtd, sepby(month) noobs abbreviate(12)
export delimited using "`tab'/gtap_actual_corr.csv", replace
erase "`tab'/_corr_tmp.dta"
di as txt "Correlations -> `tab'/gtap_actual_corr.csv"

* ==============================================================================
* 5. By-month scatter: actual vs predicted share change (with 45-degree line)
* ==============================================================================
use `gtap_pred', clear
merge 1:1 ym commodity region using `actual', keep(match) nogen
* by() panel titles use value labels (not the %tm format), so attach month labels
capture label drop ymlab
levelsof ym, local(ms)
foreach m of local ms {
    local yy = year(dofm(`m'))
    local mm = month(dofm(`m'))
    label define ymlab `m' "`yy'm`mm'", add
}
label values ym ymlab
twoway (scatter achange gchange, msize(vsmall) mcolor("0 114 178%50")) ///
       (function y = x, range(gchange) lcolor("213 94 0") lpattern(dash)), ///
       by(ym, title("Actual vs GTAP-predicted import-share change") ///
              subtitle("Each point = commodity x source region; dashed = 45{superscript:o}") ///
              note("Share change vs 2024 baseline. Merchandise commodities; 8 source regions.") ///
              legend(off)) ///
       xtitle("GTAP predicted {&Delta}share") ytitle("Actual {&Delta}share") ///
       xsize(9) ysize(6.5)
graph export "`fig'/figure_gtap_actual_scatter.png", replace width(1800)
di as txt "Scatter -> `fig'/figure_gtap_actual_scatter.png"

di as result "XX_gtap_trade_validation.do complete."
