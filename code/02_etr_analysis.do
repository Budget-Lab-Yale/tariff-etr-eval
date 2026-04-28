* ==============================================================================
* 02_etr_analysis.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Six-tier decomposition of the statutory-actual ETR gap, Shapley
*          decomposition by country (h2avg-based; legacy), and all figures.
*
* Tiers (S0/S1/S2/S3 from 05_counterfactual_ladder.do; S4 + T computed here):
*   S0: Statutory @ 2024 USMCA shares x 2024 import weights
*   S1: Statutory @ 2024 USMCA shares x actual monthly weights
*   S2: Statutory @ monthly USMCA shares x actual monthly weights
*   S3: + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
*   S4: Census calculated ETR (cal_dut / con_val at HS10 x country, summed)
*   T:  Treasury actual ETR (customs duties / imports)
*
* Gap channels:
*   S0 -> S1 = Trade diversion (composition shift)
*   S1 -> S2 = USMCA surge (CA/MX claim-rate dynamics)
*   S2 -> S3 = All-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
*   S3 -> S4 = Residual (AVE failures, AD/CVD, tracker error, behavioral)
*   S4 -> T  = Timing/enforcement (Treasury vs Census aggregation)
*
* See docs/six_tier_framework_plan.md for derivation and applicability matrix.
* Section B (Shapley) still uses total_rate (h2avg) -- legacy, not the new
* gap_diversion channel; flagged in section header.
*
* Input:
*   $working/counterfactual_ladder.dta   (from 05; provides S0 S1 S2 S3 + T)
*   $working/merged_analysis.dta         (provides S4 = Census collected)
*
* Output:
*   $working/decomp_monthly.dta     + $tables/decomp_monthly.csv
*   $working/decomp_by_country.dta  + $tables/decomp_by_country.csv
*   $figures/figure1_etr_comparison.png
*   $figures/figure2_gap_stacked.png
*   $figures/figure3_usmca_decomp.png
*
*   Section D -- Census vs statutory-monthly-USMCA comparison:
*     $figures/figure4_cmp_overall.png
*     $figures/figure5_cmp_partner_facets.png
*     $figures/figure6_cmp_gap_by_partner.png
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
* A. SIX-TIER DECOMPOSITION
* ======================================================================
*
* Reads S0/S1/S2/S3 + treasury_actual from 05's counterfactual_ladder.dta
* and adds S4 (Census collected ETR), then computes the six-tier channel
* decomposition. S0-S3 are computed in 05 against cf_2024 / cf_monthly /
* cf_all_pref rate panels; we just consume them here to keep tier values
* consistent across 02 and 05.

di as text "  [A] Six-tier decomposition..."

* --- A1. Read S0, S1, S2, S3, T from 05's output ---

di as text "      S0-S3 + T from 05's counterfactual_ladder..."

capture confirm file "${working}/counterfactual_ladder.dta"
if _rc != 0 {
    di as error "ERROR: counterfactual_ladder.dta not found. Run 05 first."
    error 601
}

use "${working}/counterfactual_ladder.dta", clear
keep ym s0 s1 s2 s3 treasury_actual
rename treasury_actual t
tempfile ladder
save `ladder'

* --- A2. S4: Census collected ETR (HS10 x cty x ym -> aggregate) ---

di as text "      S4: Census collected ETR"

use "${working}/merged_analysis.dta", clear
collapse (sum) cal_dut_mo con_val_mo, by(ym)
safe_divide cal_dut_mo con_val_mo s4
replace s4 = s4 * 100
keep ym s4
tempfile s4
save `s4'

* --- A3. Combine ---

use `ladder', clear
merge 1:1 ym using `s4', nogenerate

assert _N > 0
foreach v in s0 s1 s2 s3 s4 {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "ERROR: `v' has " r(N) " missing values (should be 0)"
        error 459
    }
}
qui count if missing(t)
if r(N) > 0 {
    di as error "WARNING: t (Treasury) missing for " r(N) ///
        " of `=_N' months -- gap_total will be missing for those months"
}
di as text "      Combined `=_N' months, tiers S0-S4 + T"

* Channel decomposition (pp). Sequential: each rung subtracts one channel.
* Sign-bearing channels: gap_diversion and gap_usmca can flip negative
* (see docs/six_tier_framework_plan.md sec. 5a). gap_others is structurally
* non-negative by the delta math in R section 3g.
gen double gap_diversion = s0 - s1
gen double gap_usmca     = s1 - s2
gen double gap_others    = s2 - s3
gen double gap_residual  = s3 - s4 if !missing(s4)
gen double gap_timing    = s4 - t  if !missing(s4) & !missing(t)
gen double gap_total     = s0 - t  if !missing(t)

label var s0  "S0: Statutory (USMCA 2024) x 2024 wts (%)"
label var s1  "S1: Statutory (USMCA 2024) x monthly wts (%)"
label var s2  "S2: Statutory (USMCA monthly) x monthly wts (%)"
label var s3  "S3: + non-USMCA preferences x monthly wts (%)"
label var s4  "S4: Census collected ETR (%)"
label var t   "T:  Treasury actual ETR (%)"
label var gap_diversion "Trade diversion (S0-S1, pp)"
label var gap_usmca     "USMCA surge (S1-S2, pp)"
label var gap_others    "All-other preferences (S2-S3, pp)"
label var gap_residual  "Residual (S3-S4, pp)"
label var gap_timing    "Timing/enforcement (S4-T, pp)"
label var gap_total     "Total gap (S0-T, pp)"

di as text _n "  === Six-Tier Decomposition ==="
format s0 s1 s2 s3 s4 t %9.2f
format gap_* %9.2f
list ym s0 s1 s2 s3 s4 t, clean noobs

di as text _n "  === Channel Decomposition (pp) ==="
list ym gap_diversion gap_usmca gap_others gap_residual gap_timing gap_total, ///
    clean noobs

sort ym
compress
save "$working/decomp_monthly.dta", replace
export delimited using "$tables/decomp_monthly.csv", replace


* ======================================================================
* B. SHAPLEY DECOMPOSITION (between- vs. within-country)
* ======================================================================

di as text _n "  [B] Shapley decomposition by country..."

use "$working/merged_analysis.dta", clear

* Country-level under 2024 weights
*   Symmetric inclusion: keep all rows present in merged_analysis (i.e. all
*   HS10 x cty x ym cells with positive monthly trade), even when the 2024
*   weight is zero/missing. Rows with imports == 0 contribute 0 to numerator
*   and denominator and so do not affect the partner-group sums; the
*   alignment matters mainly so the 2024 and monthly panels operate on the
*   same product universe.
preserve
    replace imports = 0 if missing(imports)
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
* C. FIGURES (six-tier ladder)
* ======================================================================
*
* Reads the six-tier decomposition from decomp_monthly.dta (produced in
* Section A above). All tier values are already in pp.
*
* Three figures:
*   Figure 1 -- Line chart: S0, S1, S2, S3, Treasury (5 lines)
*   Figure 2 -- Stacked bar: trade diversion + everything else
*   Figure 3 -- Stacked bar: USMCA surge + all-other preferences + residual
*               (decomposition of S1 -> Treasury gap into 3 channels)

di as text _n "  [C] Generating figures from six-tier decomposition..."

use "${working}/decomp_monthly.dta", clear
keep ym s0 s1 s2 s3 s4 t gap_*

* Sub-channel for figure 3 stacking: gap_others + (S3 -> Treasury residual)
gen double gap_s3_treasury = s3 - t if !missing(t)
gen double gap_s1_treasury = s1 - t if !missing(t)

di as text _n "  === Figure-input ladder ==="
format s0 s1 s2 s3 t gap_* %9.2f
list ym s0 s1 s2 s3 t gap_diversion gap_usmca gap_others, clean noobs


* --- Figure 1: ETR line chart (S0, S1, S2, S3, Treasury) ---

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
    (connected s2 ym, ///
        mcolor("$color_canada") lcolor("$color_canada") ///
        msymbol(square) msize(small) lwidth(medium) ///
        lpattern(shortdash)) ///
    (connected s3 ym, ///
        mcolor("$color_gap") lcolor("$color_gap") ///
        msymbol(triangle) msize(small) lwidth(medium) ///
        lpattern(longdash_dot)) ///
    (connected t ym, ///
        mcolor("$color_actual") lcolor("$color_actual") ///
        msymbol(triangle) msize(small) lwidth(medthick) ///
        lpattern(solid)) ///
    , ///
    legend(order( ///
        1 "S0 (USMCA 2024, 2024 wts)" ///
        2 "S1 (USMCA 2024, monthly wts)" ///
        3 "S2 (USMCA monthly)" ///
        4 "S3 (+ all-other prefs)" ///
        5 "T (Treasury actual)") ///
        rows(5) size(small) position(6)) ///
    ytitle("Effective Tariff Rate (%)") ///
    xtitle("") ///
    title("Statutory vs. Actual Effective Tariff Rates") ///
    subtitle("Six-tier ladder, Jan 2025 - Feb 2026") ///
    xlabel(`=ym(2025,1)' `=ym(2025,4)' `=ym(2025,7)' `=ym(2025,10)' ///
           `=ym(2026,1)' `=ym(2026,2)', format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure1_etr_comparison.png", replace width(2400)


* --- Figure 2: Gap decomposition stacked bar (S0->Treasury, two stacks) ---

di as text "      Figure 2: Gap decomposition (stacked: diversion vs everything else)"

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
        1 "Preferences + residual (S1{&rarr}Treasury)") ///
        rows(1) size(small) position(6)) ///
    ytitle("Gap (percentage points)") ///
    title("Statutory-Actual ETR Gap Decomposition") ///
    subtitle("Stacked components, Jan 2025 - Feb 2026") ///
    graphregion(color(white))

graph export "$figures/figure2_gap_stacked.png", replace width(2400)


* --- Figure 3: S1->Treasury decomposed into USMCA / others / residual (3 stacks) ---

di as text "      Figure 3: USMCA / all-others / residual decomposition"

graph bar (asis) gap_usmca gap_others gap_s3_treasury, ///
    over(ym, relabel( ///
        1 `" "Jan" "2025" "' ///
        2 "Feb" 3 "Mar" 4 "Apr" 5 "May" 6 "Jun" ///
        7 "Jul" 8 "Aug" 9 "Sep" 10 "Oct" 11 "Nov" 12 "Dec" ///
        13 `" "Jan" "2026" "' 14 "Feb") ///
        label(angle(0) labsize(small))) ///
    stack ///
    bar(1, color("$color_canada") fintensity(80)) ///
    bar(2, color("$color_eu")     fintensity(75)) ///
    bar(3, color("$color_gray")   fintensity(70)) ///
    legend(order( ///
        1 "USMCA surge (S1{&rarr}S2)" ///
        2 "All-other preferences (S2{&rarr}S3)" ///
        3 "Residual + timing (S3{&rarr}Treasury)") ///
        rows(2) size(small) position(6)) ///
    ytitle("Gap (percentage points)") ///
    title("Preferences Gap Decomposition") ///
    subtitle("S1{&rarr}Treasury split into USMCA / all-others / residual") ///
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

    graph export "$figures/figure4_cmp_overall.png", replace width(2400)
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

    graph export "$figures/figure5_cmp_partner_facets.png", replace width(3000)

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

    * Build human-readable ym labels (Stata default would show raw integers
    * like 780 = 2025m1; relabel maps each ordered position to the date).
    sort ym
    gen byte ym_idx = _n
    levelsof ym, local(ymlist)
    local relabel_str ""
    local i = 1
    foreach m of local ymlist {
        local ms : di %tmMon_CCYY `m'
        local ms = trim("`ms'")
        local relabel_str `relabel_str' `i' "`ms'"
        local ++i
    }

    graph bar (asis) pg_CN pg_CA pg_MX pg_EU pg_JP pg_KR pg_UK pg_RW, ///
        over(ym_idx, relabel(`relabel_str') ///
                     label(angle(45) labsize(vsmall))) ///
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

    graph export "$figures/figure6_cmp_gap_by_partner.png", replace width(2400)
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


* ======================================================================
* E. BASELINE STATUTORY ETR vs TREASURY ACTUAL  (Paper §4.1, Fig. 1)
* ======================================================================
*
* Headline figure for the paper. Two-line monthly time series:
*   - Statutory ETR at 2024 import weights, with the tracker's production
*     USMCA treatment (h2avg). Computed by aggregating the tracker's daily
*     statutory ETR (which is exactly T_1^h2avg per day, since the tracker
*     uses 2024 fixed weights and h2avg USMCA shares) to monthly means.
*     Day-weighting is implicit: every day in the month enters with equal
*     weight, and 2024 import denominators are static.
*   - Treasury actual ETR (T_4) from `revenue_monthly.dta`.

di as text _n "  [E] Baseline statutory vs Treasury actual (Paper §4.1)..."

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
di as text "      Figure 1: Baseline statutory vs Treasury actual"

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
        1 "Statutory ETR (2024 wts, tracker production)" ///
        2 "Actual ETR (Treasury)") ///
        rows(2) size(small) position(6)) ///
    ytitle("Effective Tariff Rate (%)") ///
    xtitle("") ///
    title("Statutory vs. Actual Effective Tariff Rates") ///
    subtitle("Monthly, 2024 import weights, tracker production USMCA") ///
    xlabel(`=ym(2025,1)' `=ym(2025,4)' `=ym(2025,7)' `=ym(2025,10)' ///
           `=ym(2026,1)' `=ym(2026,2)', format(%tmMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure_baseline_etr.png", replace width(2400)


* ======================================================================
* F. DAILY STATUTORY ETR OVERLAID ON MONTHLY  (Paper §4.5, Fig. 5)
* ======================================================================
*
* Within-month variation: daily T_1^h2avg from the tracker overlaid on the
* monthly aggregate (mean of daily within each month). Demonstrates that
* the day-weighted monthly is well-defined despite within-month policy
* changes (Liberation Day, Phase 2, Phase 3 / SCOTUS, S232 annex).
* xline() markers flag the major policy events.

di as text _n "  [F] Daily ETR overlaid on monthly (Paper §4.5)..."

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
di as text "      Figure 5: Daily ETR overlaid on monthly"

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
    title("Within-Month Variation: Daily vs. Monthly Statutory ETR") ///
    subtitle("Tracker production rates, 2024 import weights") ///
    xlabel(, format(%tdMon_CCYY) angle(45)) ///
    ylabel(, format(%9.0f)) ///
    yscale(range(0)) ///
    graphregion(color(white)) ///
    plotregion(margin(small))

graph export "$figures/figure_daily_overlay.png", replace width(2400)


* ======================================================================
* G. MONTHLY SUMMARY EXCEL  (Paper supplementary table)
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

di as text _n "  [G] Monthly summary Excel..."

* --- G1. Build panel: merged_analysis + USMCA-2024 counterfactual rates ---
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

* --- G2. Compute 6 statutory ETRs + T3 + active pair count, by month ---
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

* --- G3. Override t_24w_base with full-universe value from baseline_etr.dta ---
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

* --- G4. Merge T4 (Treasury) ---
merge 1:1 ym using "$working/revenue_monthly.dta", ///
    keep(match master) keepusing(effective_rate) nogenerate
rename effective_rate t4

* --- G4b. Merge S3 (all-preferences statutory @ monthly weights) ---
* From decomp_monthly.dta -- the new six-tier framework's S3 tier.
preserve
    use "$working/decomp_monthly.dta", clear
    keep ym s3
    rename s3 t_mw_allpref
    tempfile s3_panel
    save `s3_panel'
restore
merge 1:1 ym using `s3_panel', keep(match master) nogenerate

* --- G5. Universe pair count (constant, ~333k) ---
qui describe using "$working/weights_2024.dta", short
gen long n_pairs_universe = r(N)

* --- G6. 2x2 cell counts from D5 output ---
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

* --- G7. Final formatting + restrict to analysis window ---
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

* --- G8. Save Excel + .dta + .csv ---
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


di as text _n "  02_etr_analysis complete." _n
