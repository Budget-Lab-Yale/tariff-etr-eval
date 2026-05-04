* ==============================================================================
* 03_etr_analysis.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Six-tier decomposition of the statutory-actual ETR gap and the
*          framework figures + diagnostic tables built from it.
*
*          The TBL-judgment paper figures (baseline statutory vs Treasury;
*          daily overlay; supplementary monthly summary; USMCA adjustment
*          explainer) live in the sibling script 03b_baseline_figures.do.
*
* Tiers (S0/S1/S2/S3 from 02_counterfactual_ladder.do; S4 + T computed here):
*   S0: Statutory @ USMCA 2024 baseline x 2024 import weights
*   S1: Statutory @ Post-July 2025 USMCA (rate_h2avg) x 2024 import weights
*   S2: Statutory @ Post-July 2025 USMCA (rate_h2avg) x actual monthly weights
*   S3: + non-USMCA preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
*   S4: Census calculated ETR (cal_dut / con_val at HS10 x country, summed)
*   T:  Treasury actual ETR (customs duties / imports)
*
* Gap channels:
*   S0 -> S1 = USMCA adjustment (claim-rate normalization 2024 -> post-July 2025;
*              weights frozen). Mostly retrospective: paperwork caught up
*              after July 2025 reporting changes. Explainer figs in 03b.
*   S1 -> S2 = Trade diversion (composition shift in monthly weights with
*              USMCA stable at h2avg). Main analysis channel; figs D1-D3.
*   S2 -> S3 = All-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
*   S3 -> S4 = Residual (AVE failures, AD/CVD, tracker error, behavioral)
*   S4 -> T  = Timing/enforcement (Treasury vs Census aggregation)
*
* See docs/six_tier_framework_plan.md for derivation and applicability matrix.
*
* Sections:
*   A. Six-tier decomposition (consumes ladder, adds S4, computes channel gaps)
*   B.  S1->S2 trade-diversion Shapley decomposition (country + product lenses)
*       + figs D1, D2, D3
*   B2. S2->S3 other-preferences attribution by group (country + product)
*   B3. S3->S4 residual attribution by group (country + product)
*   B4. Stacked-bar figures O2/O3 (others) and R2/R3 (residual)
*   B5. Unified attribution tables (per-month per-group, all 4 channels)
*   B6. 4-panel attribution facets F2 (country) and F3 (product)
*   C.  Figures 1-3 (six-tier ladder line + stacked bar charts)
*   D. Figures 4-6 + diagnostic tables (S2 vs S4 vs T, partner / HS2 / HS10)
*      D7. Product-group gap (figs P1, P2, P3 + cmp_product_*)
*
* Input:
*   $working/counterfactual_ladder.dta   (from 02; provides S0 S1 S2 S3 + T)
*   $working/merged_analysis.dta         (provides S4 = Census collected;
*                                         also rate_h2avg, rate_2024,
*                                         rate_all_pref panels for Section B
*                                         and Section D compute_tier calls)
*
* Output:
*   $working/decomp_monthly.dta     + $tables/decomp_monthly.csv
*   $working/diversion_by_country.dta + $tables/diversion_by_country_avg.csv
*   $working/diversion_by_product.dta + $tables/diversion_by_product_avg.csv
*   $tables/attribution_by_country.csv
*   $tables/attribution_by_product.csv
*
* Figure naming convention: every figure is exported in two versions --
*   $figures/<base>.png            no titles or subtitles (slides default)
*   $figures/<base>_titled.png     with titles + subtitles (paper draft)
* The `<base>` follows `figure_<topic>[_<partition>]`.
*
* Figures by section:
*
*   Section B (S1->S2 trade-diversion Shapley):
*     figure_diversion_decomp        (aggregate between/within stack)
*     figure_diversion_country       (per-partner contributions)
*     figure_diversion_product       (per-product contributions)
*
*   Section B2/B3/B4 (other channels by group):
*     figure_others_country / figure_others_product       (S2->S3)
*     figure_residual_country / figure_residual_product   (S3->S4)
*
*   Section B6 (4-panel attribution facets):
*     figure_attribution_country     (4 channels x 8 countries)
*     figure_attribution_product     (4 channels x 9 product groups)
*
*   Section C (six-tier ladder framework figures):
*     figure_ladder                  (S0/S1/S2/S3/T line chart)
*     figure_gap_stacked             (USMCA adjustment vs main analytic)
*     figure_channel_stacked         (3-channel S1->T decomposition)
*
*   Section D (S2 vs S4 vs T comparison):
*     figure_s2s4_overall            (3-line aggregate)
*     figure_s2s4_facets_country     (8-panel by partner)
*     figure_s2s4_gap_country        (gap stacked by partner)
*
*   Section D7 (product-side analogues):
*     figure_s2s4_facets_product     (9-panel by product group)
*     figure_s2s4_gap_product        (gap stacked by product)
*     figure_s2s4_heatmap            (period-avg gap, product x partner; needs heatplot)
*
*   Section D8 (S1 vs S2 facets):
*     figure_s1s2_facets_country
*     figure_s1s2_facets_product
*
*   Tables (Section D):
*     cmp_overall_monthly, cmp_partner_monthly, cmp_hs2_ranking,
*     cmp_top_hs10_anomalies, cmp_2x2_monthly, cmp_2x2_partner_monthly,
*     cmp_2x2_hs2_monthly, cmp_gap_quantiles_monthly,
*     cmp_product_monthly, cmp_product_partner_avg
*     cmp_s1s2_country_monthly, cmp_s1s2_product_monthly
* ==============================================================================

di as text _n "=========================================="
di as text "  03_etr_analysis: Decomposition & Figures"
di as text "==========================================" _n


* ======================================================================
* A. SIX-TIER DECOMPOSITION
* ======================================================================
*
* Reads S0/S1/S2/S3 + treasury_actual from 02_counterfactual_ladder.dta
* and adds S4 (Census collected ETR), then computes the six-tier channel
* decomposition. S0-S3 are computed in 02 by applying compute_tier to the
* rate_2024 / rate_h2avg / rate_all_pref columns of merged_analysis; this
* script consumes them so tier values are consistent across all figures.

di as text "  [A] Six-tier decomposition..."

* --- A1. Read S0, S1, S2, S3, T from 02's output ---

di as text "      S0-S3 + T from 02_counterfactual_ladder..."

capture confirm file "${working}/counterfactual_ladder.dta"
if _rc != 0 {
    di as error "ERROR: counterfactual_ladder.dta not found. Run 02 first."
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
* gap_adjustment is mostly one-signed (USMCA claim rates rose 2024 -> post-July 2025
* almost everywhere CA/MX trade existed). gap_diversion is bidirectional
* (negative country-period averages = "reverse diversion"). gap_others is
* structurally non-negative by the delta math in R section 3g. See
* docs/six_tier_framework_plan.md sec. 5a.
gen double gap_adjustment = s0 - s1
gen double gap_diversion  = s1 - s2
gen double gap_others     = s2 - s3
gen double gap_residual   = s3 - s4 if !missing(s4)
gen double gap_timing     = s4 - t  if !missing(s4) & !missing(t)
gen double gap_total      = s0 - t  if !missing(t)

label var s0  "S0: Statutory (USMCA 2024 baseline) x 2024 wts (%)"
label var s1  "S1: Statutory (Post-July 2025 USMCA) x 2024 wts (%)"
label var s2  "S2: Statutory (Post-July 2025 USMCA) x monthly wts (%)"
label var s3  "S3: + non-USMCA preferences x monthly wts (%)"
label var s4  "S4: Census collected ETR (%)"
label var t   "T:  Treasury actual ETR (%)"
label var gap_adjustment "USMCA adjustment (S0-S1, pp)"
label var gap_diversion  "Trade diversion (S1-S2, pp)"
label var gap_others     "All-other preferences (S2-S3, pp)"
label var gap_residual   "Residual (S3-S4, pp)"
label var gap_timing     "Timing/enforcement (S4-T, pp)"
label var gap_total     "Total gap (S0-T, pp)"

di as text _n "  === Six-Tier Decomposition ==="
format s0 s1 s2 s3 s4 t %9.2f
format gap_* %9.2f
list ym s0 s1 s2 s3 s4 t, clean noobs

di as text _n "  === Channel Decomposition (pp) ==="
list ym gap_adjustment gap_diversion gap_others gap_residual gap_timing gap_total, ///
    clean noobs

sort ym
compress
save "$working/decomp_monthly.dta", replace
export delimited using "$tables/decomp_monthly.csv", replace


* ======================================================================
* B. S1 -> S2 TRADE-DIVERSION DECOMPOSITION  (between vs within)
* ======================================================================
*
* S1 -> S2 holds rates fixed at rate_h2avg (USMCA stabilized at post-July 2025
* baseline) and shifts weights from 2024-annual to actual-monthly. The
* entire gap is composition-driven, so Shapley splits it into between-group
* and within-group along any partition. Two complementary lenses:
*
*   Country lens:
*     between-country = shifts in country shares of total imports
*     within-country  = shifts in product mix inside each country
*
*   Product lens:
*     between-product = shifts in product-group shares of total imports
*     within-product  = shifts in country mix inside each product group
*
* Both lenses sum to the same gap_diversion = S1 - S2 from the ladder. The
* country lens isolates "imports shifted away from CA/MX" effects; the
* product lens isolates "imports shifted out of high-tariff steel into
* low-tariff electronics" effects.
*
* See docs/six_tier_framework_plan.md and the Shapley two-way derivation in
* programs.do::compute_diversion_decomp.

di as text _n "  [B] S1 -> S2 trade-diversion Shapley decomposition..."

* --- B1. Country lens ---
di as text "      Country lens (between/within-country)"
use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

preserve
    compute_diversion_decomp, ratevar(rate_h2avg) byvar(partner_group) ///
        outfile("$working/diversion_by_country.dta") outvar_prefix(c)
restore

* --- B2. Product lens ---
di as text "      Product lens (between/within-product)"
preserve
    compute_diversion_decomp, ratevar(rate_h2avg) byvar(product_group) ///
        outfile("$working/diversion_by_product.dta") outvar_prefix(p)
restore

* --- B3. Validate that both lenses sum to gap_diversion from ladder ---
di as text "      Validating decomposition against ladder gap_diversion..."

preserve
    use "$working/counterfactual_ladder.dta", clear
    keep ym gap_diversion
    tempfile lad_div
    save `lad_div'
restore

preserve
    use "$working/diversion_by_country.dta", clear
    collapse (sum) c_between c_within c_total, by(ym)
    merge 1:1 ym using `lad_div', nogenerate
    gen double resid = c_total - gap_diversion
    qui sum resid, detail
    if abs(r(max)) > 1e-3 | abs(r(min)) > 1e-3 {
        di as error "WARNING: country-lens sum differs from gap_diversion by up to " ///
            string(max(abs(r(max)), abs(r(min))), "%9.4f") " pp"
    }
    else {
        di as text "      Country lens: max residual " ///
            string(max(abs(r(max)), abs(r(min))), "%9.6f") " pp (OK)"
    }
restore

preserve
    use "$working/diversion_by_product.dta", clear
    collapse (sum) p_between p_within p_total, by(ym)
    merge 1:1 ym using `lad_div', nogenerate
    gen double resid = p_total - gap_diversion
    qui sum resid, detail
    if abs(r(max)) > 1e-3 | abs(r(min)) > 1e-3 {
        di as error "WARNING: product-lens sum differs from gap_diversion by up to " ///
            string(max(abs(r(max)), abs(r(min))), "%9.4f") " pp"
    }
    else {
        di as text "      Product lens: max residual " ///
            string(max(abs(r(max)), abs(r(min))), "%9.6f") " pp (OK)"
    }
restore

* --- B4. Period-averaged decomp summary CSV (for paper appendix) ---
preserve
    use "$working/diversion_by_country.dta", clear
    collapse (mean) c_between c_within c_total, by(partner_group)
    gsort -c_total
    label var c_between "Between-country avg (pp)"
    label var c_within  "Within-country avg (pp)"
    label var c_total   "Total avg (pp)"
    format c_* %9.3f
    di as text _n "  === Country diversion contributions (period mean) ==="
    list partner_group c_between c_within c_total, clean noobs
    export delimited using "$tables/diversion_by_country_avg.csv", replace
restore

preserve
    use "$working/diversion_by_product.dta", clear
    collapse (mean) p_between p_within p_total, by(product_group)
    gsort -p_total
    label var p_between "Between-product avg (pp)"
    label var p_within  "Within-product avg (pp)"
    label var p_total   "Total avg (pp)"
    format p_* %9.3f
    di as text _n "  === Product diversion contributions (period mean) ==="
    list product_group p_between p_within p_total, clean noobs
    export delimited using "$tables/diversion_by_product_avg.csv", replace
restore


* ======================================================================
* B'. DIVERSION FIGURES (D1, D2, D3)
* ======================================================================

di as text _n "  [B'] Diversion decomposition figures..."

* --- D1. Aggregate decomposition over time (country lens), stacked bar ---
* between + within sum to total by Shapley construction; the stacked bar
* makes the additivity visible.
di as text "      Fig D1: aggregate between/within stacked"
preserve
    use "$working/diversion_by_country.dta", clear
    collapse (sum) c_between c_within, by(ym)
    label var c_between "Between-country (pp)"
    label var c_within  "Within-country, product mix (pp)"

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

    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("Trade Diversion Decomposition: Country Lens") subtitle("Shapley two-way; segments sum to total S1-S2 gap")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) c_between c_within, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_canada")) ///
            bar(2, color("$color_gap")) ///
            legend(order( ///
                1 "Between-country (share shifts)" ///
                2 "Within-country (product mix)") ///
                rows(1) size(small) position(6)) ///
            ytitle("Contribution to S1-S2 gap (pp)") ///
            `opt_title' ///
            yline(0, lcolor(gs10) lpattern(dot)) ///
            graphregion(color(white)) plotregion(margin(small)) ///
            name(g_div_decomp, replace)

        export_fig figure_diversion_decomp`sfx'
    }
restore

* --- D2. Country contributions stacked over time ---
di as text "      Fig D2: country stacked-bar contributions"
preserve
    use "$working/diversion_by_country.dta", clear
    keep ym partner_group c_total

    * Short codes for variable names after reshape
    gen str2 pg_short = ""
    replace pg_short = "CN" if partner_group == "China"
    replace pg_short = "CA" if partner_group == "Canada"
    replace pg_short = "MX" if partner_group == "Mexico"
    replace pg_short = "EU" if partner_group == "EU"
    replace pg_short = "JP" if partner_group == "Japan"
    replace pg_short = "KR" if partner_group == "S. Korea"
    replace pg_short = "UK" if partner_group == "UK"
    replace pg_short = "RW" if partner_group == "ROW"

    drop partner_group
    reshape wide c_total, i(ym) j(pg_short) string
    foreach pg in CN CA MX EU JP KR UK RW {
        capture rename c_total`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
        replace pg_`pg' = 0 if missing(pg_`pg')
    }

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

    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("Trade Diversion: Country Contributions") subtitle("Stacked monthly, signed (positive = adds to gap_diversion)")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
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
            ytitle("Contribution to S1-S2 gap (pp)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_div_country, replace)

        export_fig figure_diversion_country`sfx'
    }
restore

* --- D3. Product contributions stacked over time ---
di as text "      Fig D3: product stacked-bar contributions"
preserve
    use "$working/diversion_by_product.dta", clear
    keep ym product_group p_total

    * Short codes for variable names after reshape
    gen str4 pg_short = ""
    replace pg_short = "stl"  if product_group == "Steel & Aluminum"
    replace pg_short = "auto" if product_group == "Autos & Auto Parts"
    replace pg_short = "elec" if product_group == "Electronics & Machinery"
    replace pg_short = "phrm" if product_group == "Pharmaceuticals"
    replace pg_short = "engy" if product_group == "Energy & Minerals"
    replace pg_short = "chem" if product_group == "Chemicals & Plastics"
    replace pg_short = "appr" if product_group == "Apparel & Textiles"
    replace pg_short = "food" if product_group == "Food & Agriculture"
    replace pg_short = "othr" if product_group == "Other Manufactured"

    drop product_group
    reshape wide p_total, i(ym) j(pg_short) string
    foreach pg in stl auto elec phrm engy chem appr food othr {
        capture rename p_total`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
        replace pg_`pg' = 0 if missing(pg_`pg')
    }

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

    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("Trade Diversion: Product Contributions") subtitle("Stacked monthly, signed (positive = adds to gap_diversion)")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) pg_stl pg_auto pg_elec pg_phrm pg_engy pg_chem ///
                         pg_appr pg_food pg_othr, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_steel"))   ///
            bar(2, color("$color_autos"))   ///
            bar(3, color("$color_elec"))    ///
            bar(4, color("$color_pharma"))  ///
            bar(5, color("$color_energy"))  ///
            bar(6, color("$color_chem"))    ///
            bar(7, color("$color_apparel")) ///
            bar(8, color("$color_food"))    ///
            bar(9, color("$color_other"))   ///
            legend(order(1 "Steel & Al" 2 "Autos" 3 "Electronics" 4 "Pharma" ///
                         5 "Energy" 6 "Chem & Plastics" 7 "Apparel" ///
                         8 "Food & Ag" 9 "Other") ///
                   rows(2) size(vsmall) position(6)) ///
            ytitle("Contribution to S1-S2 gap (pp)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_div_product, replace)

        export_fig figure_diversion_product`sfx'
    }
restore


* ======================================================================
* B2. S2 -> S3 ATTRIBUTION  (other preferences, by country and product)
* ======================================================================
*
* Weights fixed at con_val_mo; rate panel changes from rate_h2avg to
* rate_all_pref. Per-group contribution = (sum_g rate_h2avg*w - sum_g
* rate_all_pref*w) / sum_total w. Sums to gap_others = S2 - S3.

di as text _n "  [B2] S2 -> S3 (other preferences) by country and product..."

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

preserve
    compute_per_group_attribution, ratevar_left(rate_h2avg) ratevar_right(rate_all_pref) ///
        weightvar(con_val_mo) byvar(partner_group) percent ///
        outfile("$working/others_by_country.dta") outvar(others_pp)
restore

preserve
    compute_per_group_attribution, ratevar_left(rate_h2avg) ratevar_right(rate_all_pref) ///
        weightvar(con_val_mo) byvar(product_group) percent ///
        outfile("$working/others_by_product.dta") outvar(others_pp)
restore

* Validation: per-month sum equals gap_others from the ladder.
preserve
    use "$working/counterfactual_ladder.dta", clear
    keep ym gap_others
    tempfile lad_o
    save `lad_o'
restore
preserve
    use "$working/others_by_country.dta", clear
    collapse (sum) others_pp, by(ym)
    merge 1:1 ym using `lad_o', nogenerate
    gen double resid = others_pp - gap_others
    qui sum resid, detail
    if abs(r(max)) > 1e-3 | abs(r(min)) > 1e-3 {
        di as error "WARNING: others-by-country sum differs from gap_others"
    }
    else {
        di as text "      Others-by-country: max residual " ///
            string(max(abs(r(max)), abs(r(min))), "%9.6f") " pp (OK)"
    }
restore


* ======================================================================
* B3. S3 -> S4 ATTRIBUTION  (residual, by country and product)
* ======================================================================
*
* Rate-vs-observed: rate_all_pref (statutory after all preferences) vs
* census_etr (Census collected duty / consumption value, row-level).
* Per-group contribution = (sum_g rate_all_pref*w - sum_g cal_dut_mo) /
* sum_total w. Sums to gap_residual = S3 - S4.
*
* (Treasury's monthly revenue is not country/product disaggregated, so
* the framework's S4 -> T timing channel cannot be similarly broken out.)

di as text _n "  [B3] S3 -> S4 (residual) by country and product..."

preserve
    compute_per_group_attribution, ratevar_left(rate_all_pref) ratevar_right(census_etr) ///
        weightvar(con_val_mo) byvar(partner_group) percent ///
        outfile("$working/residual_by_country.dta") outvar(residual_pp)
restore

preserve
    compute_per_group_attribution, ratevar_left(rate_all_pref) ratevar_right(census_etr) ///
        weightvar(con_val_mo) byvar(product_group) percent ///
        outfile("$working/residual_by_product.dta") outvar(residual_pp)
restore

* Note: validation against decomp_monthly's gap_residual deferred — the
* ladder's gap_residual = s3 - treasury_actual (not - s4). The S3 - S4
* check using these per-group sums is a separate computation handled in
* Section A's gap_residual / gap_timing labels.


* ======================================================================
* B4. STACKED-BAR FIGURES (O2/O3 and R2/R3)
* ======================================================================

di as text _n "  [B4] Stacked-bar figures for B2/B3..."

* Helper for stacked-bar build per partition. Inline (twice) to avoid a
* fourth helper program -- four blocks each ~40 lines, mostly relabel /
* color glue.

* --- O2: others by country ---
preserve
    use "$working/others_by_country.dta", clear
    keep ym partner_group others_pp

    gen str2 pg_short = ""
    replace pg_short = "CN" if partner_group == "China"
    replace pg_short = "CA" if partner_group == "Canada"
    replace pg_short = "MX" if partner_group == "Mexico"
    replace pg_short = "EU" if partner_group == "EU"
    replace pg_short = "JP" if partner_group == "Japan"
    replace pg_short = "KR" if partner_group == "S. Korea"
    replace pg_short = "UK" if partner_group == "UK"
    replace pg_short = "RW" if partner_group == "ROW"
    drop partner_group
    reshape wide others_pp, i(ym) j(pg_short) string
    foreach pg in CN CA MX EU JP KR UK RW {
        capture rename others_pp`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
        replace pg_`pg' = 0 if missing(pg_`pg')
    }
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
    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("All-Other Preferences: Country Contributions") subtitle("Stacked monthly, signed; sums to gap_others")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) pg_CN pg_CA pg_MX pg_EU pg_JP pg_KR pg_UK pg_RW, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_china"))  bar(2, color("$color_canada")) ///
            bar(3, color("$color_mexico")) bar(4, color("$color_eu")) ///
            bar(5, color("$color_japan"))  bar(6, color("$color_skorea")) ///
            bar(7, color("$color_uk"))     bar(8, color("$color_row")) ///
            legend(order(1 "China" 2 "Canada" 3 "Mexico" 4 "EU" ///
                         5 "Japan" 6 "S. Korea" 7 "UK" 8 "ROW") ///
                   rows(1) size(vsmall) position(6)) ///
            ytitle("Contribution to S2-S3 gap (pp)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_others_country, replace)
        export_fig figure_others_country`sfx'
    }
restore

* --- O3: others by product ---
preserve
    use "$working/others_by_product.dta", clear
    keep ym product_group others_pp
    gen str4 pg_short = ""
    replace pg_short = "stl"  if product_group == "Steel & Aluminum"
    replace pg_short = "auto" if product_group == "Autos & Auto Parts"
    replace pg_short = "elec" if product_group == "Electronics & Machinery"
    replace pg_short = "phrm" if product_group == "Pharmaceuticals"
    replace pg_short = "engy" if product_group == "Energy & Minerals"
    replace pg_short = "chem" if product_group == "Chemicals & Plastics"
    replace pg_short = "appr" if product_group == "Apparel & Textiles"
    replace pg_short = "food" if product_group == "Food & Agriculture"
    replace pg_short = "othr" if product_group == "Other Manufactured"
    drop product_group
    reshape wide others_pp, i(ym) j(pg_short) string
    foreach pg in stl auto elec phrm engy chem appr food othr {
        capture rename others_pp`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
        replace pg_`pg' = 0 if missing(pg_`pg')
    }
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
    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("All-Other Preferences: Product Contributions") subtitle("Stacked monthly, signed; sums to gap_others")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) pg_stl pg_auto pg_elec pg_phrm pg_engy pg_chem ///
                         pg_appr pg_food pg_othr, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_steel"))   bar(2, color("$color_autos")) ///
            bar(3, color("$color_elec"))    bar(4, color("$color_pharma")) ///
            bar(5, color("$color_energy"))  bar(6, color("$color_chem")) ///
            bar(7, color("$color_apparel")) bar(8, color("$color_food")) ///
            bar(9, color("$color_other")) ///
            legend(order(1 "Steel & Al" 2 "Autos" 3 "Electronics" 4 "Pharma" ///
                         5 "Energy" 6 "Chem & Plastics" 7 "Apparel" ///
                         8 "Food & Ag" 9 "Other") ///
                   rows(2) size(vsmall) position(6)) ///
            ytitle("Contribution to S2-S3 gap (pp)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_others_product, replace)
        export_fig figure_others_product`sfx'
    }
restore

* --- R2: residual by country ---
preserve
    use "$working/residual_by_country.dta", clear
    keep ym partner_group residual_pp
    gen str2 pg_short = ""
    replace pg_short = "CN" if partner_group == "China"
    replace pg_short = "CA" if partner_group == "Canada"
    replace pg_short = "MX" if partner_group == "Mexico"
    replace pg_short = "EU" if partner_group == "EU"
    replace pg_short = "JP" if partner_group == "Japan"
    replace pg_short = "KR" if partner_group == "S. Korea"
    replace pg_short = "UK" if partner_group == "UK"
    replace pg_short = "RW" if partner_group == "ROW"
    drop partner_group
    reshape wide residual_pp, i(ym) j(pg_short) string
    foreach pg in CN CA MX EU JP KR UK RW {
        capture rename residual_pp`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
        replace pg_`pg' = 0 if missing(pg_`pg')
    }
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
    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("Residual: Country Contributions") subtitle("Stacked monthly, signed; sums to gap_residual (S3-S4)")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) pg_CN pg_CA pg_MX pg_EU pg_JP pg_KR pg_UK pg_RW, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_china"))  bar(2, color("$color_canada")) ///
            bar(3, color("$color_mexico")) bar(4, color("$color_eu")) ///
            bar(5, color("$color_japan"))  bar(6, color("$color_skorea")) ///
            bar(7, color("$color_uk"))     bar(8, color("$color_row")) ///
            legend(order(1 "China" 2 "Canada" 3 "Mexico" 4 "EU" ///
                         5 "Japan" 6 "S. Korea" 7 "UK" 8 "ROW") ///
                   rows(1) size(vsmall) position(6)) ///
            ytitle("Contribution to S3-S4 gap (pp)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_resid_country, replace)
        export_fig figure_residual_country`sfx'
    }
restore

* --- R3: residual by product ---
preserve
    use "$working/residual_by_product.dta", clear
    keep ym product_group residual_pp
    gen str4 pg_short = ""
    replace pg_short = "stl"  if product_group == "Steel & Aluminum"
    replace pg_short = "auto" if product_group == "Autos & Auto Parts"
    replace pg_short = "elec" if product_group == "Electronics & Machinery"
    replace pg_short = "phrm" if product_group == "Pharmaceuticals"
    replace pg_short = "engy" if product_group == "Energy & Minerals"
    replace pg_short = "chem" if product_group == "Chemicals & Plastics"
    replace pg_short = "appr" if product_group == "Apparel & Textiles"
    replace pg_short = "food" if product_group == "Food & Agriculture"
    replace pg_short = "othr" if product_group == "Other Manufactured"
    drop product_group
    reshape wide residual_pp, i(ym) j(pg_short) string
    foreach pg in stl auto elec phrm engy chem appr food othr {
        capture rename residual_pp`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
        replace pg_`pg' = 0 if missing(pg_`pg')
    }
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
    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("Residual: Product Contributions") subtitle("Stacked monthly, signed; sums to gap_residual (S3-S4)")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) pg_stl pg_auto pg_elec pg_phrm pg_engy pg_chem ///
                         pg_appr pg_food pg_othr, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_steel"))   bar(2, color("$color_autos")) ///
            bar(3, color("$color_elec"))    bar(4, color("$color_pharma")) ///
            bar(5, color("$color_energy"))  bar(6, color("$color_chem")) ///
            bar(7, color("$color_apparel")) bar(8, color("$color_food")) ///
            bar(9, color("$color_other")) ///
            legend(order(1 "Steel & Al" 2 "Autos" 3 "Electronics" 4 "Pharma" ///
                         5 "Energy" 6 "Chem & Plastics" 7 "Apparel" ///
                         8 "Food & Ag" 9 "Other") ///
                   rows(2) size(vsmall) position(6)) ///
            ytitle("Contribution to S3-S4 gap (pp)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_resid_product, replace)
        export_fig figure_residual_product`sfx'
    }
restore


* ======================================================================
* B5. UNIFIED 5-CHANNEL ATTRIBUTION  (Fig F2 by country, Fig F3 by product)
* ======================================================================
*
* Each month, stack five segments per partition:
*   gap_adjustment   (S0 - S1)
*   gap_diversion    (S1 - S2; from B Section)
*   gap_others       (S2 - S3; from B2)
*   gap_residual     (S3 - S4; from B3)
*   gap_timing       (S4 - T;  no per-group breakdown -- stacked at residual line)
*
* For the per-group view, gap_timing cannot be split (Treasury is aggregate),
* so it appears as a single solid color across the full bar (proportional to
* total gap), not attributed to any partition. The five segments per (group,
* month) cell sum to gap_total when summed across groups.

di as text _n "  [B5] Unified 5-channel attribution (Figs F2, F3)..."

* For now, build the country and product attribution tables only -- the
* aggregated stacked-bar figure is left for a later iteration since the
* "Treasury timing as overlay" rendering needs a custom twoway approach.

* Country-level table: per (ym, partner_group), stack of channels.
preserve
    * Diversion contribution per ym x partner_group
    use "$working/diversion_by_country.dta", clear
    keep ym partner_group c_total
    rename c_total diversion_pp
    tempfile div_c
    save `div_c'
restore
preserve
    use "$working/others_by_country.dta", clear
    rename others_pp others_c_pp
    tempfile oth_c
    save `oth_c'
restore
preserve
    use "$working/residual_by_country.dta", clear
    rename residual_pp residual_c_pp
    tempfile res_c
    save `res_c'
restore

* Per-country adjustment (S0 - S1) attribution
preserve
    use "$working/merged_analysis.dta", clear
    keep if ym >= $start_ym & ym <= $end_ym
    compute_per_group_attribution, ratevar_left(rate_2024) ratevar_right(rate_h2avg) ///
        weightvar(imports) byvar(partner_group) percent ///
        outfile("$working/adjustment_by_country.dta") outvar(adjustment_pp)
restore

preserve
    use "$working/diversion_by_country.dta", clear
    keep ym partner_group c_total
    rename c_total diversion_pp
    merge 1:1 ym partner_group using `oth_c', nogenerate
    rename others_c_pp others_pp
    merge 1:1 ym partner_group using `res_c', nogenerate
    rename residual_c_pp residual_pp
    merge 1:1 ym partner_group using "$working/adjustment_by_country.dta", nogenerate

    label var adjustment_pp "USMCA adjustment (S0-S1) per country (pp)"
    label var diversion_pp  "Trade diversion (S1-S2) per country (pp)"
    label var others_pp     "All-other prefs (S2-S3) per country (pp)"
    label var residual_pp   "Residual (S3-S4) per country (pp)"

    sort ym partner_group
    compress
    save "$working/attribution_by_country.dta", replace
    export delimited using "$tables/attribution_by_country.csv", replace
restore

* Product-level same flow.
preserve
    use "$working/diversion_by_product.dta", clear
    keep ym product_group p_total
    rename p_total diversion_pp
    tempfile div_p
    save `div_p'
restore
preserve
    use "$working/others_by_product.dta", clear
    rename others_pp others_p_pp
    tempfile oth_p
    save `oth_p'
restore
preserve
    use "$working/residual_by_product.dta", clear
    rename residual_pp residual_p_pp
    tempfile res_p
    save `res_p'
restore

preserve
    use "$working/merged_analysis.dta", clear
    keep if ym >= $start_ym & ym <= $end_ym
    compute_per_group_attribution, ratevar_left(rate_2024) ratevar_right(rate_h2avg) ///
        weightvar(imports) byvar(product_group) percent ///
        outfile("$working/adjustment_by_product.dta") outvar(adjustment_pp)
restore

preserve
    use "$working/diversion_by_product.dta", clear
    keep ym product_group p_total
    rename p_total diversion_pp
    merge 1:1 ym product_group using `oth_p', nogenerate
    rename others_p_pp others_pp
    merge 1:1 ym product_group using `res_p', nogenerate
    rename residual_p_pp residual_pp
    merge 1:1 ym product_group using "$working/adjustment_by_product.dta", nogenerate

    label var adjustment_pp "USMCA adjustment (S0-S1) per product (pp)"
    label var diversion_pp  "Trade diversion (S1-S2) per product (pp)"
    label var others_pp     "All-other prefs (S2-S3) per product (pp)"
    label var residual_pp   "Residual (S3-S4) per product (pp)"

    sort ym product_group
    compress
    save "$working/attribution_by_product.dta", replace
    export delimited using "$tables/attribution_by_product.csv", replace
restore

di as text "      Saved attribution_by_country / attribution_by_product (CSVs + dta)"
di as text "      Per-month per-group: adjustment + diversion + others + residual."
di as text "      gap_timing (S4 -> T) is aggregate-only; not in per-group panels."


* ======================================================================
* B6. 4-PANEL CHANNEL-ATTRIBUTION FACETS (Fig F2 country, Fig F3 product)
* ======================================================================
*
* For each partition (country, product), build four stacked-bar panels
* (adjustment / diversion / others / residual), then graph combine into
* one figure. Shared legend lives on the first panel only.

di as text _n "  [B6] 4-panel attribution facets (country, product)..."

* --- F2: Country partition ---
foreach ch in adjustment diversion others residual {
    preserve
        use "$working/attribution_by_country.dta", clear
        keep ym partner_group `ch'_pp
        rename `ch'_pp val

        gen str2 pg_short = ""
        replace pg_short = "CN" if partner_group == "China"
        replace pg_short = "CA" if partner_group == "Canada"
        replace pg_short = "MX" if partner_group == "Mexico"
        replace pg_short = "EU" if partner_group == "EU"
        replace pg_short = "JP" if partner_group == "Japan"
        replace pg_short = "KR" if partner_group == "S. Korea"
        replace pg_short = "UK" if partner_group == "UK"
        replace pg_short = "RW" if partner_group == "ROW"
        drop partner_group
        reshape wide val, i(ym) j(pg_short) string
        foreach pg in CN CA MX EU JP KR UK RW {
            capture rename val`pg' pg_`pg'
            capture confirm variable pg_`pg'
            if _rc != 0 gen double pg_`pg' = 0
            replace pg_`pg' = 0 if missing(pg_`pg')
        }

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

        local channel_title = upper(substr("`ch'", 1, 1)) + substr("`ch'", 2, .)
        if "`ch'" == "adjustment" local panel_label "USMCA adjustment (S0-S1)"
        if "`ch'" == "diversion"  local panel_label "Trade diversion (S1-S2)"
        if "`ch'" == "others"     local panel_label "Other preferences (S2-S3)"
        if "`ch'" == "residual"   local panel_label "Residual (S3-S4)"

        * Show legend on first panel only.
        if "`ch'" == "adjustment" {
            local legend_opts ///
                legend(order(1 "China" 2 "Canada" 3 "Mexico" 4 "EU" ///
                             5 "Japan" 6 "S. Korea" 7 "UK" 8 "ROW") ///
                       rows(1) size(vsmall) position(6))
        }
        else {
            local legend_opts legend(off)
        }

        graph bar (asis) pg_CN pg_CA pg_MX pg_EU pg_JP pg_KR pg_UK pg_RW, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(tiny))) ///
            stack ///
            bar(1, color("$color_china"))  bar(2, color("$color_canada")) ///
            bar(3, color("$color_mexico")) bar(4, color("$color_eu")) ///
            bar(5, color("$color_japan"))  bar(6, color("$color_skorea")) ///
            bar(7, color("$color_uk"))     bar(8, color("$color_row")) ///
            ytitle("pp", size(vsmall)) ///
            title("`panel_label'", size(small) color(black)) ///
            yline(0, lcolor(gs10) lpattern(dot)) ///
            `legend_opts' ///
            graphregion(color(white)) ///
            name(g_c_`ch', replace)
    restore
}

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Per-Country Attribution Across the Four Decomposable Channels") subtitle("Stacked monthly; gap_timing (S4-T) is Treasury-aggregate-only, not shown")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    graph combine g_c_adjustment g_c_diversion g_c_others g_c_residual, ///
        cols(2) ycommon ///
        `opt_title' ///
        graphregion(color(white)) ///
        name(g_attr_country, replace)
    export_fig figure_attribution_country`sfx', width(3000)
}

* Drop named graphs to free memory before product loop.
graph drop g_c_adjustment g_c_diversion g_c_others g_c_residual


* --- F3: Product partition ---
foreach ch in adjustment diversion others residual {
    preserve
        use "$working/attribution_by_product.dta", clear
        keep ym product_group `ch'_pp
        rename `ch'_pp val

        gen str4 pg_short = ""
        replace pg_short = "stl"  if product_group == "Steel & Aluminum"
        replace pg_short = "auto" if product_group == "Autos & Auto Parts"
        replace pg_short = "elec" if product_group == "Electronics & Machinery"
        replace pg_short = "phrm" if product_group == "Pharmaceuticals"
        replace pg_short = "engy" if product_group == "Energy & Minerals"
        replace pg_short = "chem" if product_group == "Chemicals & Plastics"
        replace pg_short = "appr" if product_group == "Apparel & Textiles"
        replace pg_short = "food" if product_group == "Food & Agriculture"
        replace pg_short = "othr" if product_group == "Other Manufactured"
        drop product_group
        reshape wide val, i(ym) j(pg_short) string
        foreach pg in stl auto elec phrm engy chem appr food othr {
            capture rename val`pg' pg_`pg'
            capture confirm variable pg_`pg'
            if _rc != 0 gen double pg_`pg' = 0
            replace pg_`pg' = 0 if missing(pg_`pg')
        }

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

        if "`ch'" == "adjustment" local panel_label "USMCA adjustment (S0-S1)"
        if "`ch'" == "diversion"  local panel_label "Trade diversion (S1-S2)"
        if "`ch'" == "others"     local panel_label "Other preferences (S2-S3)"
        if "`ch'" == "residual"   local panel_label "Residual (S3-S4)"

        if "`ch'" == "adjustment" {
            local legend_opts ///
                legend(order(1 "Steel & Al" 2 "Autos" 3 "Electronics" ///
                             4 "Pharma" 5 "Energy" 6 "Chem & Plastics" ///
                             7 "Apparel" 8 "Food & Ag" 9 "Other") ///
                       rows(2) size(vsmall) position(6))
        }
        else {
            local legend_opts legend(off)
        }

        graph bar (asis) pg_stl pg_auto pg_elec pg_phrm pg_engy pg_chem ///
                         pg_appr pg_food pg_othr, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(tiny))) ///
            stack ///
            bar(1, color("$color_steel"))   bar(2, color("$color_autos")) ///
            bar(3, color("$color_elec"))    bar(4, color("$color_pharma")) ///
            bar(5, color("$color_energy"))  bar(6, color("$color_chem")) ///
            bar(7, color("$color_apparel")) bar(8, color("$color_food")) ///
            bar(9, color("$color_other")) ///
            ytitle("pp", size(vsmall)) ///
            title("`panel_label'", size(small) color(black)) ///
            yline(0, lcolor(gs10) lpattern(dot)) ///
            `legend_opts' ///
            graphregion(color(white)) ///
            name(g_p_`ch', replace)
    restore
}

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Per-Product Attribution Across the Four Decomposable Channels") subtitle("Stacked monthly; gap_timing (S4-T) is Treasury-aggregate-only, not shown")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    graph combine g_p_adjustment g_p_diversion g_p_others g_p_residual, ///
        cols(2) ycommon ///
        `opt_title' ///
        graphregion(color(white)) ///
        name(g_attr_product, replace)
    export_fig figure_attribution_product`sfx', width(3000)
}

graph drop g_p_adjustment g_p_diversion g_p_others g_p_residual


* ======================================================================
* C. FIGURES (six-tier ladder)
* ======================================================================
*
* Reads the six-tier decomposition from decomp_monthly.dta (produced in
* Section A above). All tier values are already in pp.
*
* Three figures:
*   Figure 1 -- Line chart: S0, S1, S2, S3, Treasury (5 lines)
*   Figure 2 -- Stacked bar: USMCA adjustment (S0->S1) + main analytic (S1->T)
*   Figure 3 -- Stacked bar: trade diversion + all-other preferences + residual
*               (decomposition of the S1 -> Treasury main analytic gap)

di as text _n "  [C] Generating figures from six-tier decomposition..."

use "${working}/decomp_monthly.dta", clear
keep ym s0 s1 s2 s3 s4 t gap_*

* Sub-channels for figure stacking
gen double gap_s3_t = s3 - t if !missing(t)   // residual + timing combined
gen double gap_s1_t = s1 - t if !missing(t)   // total main-analytic gap (S1->T)

di as text _n "  === Figure-input ladder ==="
format s0 s1 s2 s3 t gap_* %9.2f
list ym s0 s1 s2 s3 t gap_adjustment gap_diversion gap_others, clean noobs


* --- Figure 1: ETR line chart (S0, S1, S2, S3, Treasury) ---

di as text _n "      Figure 1: ETR comparison"

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Statutory vs. Actual Effective Tariff Rates") subtitle("Six-tier ladder, Jan 2025 - Feb 2026")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    twoway ///
        (connected s0 ym, ///
            mcolor("$color_gray") lcolor("$color_gray") ///
            msymbol(circle) msize(vsmall) lwidth(medium) ///
            lpattern(dash)) ///
        (connected s1 ym, ///
            mcolor("$color_statutory") lcolor("$color_statutory") ///
            msymbol(diamond) msize(small) lwidth(thick) ///
            lpattern(solid)) ///
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
            1 "S0 (USMCA 2024 baseline; backstory)" ///
            2 "S1 (Post-July 2025 USMCA, 2024 wts; framework anchor)" ///
            3 "S2 (Post-July 2025 USMCA, monthly wts)" ///
            4 "S3 (+ all-other prefs, monthly wts)" ///
            5 "T (Treasury actual)") ///
            rows(5) size(small) position(6)) ///
        ytitle("Effective Tariff Rate (%)") ///
        xtitle("") ///
        `opt_title' ///
        xlabel(`=ym(2025,1)'(1)`=ym(2026,2)', ///
               format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
        ylabel(, format(%9.0f)) ///
        yscale(range(0)) ///
        graphregion(color(white)) ///
        plotregion(margin(small)) ///
        name(g_ladder, replace)
    export_fig figure_ladder`sfx'
}


* --- Figure 1b: ETR line chart without S3 (S0, S1, S2, Treasury) ---
* Same layout as figure_ladder but drops the S3 line and uses a 2-row legend.

di as text _n "      Figure 1b: ETR comparison (no S3)"

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Statutory vs. Actual Effective Tariff Rates") subtitle("Six-tier ladder excluding S3, Jan 2025 - Feb 2026")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    twoway ///
        (connected s0 ym, ///
            mcolor("$color_gray") lcolor("$color_gray") ///
            msymbol(circle) msize(vsmall) lwidth(medium) ///
            lpattern(dash)) ///
        (connected s1 ym, ///
            mcolor("$color_statutory") lcolor("$color_statutory") ///
            msymbol(diamond) msize(small) lwidth(thick) ///
            lpattern(solid)) ///
        (connected s2 ym, ///
            mcolor("$color_canada") lcolor("$color_canada") ///
            msymbol(square) msize(small) lwidth(medium) ///
            lpattern(shortdash)) ///
        (connected t ym, ///
            mcolor("$color_actual") lcolor("$color_actual") ///
            msymbol(triangle) msize(small) lwidth(medthick) ///
            lpattern(solid)) ///
        , ///
        legend(order( ///
            1 "S0 (USMCA 2024 baseline; backstory)" ///
            2 "S1 (Post-July 2025 USMCA, 2024 wts; framework anchor)" ///
            3 "S2 (Post-July 2025 USMCA, monthly wts)" ///
            4 "T (Treasury actual)") ///
            rows(2) size(small) position(6)) ///
        ytitle("Effective Tariff Rate (%)") ///
        xtitle("") ///
        `opt_title' ///
        xlabel(`=ym(2025,1)'(1)`=ym(2026,2)', ///
               format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
        ylabel(, format(%9.0f)) ///
        yscale(range(0)) ///
        graphregion(color(white)) ///
        plotregion(margin(small)) ///
        name(g_ladder_no_s3, replace)
    export_fig figure_ladder_no_s3`sfx'
}


* --- Figure 2: Gap decomposition stacked bar (S0->T, two stacks) ---
* USMCA adjustment vs the main-analytic gap (S1->T).

di as text "      Figure 2: Gap decomposition (USMCA adjustment vs main analytic)"

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Statutory-Actual ETR Gap Decomposition") subtitle("Stacked components, Jan 2025 - Feb 2026")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    graph bar (asis) gap_s1_t gap_adjustment, ///
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
            2 "USMCA adjustment (S0{&rarr}S1)" ///
            1 "Main analytic gap (S1{&rarr}Treasury)") ///
            rows(1) size(small) position(6)) ///
        ytitle("Gap (percentage points)") ///
        `opt_title' ///
        graphregion(color(white)) ///
        name(g_gap_stacked, replace)
    export_fig figure_gap_stacked`sfx'
}


* --- Figure 3: S1->Treasury decomposed into diversion / others / residual (3 stacks) ---

di as text "      Figure 3: Trade diversion / all-others / residual decomposition"

foreach v in titled clean {
    if "`v'" == "titled" {
        local opt_title `"title("Preferences Gap Decomposition") subtitle("S1{&rarr}Treasury split into USMCA / all-others / residual")"'
        local sfx "_titled"
    }
    else {
        local opt_title ""
        local sfx ""
    }
    graph bar (asis) gap_diversion gap_others gap_s3_t, ///
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
            1 "Trade diversion (S1{&rarr}S2)" ///
            2 "All-other preferences (S2{&rarr}S3)" ///
            3 "Residual + timing (S3{&rarr}Treasury)") ///
            rows(2) size(small) position(6)) ///
        ytitle("Gap (percentage points)") ///
        `opt_title' ///
        graphregion(color(white)) ///
        name(g_channel_stacked, replace)
    export_fig figure_channel_stacked`sfx'
}


* ======================================================================
* D. S2 vs S4 vs T COMPARISON  (six-tier framework labels)
* ======================================================================
*
* Clean comparison between:
*   S2 = rate_h2avg weighted by con_val_mo (statutory rate with USMCA at
*        the post-July 2025 stabilized baseline). Identical by construction to S2
*        in counterfactual_ladder.dta -- same panel, same row-level
*        Sum(rate*val)/Sum(val) collapse.
*   S4 = cal_dut_mo / con_val_mo (Census-collected duties)
*   T  = Treasury actual ETR (revenue_monthly.dta)
*
* Three aggregation levels:
*   (i)   Overall monthly                  -> figure_s2s4_overall
*   (ii)  Partner group x month            -> figure_s2s4_facets_country, figure_s2s4_gap_country
*   (iii) Product group x month            -> figure_s2s4_facets_product, figure_s2s4_gap_product
*   (iv)  Product x partner heatmap        -> figure_s2s4_heatmap
*   (v)   HS2 chapter x month (rankings)   -> Tbl 3a
*
* Outputs:
*   results/tables/cmp_overall_monthly.csv
*   results/tables/cmp_partner_monthly.csv
*   results/tables/cmp_hs2_ranking.csv
*   results/tables/cmp_top_hs10_anomalies.csv

di as text _n "  [D] S2 (statutory, Post-July 2025 USMCA) vs S4 (Census) vs T (Treasury)..."

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

** Sanity: rate_h2avg is the S2 panel rate, merged in 01.
capture confirm variable rate_h2avg
if _rc != 0 {
    di as error "ERROR: rate_h2avg not found. Re-run 01_etr_clean.do."
    error 111
}


* ----------------------------------------------------------------------
* D1. Overall monthly comparison (Tbl 1 + Fig 4)
*
* Statutory = S2 (rate_h2avg x con_val_mo, row-level value-weighted).
* Identical by construction to S2 in counterfactual_ladder.dta, since both
* use the same panel and the same row-level Sum(rate*val)/Sum(val) collapse.
* ----------------------------------------------------------------------

di as text "      D1. Overall monthly..."

preserve
    compute_tier, ratevar(rate_h2avg) weightvar(con_val_mo) ///
        outfile("$working/cmp_overall_monthly.dta") outvar(s2) percent
restore

preserve
    collapse (sum) cal_dut_mo con_val_mo, by(ym)
    safe_divide cal_dut_mo con_val_mo s4
    replace s4 = s4 * 100
    keep ym s4
    tempfile s4_overall
    save `s4_overall'
restore

preserve
    use "$working/cmp_overall_monthly.dta", clear
    merge 1:1 ym using `s4_overall', nogenerate
    merge 1:1 ym using "$working/revenue_monthly.dta", ///
        keep(match master) keepusing(actual_rate) nogenerate
    rename actual_rate t
    replace t = t * 100

    gen double gap_s2_s4 = s2 - s4
    gen double gap_s4_t  = s4 - t
    gen double gap_s2_t  = s2 - t

    label var s2        "S2: Statutory (Post-July 2025 USMCA), monthly wts (%)"
    label var s4        "S4: Census collected ETR (%)"
    label var t         "T: Treasury actual ETR (%)"
    label var gap_s2_s4 "S2 - S4 (pp)"
    label var gap_s4_t  "S4 - T (pp)"
    label var gap_s2_t  "S2 - T (pp)"

    format s2 s4 t gap_* %9.2f
    di as text "  === Tbl 1: Overall monthly comparison (S2 / S4 / T) ==="
    list ym s2 s4 t gap_s2_s4 gap_s4_t, clean noobs

    save "$working/cmp_overall_monthly.dta", replace
    export delimited using "$tables/cmp_overall_monthly.csv", replace

    ** --- Fig 4: overall line chart (S2 / S4 / T) ---
    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("S2 vs. S4 vs. T") subtitle("Monthly, Jan 2025 - Feb 2026")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        twoway ///
            (connected s2 ym, ///
                mcolor("$color_statutory") lcolor("$color_statutory") ///
                msymbol(circle) msize(small) lwidth(medthick) lpattern(solid)) ///
            (connected s4 ym, ///
                mcolor("$color_gap") lcolor("$color_gap") ///
                msymbol(diamond) msize(small) lwidth(medium) lpattern(solid)) ///
            (connected t ym, ///
                mcolor("$color_actual") lcolor("$color_actual") ///
                msymbol(triangle) msize(small) lwidth(medium) lpattern(dash)) ///
            , ///
            legend(order( ///
                1 "S2: Statutory (Post-July 2025 USMCA)" ///
                2 "S4: Census (cal. duty / cons. value)" ///
                3 "T: Treasury actual") ///
                rows(1) size(small) position(6)) ///
            ytitle("Effective Tariff Rate (%)") ///
            xtitle("") ///
            `opt_title' ///
            xlabel(, format(%tmMon_CCYY) angle(45)) ///
            ylabel(, format(%9.0f)) ///
            yscale(range(0)) ///
            graphregion(color(white)) plotregion(margin(small)) ///
            name(g_s2s4_overall, replace)
        export_fig figure_s2s4_overall`sfx'
    }
restore

** Reload merged_analysis for the remaining D2-D6 sections.
** census_etr is already on the dataset (computed in 01); no need to recompute.
** stat_rev_row uses rate_h2avg (the S2 panel rate after the framework
** restructuring; was rate_usmca_monthly under the prior framework).
use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym
gen double stat_rev_row = rate_h2avg * con_val_mo
gen double cens_rev_row = cal_dut_mo


* ----------------------------------------------------------------------
* D2. Partner group x month (Tbl 2 + Fig B + Fig C)
* ----------------------------------------------------------------------

di as text "      D2. Partner group x month..."

preserve
    collapse (sum) stat_num=stat_rev_row cens_num=cens_rev_row ///
                   total_val=con_val_mo, ///
        by(ym partner_group)

    safe_divide stat_num total_val s2
    safe_divide cens_num total_val s4

    foreach v in s2 s4 {
        replace `v' = `v' * 100
    }
    gen double gap_pp = s2 - s4

    label var s2     "S2: Statutory (Post-July 2025 USMCA), monthly wts (%)"
    label var s4     "S4: Census collected ETR (%)"
    label var gap_pp "S2 - S4 (pp)"

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

    ** --- Fig 5: 8-panel facet by partner group ---
    encode partner_group, gen(pg_id)

    foreach v in titled clean {
        if "`v'" == "titled" {
            local fig_t "S2 (Statutory, Post-July 2025 USMCA) vs. S4 (Census) by Partner"
            local fig_st "Monthly, Jan 2025 - Feb 2026"
            local sfx "_titled"
        }
        else {
            local fig_t ""
            local fig_st ""
            local sfx ""
        }
        twoway ///
            (connected s2 ym, ///
                mcolor("$color_statutory") lcolor("$color_statutory") ///
                msymbol(circle) msize(vsmall) lwidth(medium) lpattern(solid)) ///
            (connected s4 ym, ///
                mcolor("$color_gap") lcolor("$color_gap") ///
                msymbol(diamond) msize(vsmall) lwidth(medium) lpattern(solid)) ///
            , ///
            by(pg_id, ///
                cols(4) ///
                title("`fig_t'") ///
                subtitle("`fig_st'") ///
                note("") ///
                graphregion(color(white))) ///
            legend(order( ///
                1 "S2: Statutory (Post-July 2025 USMCA)" ///
                2 "S4: Census") rows(1) size(small) position(6)) ///
            ytitle("ETR (%)") xtitle("") ///
            xlabel(, format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
            ylabel(, labsize(vsmall))
        export_fig figure_s2s4_facets_country`sfx', width(3000)
    }

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

    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("Statutory - Census gap, by partner group") subtitle("Monthly contribution to overall-ETR gap, pp")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
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
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_s2s4_gap_country, replace)
        export_fig figure_s2s4_gap_country`sfx'
    }
restore


* ----------------------------------------------------------------------
* D3. HS2 chapter ranking (Tbl 3a)
* ----------------------------------------------------------------------

di as text "      D3. HS2 chapter ranking..."

preserve
    ** Aggregate over the whole window for a single ranked table
    gen double stat_num_row = rate_h2avg * con_val_mo
    collapse (sum) stat_num = stat_num_row ///
                   cens_num = cal_dut_mo ///
                   total_val = con_val_mo, ///
        by(hs2)

    destring hs2, gen(hs2_num) force
    label values hs2_num hs2_lbl

    safe_divide stat_num total_val s2
    safe_divide cens_num total_val s4
    replace s2 = s2 * 100
    replace s4 = s4 * 100

    gen double gap_pp = s2 - s4
    ** Dollar-weighted contribution to overall gap (in USD)
    gen double gap_usd = stat_num - cens_num

    label var s2         "S2: Statutory (Post-July 2025 USMCA), monthly wts (%)"
    label var s4         "S4: Census collected ETR (%)"
    label var gap_pp     "Chapter-level gap S2-S4 (pp)"
    label var gap_usd    "Chapter-level gap in $ (S2 - S4)"
    label var total_val  "Total imports, analysis window (USD)"

    gsort -gap_usd
    format total_val gap_usd %20.0fc
    format s2 s4 gap_pp %9.2f

    di as text "  === Tbl 3a: HS2 chapter gap ranking (top 25 by $ gap) ==="
    list hs2_num total_val s2 s4 gap_pp gap_usd in 1/25, ///
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

    safe_divide stat_num total_val s2
    safe_divide cens_num total_val s4
    replace s2 = s2 * 100
    replace s4 = s4 * 100

    gen double gap_pp  = s2 - s4
    gen double gap_usd = stat_num - cens_num
    gen double abs_usd = abs(gap_usd)

    keep if total_val > 0

    gsort -abs_usd
    format total_val gap_usd %20.0fc
    format s2 s4 gap_pp %9.2f

    di as text "  === Tbl 3b: Top 30 HS10 x country by |gap x value| ==="
    list hs10 partner_group total_val s2 s4 gap_pp gap_usd ///
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

    gen byte stat_pos = (rate_h2avg > 0 & !missing(rate_h2avg))
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
*     gap_pp = 100 * (rate_h2avg - census_etr).
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
    * census_etr already on merged_analysis.dta from 01 -- no recompute needed.
    gen double gap_pp  = 100 * (rate_h2avg - census_etr)
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


* ----------------------------------------------------------------------
* D7. Product group x month  (Tbl + Figs P1, P2, P3)
*
* Mirrors D2 with product_group instead of partner_group. Plus Fig P3:
* a heatplot of the period-averaged S2-S4 gap across the
* product_group x partner_group grid.
* ----------------------------------------------------------------------

di as text "      D7. Product group x month..."

preserve
    collapse (sum) stat_num=stat_rev_row cens_num=cens_rev_row ///
                   total_val=con_val_mo, ///
        by(ym product_group)

    safe_divide stat_num total_val s2
    safe_divide cens_num total_val s4

    foreach v in s2 s4 {
        replace `v' = `v' * 100
    }
    gen double gap_pp = s2 - s4

    label var s2     "S2: Statutory (Post-July 2025 USMCA), monthly wts (%)"
    label var s4     "S4: Census collected ETR (%)"
    label var gap_pp "S2 - S4 (pp)"

    save "$working/cmp_product_monthly.dta", replace
    export delimited using "$tables/cmp_product_monthly.csv", replace

    ** Short codes for figure variable names
    gen str4 pg_short = ""
    replace pg_short = "stl"  if product_group == "Steel & Aluminum"
    replace pg_short = "auto" if product_group == "Autos & Auto Parts"
    replace pg_short = "elec" if product_group == "Electronics & Machinery"
    replace pg_short = "phrm" if product_group == "Pharmaceuticals"
    replace pg_short = "engy" if product_group == "Energy & Minerals"
    replace pg_short = "chem" if product_group == "Chemicals & Plastics"
    replace pg_short = "appr" if product_group == "Apparel & Textiles"
    replace pg_short = "food" if product_group == "Food & Agriculture"
    replace pg_short = "othr" if product_group == "Other Manufactured"

    ** --- Fig P1: 9-panel facet by product group ---
    encode product_group, gen(pg_id)

    foreach v in titled clean {
        if "`v'" == "titled" {
            local fig_t "S2 (Statutory, Post-July 2025 USMCA) vs. S4 (Census) by Product Group"
            local fig_st "Monthly, Jan 2025 - Feb 2026"
            local sfx "_titled"
        }
        else {
            local fig_t ""
            local fig_st ""
            local sfx ""
        }
        twoway ///
            (connected s2 ym, ///
                mcolor("$color_statutory") lcolor("$color_statutory") ///
                msymbol(circle) msize(vsmall) lwidth(medium) lpattern(solid)) ///
            (connected s4 ym, ///
                mcolor("$color_gap") lcolor("$color_gap") ///
                msymbol(diamond) msize(vsmall) lwidth(medium) lpattern(solid)) ///
            , ///
            by(pg_id, ///
                cols(3) ///
                title("`fig_t'") ///
                subtitle("`fig_st'") ///
                note("") ///
                graphregion(color(white))) ///
            legend(order( ///
                1 "S2: Statutory (Post-July 2025 USMCA)" ///
                2 "S4: Census") rows(1) size(small) position(6)) ///
            ytitle("ETR (%)") xtitle("") ///
            xlabel(, format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
            ylabel(, labsize(vsmall))
        export_fig figure_s2s4_facets_product`sfx', width(3000)
    }

    ** --- Fig P2: gap contribution stacked by product group ---
    bysort ym: egen double total_val_all = total(total_val)
    gen double gap_contrib_pp = 100 * (stat_num - cens_num) / total_val_all

    keep ym pg_short gap_contrib_pp
    reshape wide gap_contrib_pp, i(ym) j(pg_short) string

    foreach pg in stl auto elec phrm engy chem appr food othr {
        capture rename gap_contrib_pp`pg' pg_`pg'
        capture confirm variable pg_`pg'
        if _rc != 0 gen double pg_`pg' = 0
    }

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

    foreach v in titled clean {
        if "`v'" == "titled" {
            local opt_title `"title("S2 - S4 Gap, by Product Group") subtitle("Monthly contribution to overall-ETR gap, pp")"'
            local sfx "_titled"
        }
        else {
            local opt_title ""
            local sfx ""
        }
        graph bar (asis) pg_stl pg_auto pg_elec pg_phrm pg_engy pg_chem ///
                         pg_appr pg_food pg_othr, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_steel"))   ///
            bar(2, color("$color_autos"))   ///
            bar(3, color("$color_elec"))    ///
            bar(4, color("$color_pharma"))  ///
            bar(5, color("$color_energy"))  ///
            bar(6, color("$color_chem"))    ///
            bar(7, color("$color_apparel")) ///
            bar(8, color("$color_food"))    ///
            bar(9, color("$color_other"))   ///
            legend(order(1 "Steel & Al" 2 "Autos" 3 "Electronics" 4 "Pharma" ///
                         5 "Energy" 6 "Chem & Plastics" 7 "Apparel" ///
                         8 "Food & Ag" 9 "Other") ///
                   rows(2) size(vsmall) position(6)) ///
            ytitle("Gap contribution (pp of overall ETR)") ///
            `opt_title' ///
            graphregion(color(white)) ///
            name(g_s2s4_gap_product, replace)
        export_fig figure_s2s4_gap_product`sfx'
    }
restore

** --- Fig P3: product_group x partner_group heatmap (period-averaged S2-S4) ---
di as text "      Fig P3: product x partner heatmap"

preserve
    collapse (sum) stat_num=stat_rev_row cens_num=cens_rev_row ///
                   total_val=con_val_mo, ///
        by(product_group partner_group)

    safe_divide stat_num total_val s2
    safe_divide cens_num total_val s4
    gen double gap_pp = (s2 - s4) * 100

    label var gap_pp "S2 - S4 (pp), period average"

    save "$working/cmp_product_partner_avg.dta", replace
    export delimited using "$tables/cmp_product_partner_avg.csv", replace

    ** heatplot is from SSC (ssc install heatplot palettes colrspace).
    ** heatplot's i.<varname> factor syntax requires numeric vars; encode the
    ** string group columns first so heatplot can pull value labels for axes.
    encode product_group, gen(prod_id)
    encode partner_group, gen(part_id)

    capture which heatplot
    if _rc == 0 {
        foreach v in titled clean {
            if "`v'" == "titled" {
                local fig_t "S2 - S4 Gap by Product x Partner"
                local fig_st "Period-averaged, pp"
                local sfx "_titled"
            }
            else {
                local fig_t ""
                local fig_st ""
                local sfx ""
            }
            heatplot gap_pp i.prod_id i.part_id, ///
                color(RdBu, reverse) cuts(-30(5)30) ///
                ramp(right space(5) labels(-30(10)30) subtitle("pp")) ///
                xtitle("") ytitle("") ///
                title("`fig_t'") ///
                subtitle("`fig_st'") ///
                graphregion(color(white)) plotregion(margin(small))
            export_fig figure_s2s4_heatmap`sfx'
        }
    }
    else {
        di as error "WARNING: heatplot not installed; skipping S2-S4 heatmap."
        di as error "         Install with: ssc install heatplot palettes colrspace"
    }
restore


* ----------------------------------------------------------------------
* D8. S1 vs S2 facets  (country and product partitions)
*
* Same panel-line-chart form as D2 (S2 vs S4 by country) and D7's P1
* (S2 vs S4 by product), but the two lines are S1 (rate_h2avg x 2024
* weights) and S2 (rate_h2avg x monthly weights). Visualizes the
* trade-diversion channel at the group level.
* ----------------------------------------------------------------------

di as text _n "      D8. S1 vs S2 facets..."

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

gen double s1_num = rate_h2avg * imports
gen double s2_num = rate_h2avg * con_val_mo

* --- D8a. S1 vs S2 by country ---
preserve
    collapse (sum) s1_num s2_num imports con_val_mo, by(ym partner_group)

    safe_divide s1_num imports     s1
    safe_divide s2_num con_val_mo  s2
    replace s1 = s1 * 100
    replace s2 = s2 * 100
    gen double gap_s1_s2 = s1 - s2

    label var s1        "S1: rate_h2avg x 2024 wts (%)"
    label var s2        "S2: rate_h2avg x monthly wts (%)"
    label var gap_s1_s2 "S1 - S2 (pp)"

    save "$working/cmp_s1s2_country_monthly.dta", replace
    export delimited using "$tables/cmp_s1s2_country_monthly.csv", replace

    encode partner_group, gen(pg_id)

    foreach v in titled clean {
        if "`v'" == "titled" {
            local fig_t "S1 (USMCA h2avg, 2024 wts) vs. S2 (USMCA h2avg, monthly wts) by Partner"
            local fig_st "Rate panel held fixed; weights shift -- the trade-diversion channel"
            local sfx "_titled"
        }
        else {
            local fig_t ""
            local fig_st ""
            local sfx ""
        }
        twoway ///
            (connected s1 ym, ///
                mcolor("$color_statutory") lcolor("$color_statutory") ///
                msymbol(circle) msize(vsmall) lwidth(medium) lpattern(solid)) ///
            (connected s2 ym, ///
                mcolor("$color_canada") lcolor("$color_canada") ///
                msymbol(diamond) msize(vsmall) lwidth(medium) lpattern(shortdash)) ///
            , ///
            by(pg_id, ///
                cols(4) ///
                title("`fig_t'") ///
                subtitle("`fig_st'") ///
                note("") ///
                graphregion(color(white))) ///
            legend(order( ///
                1 "S1: 2024 weights" ///
                2 "S2: monthly weights") rows(1) size(small) position(6)) ///
            ytitle("ETR (%)") xtitle("") ///
            xlabel(, format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
            ylabel(, labsize(vsmall))
        export_fig figure_s1s2_facets_country`sfx', width(3000)
    }
restore

* --- D8b. S1 vs S2 by product ---
preserve
    collapse (sum) s1_num s2_num imports con_val_mo, by(ym product_group)

    safe_divide s1_num imports     s1
    safe_divide s2_num con_val_mo  s2
    replace s1 = s1 * 100
    replace s2 = s2 * 100
    gen double gap_s1_s2 = s1 - s2

    label var s1        "S1: rate_h2avg x 2024 wts (%)"
    label var s2        "S2: rate_h2avg x monthly wts (%)"
    label var gap_s1_s2 "S1 - S2 (pp)"

    save "$working/cmp_s1s2_product_monthly.dta", replace
    export delimited using "$tables/cmp_s1s2_product_monthly.csv", replace

    encode product_group, gen(pg_id)

    foreach v in titled clean {
        if "`v'" == "titled" {
            local fig_t "S1 (USMCA h2avg, 2024 wts) vs. S2 (USMCA h2avg, monthly wts) by Product Group"
            local fig_st "Rate panel held fixed; weights shift -- the trade-diversion channel"
            local sfx "_titled"
        }
        else {
            local fig_t ""
            local fig_st ""
            local sfx ""
        }
        twoway ///
            (connected s1 ym, ///
                mcolor("$color_statutory") lcolor("$color_statutory") ///
                msymbol(circle) msize(vsmall) lwidth(medium) lpattern(solid)) ///
            (connected s2 ym, ///
                mcolor("$color_canada") lcolor("$color_canada") ///
                msymbol(diamond) msize(vsmall) lwidth(medium) lpattern(shortdash)) ///
            , ///
            by(pg_id, ///
                cols(3) ///
                title("`fig_t'") ///
                subtitle("`fig_st'") ///
                note("") ///
                graphregion(color(white))) ///
            legend(order( ///
                1 "S1: 2024 weights" ///
                2 "S2: monthly weights") rows(1) size(small) position(6)) ///
            ytitle("ETR (%)") xtitle("") ///
            xlabel(, format(%tmMon_CCYY) angle(45) labsize(vsmall)) ///
            ylabel(, labsize(vsmall))
        export_fig figure_s1s2_facets_product`sfx', width(3000)
    }
restore


di as text _n "  03_etr_analysis complete." _n
