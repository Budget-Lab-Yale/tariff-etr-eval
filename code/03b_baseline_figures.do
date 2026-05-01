* ==============================================================================
* 03b_baseline_figures.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Paper-output figures and supplementary monthly summary table that
*          reflect TBL's judgment of the optimal portrayal of statutory ETRs
*          for ECONOMIC purposes -- not for the deconstruction / decomposition
*          framework. Statutory rates here are aggregated via the tracker's
*          production daily series (h2avg USMCA shares, 2024 import weights),
*          which is the cleanest single-line representation of the U.S.
*          statutory tariff schedule for an outside reader. Compare to the
*          deconstruction tiers S0-S3 in 02/03 which use orthogonal USMCA-share
*          and weight scenarios chosen to isolate gap channels.
*
* Sections:
*   A. Baseline statutory ETR vs Treasury actual         (Paper §4.1, Fig 1)
*   B. Daily statutory ETR overlaid on monthly average   (Paper §4.5, Fig 5)
*   C. Monthly summary table (Excel + CSV)               (Paper supplement)
*   D. USMCA adjustment explainer                        (Paper §3, story figs)
*       D1: Fig U1, monthly USMCA-applied statutory ETR for CA and MX vs the
*           2024 baseline and H2-2025 baseline reference lines. Shows the
*           July 2025 reporting-pattern shift directly: empirical line moves
*           from near the 2024 baseline to near the H2-2025 baseline.
*       D2: Fig U2, period-averaged S0->S1 gap by partner_group (CA and MX
*           dominate; everyone else ~0).
*
* Inputs:
*   $working/tracker_daily.dta       (per-day statutory ETR, h2avg USMCA)
*   $working/revenue_monthly.dta     (Treasury actual ETR)
*   $working/merged_analysis.dta     (HS10 x cty x ym panel; for §C and §D)
*   $working/decomp_monthly.dta      (S3 tier; for §C supplementary table)
*   $working/baseline_etr.dta        (saved here in §A; consumed by §C)
*   $working/weights_2024.dta        (universe pair count; for §C)
*   $tables/cmp_2x2_monthly.csv      (2x2 zero-pattern; for §C)
*   $raw/counterfactual_usmca2024.csv (rate panel; for §C summary)
*
* Outputs (each figure exported in two versions: <base>.png clean / <base>_titled.png):
*   $working/baseline_etr.dta + $tables/baseline_etr.csv
*   $figures/figure_baseline.png  (was figure_baseline_etr.png)
*   $figures/figure_daily_overlay.png
*   $working/monthly_summary.dta
*   $tables/monthly_summary.csv + $tables/monthly_summary.xlsx
*   $figures/figure_adjustment_explainer.png  (was figure_u1_usmca_adjustment.png)
*   $figures/figure_adjustment_country.png    (was figure_u2_adjustment_by_country.png)
*   $tables/adjustment_by_country.csv
* ==============================================================================

di as text _n "=========================================="
di as text "  03b_baseline_figures: TBL-judgment paper figures"
di as text "==========================================" _n


* ======================================================================
* A. BASELINE STATUTORY ETR vs TREASURY ACTUAL  (Paper §4.1, Fig. 1)
* ======================================================================
*
* TBL judgment: this figure is intended for ECONOMIC interpretation, not
* gap-channel deconstruction. The statutory line uses the tracker's
* production daily ETR (h2avg USMCA shares, 2024 weights), which TBL views
* as the single best-faith answer to "what does the U.S. statutory tariff
* schedule look like over time?" -- it absorbs USMCA at a sensible average
* and uses static weights so the line moves only when the schedule itself
* moves. Do NOT read this figure as one of the framework tiers (S0-S3 in
* 02_counterfactual_ladder.do). It uses different rate / weight choices
* by design.
*
* Two-line monthly time series:
*   - Statutory ETR at 2024 import weights, h2avg USMCA, daily->monthly mean
*   - Treasury actual ETR (T_4) from `revenue_monthly.dta`

di as text _n "  [A] Baseline statutory vs Treasury actual (Paper §4.1)..."

* --- Monthly T_1^h2avg from daily series ---
use "$working/tracker_daily.dta", clear
gen int ym = mofd(daily_date)
format ym %tm
keep if ym >= $start_ym & ym <= $end_ym

collapse (mean) weighted_etr, by(ym)
* tracker stores ratios; convert to percent
replace weighted_etr = weighted_etr * 100
rename weighted_etr t1_h2avg
label var t1_h2avg "Statutory ETR, 2024 wts, h2avg USMCA (%)"

* --- Join Treasury actual ---
merge 1:1 ym using "$working/revenue_monthly.dta", ///
    keep(match master) keepusing(effective_rate) nogenerate
rename effective_rate t4
label var t4 "Treasury actual ETR (%)"

keep ym t1_h2avg t4
order ym t1_h2avg t4
sort ym

* Derived gap
gen double gap = t1_h2avg - t4 if !missing(t4)
label var gap "Statutory - Actual (pp)"

* Save table
format t1_h2avg t4 gap %9.2f
di as text _n "  === Baseline ETR table ==="
list ym t1_h2avg t4 gap, clean noobs

save "$working/baseline_etr.dta", replace
export delimited using "$tables/baseline_etr.csv", replace

* --- Figure ---
di as text "      Figure baseline: Statutory vs Treasury actual"

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Statutory vs. Actual Effective Tariff Rates") subtitle("Monthly, 2024 import weights, tracker production USMCA")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    twoway ///
        (connected t1_h2avg ym, ///
            mcolor("$color_statutory") lcolor("$color_statutory") ///
            msymbol(circle) msize(small) lwidth(medthick) ///
            lpattern(solid)) ///
        (connected t4 ym, ///
            mcolor("$color_actual") lcolor("$color_actual") ///
            msymbol(triangle) msize(small) lwidth(medthick) ///
            lpattern(solid)) ///
        , ///
        legend(order( ///
            1 "Statutory ETR (TBL estimate)" ///
            2 "Actual ETR (Treasury)") ///
            rows(1) size(small) position(6)) ///
        ytitle("Effective Tariff Rate (%)") ///
        xtitle("") ///
        `opt_title' ///
        xlabel(`=ym(2025,1)' `=ym(2025,2)' `=ym(2025,3)' `=ym(2025,4)' ///
               `=ym(2025,5)' `=ym(2025,6)' `=ym(2025,7)' `=ym(2025,8)' ///
               `=ym(2025,9)' `=ym(2025,10)' `=ym(2025,11)' `=ym(2025,12)' ///
               `=ym(2026,1)' `=ym(2026,2)', ///
               format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
        ylabel(, format(%9.0f)) ///
        yscale(range(0)) ///
        graphregion(color(white)) ///
        plotregion(margin(small)) ///
        name(g_baseline, replace)
    graph export "${figures}figure_baseline`sfx'.png", ///
        replace width(2400)
}


* ======================================================================
* B. DAILY STATUTORY ETR OVERLAID ON MONTHLY  (Paper §4.5, Fig. 5)
* ======================================================================
*
* TBL judgment: like §A, this is a paper-output figure tuned for ECONOMIC
* portrayal of the statutory schedule -- demonstrating that within-month
* variation is well-defined despite mid-month policy changes (Liberation
* Day, Phase 2, Phase 3 / SCOTUS, S232 annex). The daily series uses the
* tracker production rates (h2avg USMCA, 2024 weights) for the same reason
* as §A: it isolates schedule changes from claim-rate dynamics. xline()
* markers flag the major policy events.

di as text _n "  [B] Daily ETR overlaid on monthly (Paper §4.5)..."

use "$working/tracker_daily.dta", clear
keep daily_date weighted_etr
keep if daily_date >= dofm($start_ym) & daily_date <= dofm($end_ym + 1) - 1

* Convert to percent
replace weighted_etr = weighted_etr * 100
rename weighted_etr daily_etr
label var daily_etr "Daily statutory ETR (%)"

* Build monthly aggregate (constant within each month)
gen int ym = mofd(daily_date)
format ym %tm
bysort ym (daily_date): egen double monthly_etr = mean(daily_etr)
label var monthly_etr "Monthly mean statutory ETR (%)"

* Mid-month marker for the monthly series (only on the 15th of each month)
gen byte is_mid = (day(daily_date) == 15)
gen double monthly_etr_mid = monthly_etr if is_mid

sort daily_date

* --- Figure ---
di as text "      Figure daily overlay"

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Within-Month Variation: Daily vs. Monthly Statutory ETR") subtitle("Tracker production rates, 2024 import weights")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    twoway ///
        (line daily_etr daily_date, ///
            lcolor("$color_statutory") lwidth(thin) lpattern(solid)) ///
        (scatter monthly_etr_mid daily_date if is_mid, ///
            mcolor("$color_actual") msymbol(diamond) msize(medsmall)) ///
        , ///
        xline(`=$event_liberation', lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
        xline(`=$event_phase2',     lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
        xline(`=$event_phase2_recip', lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
        xline(`=$event_scotus_s122', lcolor(gs10) lpattern(dash) lwidth(vthin)) ///
        legend(order( ///
            1 "Daily statutory ETR" ///
            2 "Monthly mean (mid-month marker)") ///
            rows(2) size(small) position(6)) ///
        ytitle("Effective Tariff Rate (%)") ///
        xtitle("") ///
        `opt_title' ///
        xlabel(, format(%tdMon_CCYY) angle(45)) ///
        ylabel(, format(%9.0f)) ///
        yscale(range(0)) ///
        graphregion(color(white)) ///
        plotregion(margin(small)) ///
        name(g_daily_overlay, replace)
    graph export "${figures}figure_daily_overlay`sfx'.png", ///
        replace width(2400)
}


* ======================================================================
* C. MONTHLY SUMMARY EXCEL  (Paper supplementary table)
* ======================================================================
*
* One row per month, columns:
*   ym, t4 (Treasury), t3 (Census-derived),
*   six statutory ETRs = {USMCA-2024, USMCA-monthly, USMCA-baseline}
*                       x {2024 weights, monthly weights},
*   n_pairs_universe (total HS10xcty pairs in 2024 weight universe),
*   n_pairs_active   (HS10xcty pairs with positive monthly trade),
*   2x2 cell counts (statutory vs Census ETR, zero/positive).
*
* USMCA scenarios:
*   - "USMCA-2024":     2024 annual claim shares (counterfactual_usmca2024.csv)
*   - "USMCA-monthly":  realized monthly claim shares (counterfactual_usmca_monthly.csv)
*   - "USMCA-baseline": tracker production / H2 2025 average shares (h2avg)
*
* Implementation note: 2024-weighted ETRs other than baseline are computed over
* the merged_analysis universe (HS10 x cty pairs with positive monthly trade
* for that month). This understates pairs that traded in 2024 but not in the
* given month. The baseline x 2024-weights cell is overridden with the daily-
* series-derived value from baseline_etr.dta, which uses the full 2024
* universe -- treat that single cell as the gold-standard reference.
*
* The 2x2 grid uses USMCA-monthly statutory rates (matching Section D5):
*   bothzero    : statutory == 0 & Census duty == 0
*   bothpos     : statutory > 0  & Census duty > 0
*   trackermiss : statutory == 0 & Census duty > 0
*   impfriction : statutory > 0  & Census duty == 0

di as text _n "  [C] Monthly summary Excel..."

* --- C1. Build panel: merged_analysis + USMCA-2024 counterfactual rates ---
use "$working/merged_analysis.dta", clear
keep hs10 cty_code ym imports con_val_mo cal_dut_mo total_rate rate_usmca_monthly
rename total_rate rate_h2avg

* Merge in USMCA-2024 monthly day-weighted rates
preserve
    import delimited using "$raw/counterfactual_usmca2024.csv", ///
        clear stringcols(1 2 3)
    capture rename hts10 hs10
    gen year  = real(substr(year_month, 1, 4))
    gen month = real(substr(year_month, 6, 7))
    gen int ym = ym(year, month)
    format ym %tm
    drop year month year_month
    rename total_rate rate_usmca2024
    keep hs10 cty_code ym rate_usmca2024
    sort hs10 cty_code ym
    gisid hs10 cty_code ym     // gtools (faster than isid)
    tempfile cf2024
    save `cf2024'
restore

merge 1:1 hs10 cty_code ym using `cf2024', keep(match master) nogenerate
replace rate_usmca2024 = 0 if missing(rate_usmca2024)

* --- C2. Compute 6 statutory ETRs + T3 + active pair count, by month ---
gen double n24w_h2avg     = rate_h2avg          * imports
gen double n24w_2024usmca = rate_usmca2024      * imports
gen double n24w_moususmca = rate_usmca_monthly  * imports
gen double nmw_h2avg      = rate_h2avg          * con_val_mo
gen double nmw_2024usmca  = rate_usmca2024      * con_val_mo
gen double nmw_moususmca  = rate_usmca_monthly  * con_val_mo

collapse (sum) sum_imports = imports ///
               sum_cvm     = con_val_mo ///
               sum_caldut  = cal_dut_mo ///
               n24w_h2avg n24w_2024usmca n24w_moususmca ///
               nmw_h2avg  nmw_2024usmca  nmw_moususmca ///
        (count) n_pairs_active = imports ///
        , by(ym)

* T3 (Census-derived ETR), in pp
gen double t3 = 100 * sum_caldut / sum_cvm

* Six statutory ETRs in pp
* Naming: t_<weights>_<usmca-scenario>
*   24w  = 2024 weights;  mw  = monthly weights
*   base = baseline (h2avg);  m24 = USMCA-2024;  mm = USMCA-monthly
gen double t_24w_base = 100 * n24w_h2avg     / sum_imports
gen double t_24w_m24  = 100 * n24w_2024usmca / sum_imports
gen double t_24w_mm   = 100 * n24w_moususmca / sum_imports
gen double t_mw_base  = 100 * nmw_h2avg      / sum_cvm
gen double t_mw_m24   = 100 * nmw_2024usmca  / sum_cvm
gen double t_mw_mm    = 100 * nmw_moususmca  / sum_cvm

keep ym t3 t_24w_base t_24w_m24 t_24w_mm t_mw_base t_mw_m24 t_mw_mm n_pairs_active

* --- C3. Override t_24w_base with full-universe value from baseline_etr.dta ---
* baseline_etr.dta carries t1_h2avg derived from the daily series, which uses
* the full 2024 weight universe (not just merged_analysis's positive-trade
* subset). Replace the merged_analysis-derived value for accuracy.
preserve
    use "$working/baseline_etr.dta", clear
    keep ym t1_h2avg
    rename t1_h2avg t_24w_base_full
    tempfile bl
    save `bl'
restore
merge 1:1 ym using `bl', keep(match master) nogenerate
replace t_24w_base = t_24w_base_full if !missing(t_24w_base_full)
drop t_24w_base_full

* --- C4. Merge T4 (Treasury) ---
merge 1:1 ym using "$working/revenue_monthly.dta", ///
    keep(match master) keepusing(effective_rate) nogenerate
rename effective_rate t4

* --- C4b. Merge S3 (all-preferences statutory @ monthly weights) ---
* From decomp_monthly.dta -- the new six-tier framework's S3 tier.
preserve
    use "$working/decomp_monthly.dta", clear
    keep ym s3
    rename s3 t_mw_allpref
    tempfile s3_panel
    save `s3_panel'
restore
merge 1:1 ym using `s3_panel', keep(match master) nogenerate

* --- C5. Universe pair count (constant, ~333k) ---
qui describe using "$working/weights_2024.dta", short
gen long n_pairs_universe = r(N)

* --- C6. 2x2 cell counts from D5 output ---
* D5's CSV stores ym as a string ("2025m1"); convert to numeric monthly before merge.
preserve
    import delimited using "$tables/cmp_2x2_monthly.csv", clear stringcols(1)
    gen int ym_num = monthly(ym, "YM")
    format ym_num %tm
    drop ym
    rename ym_num ym
    keep ym nbothzero nbothpos ntrackermiss nimpfriction
    tempfile twox2
    save `twox2'
restore
merge 1:1 ym using `twox2', keep(match master) nogenerate

* --- C7. Final formatting + restrict to analysis window ---
keep if ym >= $start_ym & ym <= $end_ym
sort ym
order ym t4 t3 ///
      t_24w_base t_mw_base ///
      t_24w_m24  t_mw_m24 ///
      t_24w_mm   t_mw_mm ///
      t_mw_allpref ///
      n_pairs_universe n_pairs_active ///
      nbothzero nbothpos ntrackermiss nimpfriction

format t* %9.2f
format n_pairs* nbothzero nbothpos ntrackermiss nimpfriction %12.0fc

label var ym               "Month"
label var t4               "Treasury actual ETR (%)"
label var t3               "Census-derived ETR (%)"
label var t_24w_base       "Statutory: baseline USMCA x 2024 wts (%)"
label var t_mw_base        "Statutory: baseline USMCA x monthly wts (%)"
label var t_24w_m24        "Statutory: 2024 USMCA x 2024 wts (%)"
label var t_mw_m24         "Statutory: 2024 USMCA x monthly wts (%)"
label var t_24w_mm         "Statutory: monthly USMCA x 2024 wts (%)"
label var t_mw_mm          "Statutory: monthly USMCA x monthly wts (%)"
label var t_mw_allpref     "Statutory: monthly USMCA + all-other prefs x monthly wts (S3, %)"
label var n_pairs_universe "HS10 x cty pairs (2024 universe)"
label var n_pairs_active   "HS10 x cty pairs (positive monthly trade)"
label var nbothzero        "2x2: stat=0 & cens=0 (count)"
label var nbothpos         "2x2: stat>0 & cens>0 (count)"
label var ntrackermiss     "2x2: stat=0 & cens>0 (count)"
label var nimpfriction     "2x2: stat>0 & cens=0 (count)"

di as text _n "  === Monthly summary table ==="
list ym t4 t3 t_24w_base t_mw_base, clean noobs

* --- C8. Save Excel + .dta + .csv ---
* Excel: overwrite only the "Summary" sheet, preserve any other tabs (notes,
* charts, custom analysis) the user has added manually. Falls back to a
* file-level replace on the first run when the workbook doesn't yet exist.
save "$working/monthly_summary.dta", replace
export delimited using "$tables/monthly_summary.csv", replace

capture confirm file "$tables/monthly_summary.xlsx"
if _rc {
    export excel using "$tables/monthly_summary.xlsx", ///
        firstrow(varlabels) sheet("Summary") replace
}
else {
    export excel using "$tables/monthly_summary.xlsx", ///
        firstrow(varlabels) sheet("Summary", replace)
}
di as text "      Saved $tables/monthly_summary.xlsx (`=_N' months, Summary sheet)"


* ======================================================================
* D. USMCA ADJUSTMENT EXPLAINER  (Paper §3, story figures)
* ======================================================================
*
* The framework absorbs USMCA claim-rate normalization upfront in S0 -> S1:
* S0 holds USMCA at 2024 baseline shares (~38% CA, ~50% MX), S1 stabilizes
* at H2-2025 shares (~89% both). Most of the movement is retrospective --
* firms filed USMCA claims late, and a July 2025 reporting change made the
* underlying utilization visible. These figures explain that backstory
* without burdening the main waterfall (S1 -> T) with claim-rate dynamics.
*
*   Fig U1 (D1): Monthly statutory ETR for CA and MX under three USMCA
*                scenarios -- 2024 baseline (rate_2024), H2-2025 baseline
*                (rate_h2avg), and empirical monthly (rate_usmca_monthly).
*                The rate_usmca_monthly line drops sharply mid-2025 as
*                claim rates ramp; the two reference lines bracket it.
*   Fig U2 (D2): Period-averaged S0 - S1 gap by partner group. CA and MX
*                carry the gap; everyone else is essentially zero.

di as text _n "  [D] USMCA adjustment explainer..."

* --- D1. Build CA + MX monthly statutory ETRs under three USMCA scenarios ---

di as text "      D1. CA and MX statutory ETR under {2024, monthly, h2avg} USMCA"

tempfile etr_2024 etr_monthly etr_h2avg

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym
keep if inlist(cty_code, "$cty_canada", "$cty_mexico")

preserve
    compute_tier, ratevar(rate_2024)          weightvar(con_val_mo) ///
        outfile(`etr_2024')   outvar(etr_2024)   byvar(partner_group) percent
restore
preserve
    compute_tier, ratevar(rate_usmca_monthly) weightvar(con_val_mo) ///
        outfile(`etr_monthly') outvar(etr_monthly) byvar(partner_group) percent
restore
preserve
    compute_tier, ratevar(rate_h2avg)         weightvar(con_val_mo) ///
        outfile(`etr_h2avg')  outvar(etr_h2avg)  byvar(partner_group) percent
restore

use `etr_2024', clear
merge 1:1 ym partner_group using `etr_monthly', nogenerate
merge 1:1 ym partner_group using `etr_h2avg',   nogenerate

label var etr_2024    "USMCA 2024 baseline (%)"
label var etr_monthly "USMCA monthly empirical (%)"
label var etr_h2avg   "USMCA H2-2025 baseline (%)"

format etr_* %9.2f
sort partner_group ym
list partner_group ym etr_2024 etr_monthly etr_h2avg, clean noobs

** Two-panel facet: CA and MX
encode partner_group, gen(pg_id)

* Color choices: 2024 baseline (purple) and h2avg baseline (navy) need to be
* visually distinct so the reader can see the empirical line move between them.
foreach v in titled clean {
    if "`v'" == "titled" {
        local fig_t "USMCA Adjustment: CA and MX Statutory ETR by USMCA Scenario"
        local fig_st "Empirical line shifts from 2024 baseline to H2-2025 baseline mid-2025"
        local sfx "_titled"
    }
    else {
        local fig_t ""
        local fig_st ""
        local sfx ""
    }
    twoway ///
        (connected etr_2024 ym, ///
            mcolor("$color_japan") lcolor("$color_japan") ///
            msymbol(circle) msize(vsmall) lwidth(medium) lpattern(dash)) ///
        (connected etr_monthly ym, ///
            mcolor("$color_actual") lcolor("$color_actual") ///
            msymbol(diamond) msize(vsmall) lwidth(medthick) lpattern(solid)) ///
        (connected etr_h2avg ym, ///
            mcolor("$color_statutory") lcolor("$color_statutory") ///
            msymbol(square) msize(vsmall) lwidth(medium) lpattern(dash)) ///
        , ///
        by(pg_id, ///
            cols(2) ///
            title("`fig_t'") ///
            subtitle("`fig_st'") ///
            note("") ///
            graphregion(color(white))) ///
        legend(order( ///
            1 "USMCA (2024) (S0)" ///
            2 "USMCA monthly" ///
            3 "USMCA post-July 2025 (S1+)") ///
            rows(1) size(small) position(6)) ///
        ytitle("Statutory ETR (%)") xtitle("") ///
        xlabel(, format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
        ylabel(, labsize(vsmall))
    graph export "$figures/figure_adjustment_explainer`sfx'.png", replace width(2400)
}


* --- D2. Period-averaged S0 - S1 gap by partner_group (Fig U2) ---

di as text "      D2. Period-averaged adjustment gap by country"

tempfile cty_s0 cty_s1

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

preserve
    compute_tier, ratevar(rate_2024) weightvar(imports) ///
        outfile(`cty_s0') outvar(s0) byvar(partner_group) percent
restore
preserve
    compute_tier, ratevar(rate_h2avg) weightvar(imports) ///
        outfile(`cty_s1') outvar(s1) byvar(partner_group) percent
restore

use `cty_s0', clear
merge 1:1 ym partner_group using `cty_s1', nogenerate

gen double gap_adjustment = s0 - s1

* Period-averaged adjustment gap per country
collapse (mean) s0 s1 gap_adjustment, by(partner_group)

label var s0             "S0 period avg (%)"
label var s1             "S1 period avg (%)"
label var gap_adjustment "USMCA adjustment S0-S1, period avg (pp)"

gsort -gap_adjustment
format s0 s1 gap_adjustment %9.3f

di as text _n "  === USMCA adjustment by country (period mean) ==="
list partner_group s0 s1 gap_adjustment, clean noobs

export delimited using "$tables/adjustment_by_country.csv", replace

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("USMCA Adjustment Gap by Partner Group") subtitle("Where the 2024 -> H2-2025 USMCA shift moves the statutory rate")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    graph hbar (asis) gap_adjustment, ///
        over(partner_group, sort(1) descending) ///
        bar(1, color("$color_canada")) ///
        ytitle("USMCA adjustment (pp; S0 - S1, period avg)") ///
        `opt_title' ///
        graphregion(color(white)) ///
        name(g_adj_country, replace)
    graph export "${figures}figure_adjustment_country`sfx'.png", ///
        replace width(2400)
}


di as text _n "  03b_baseline_figures complete." _n
