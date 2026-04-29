* ==============================================================================
* 02_counterfactual_ladder.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Waterfall decomposition of the statutory-actual ETR gap,
*          following Gopinath-Neiman (2026) methodology. Reads the rate
*          panels from merged_analysis.dta (built in 01) and aggregates
*          via compute_tier. Produces the canonical S0/S1/S2/S3 + T values
*          consumed downstream by 03_etr_analysis.do.
*
* Ladder steps (per the framework outline; see docs/six_tier_framework_plan.md):
*   S0: rate_2024            x imports         (USMCA 2024  x 2024 wts)
*   S1: rate_2024            x con_val_mo      (USMCA 2024  x monthly wts)
*   S2: rate_usmca_monthly   x con_val_mo      (USMCA monthly x monthly wts)
*   S3: rate_all_pref        x con_val_mo      (+ non-USMCA prefs x monthly wts)
*   T:  Treasury actual ETR
*
* (S4 = Census collected ETR is computed in 03_etr_analysis.do, not here.)
*
* Sections:
*   A. Load merged_analysis.dta once (used by both ladders below)
*   B. Aggregate ladder (4x compute_tier)
*   C. Treasury actual + combine + save aggregate ladder
*   D. Country-level ladder (4x compute_tier with byvar=partner_group)
*      -- Treasury not joined: revenue series isn't broken out by country.
*
* Gap channels:
*   S0 -> S1 = Trade diversion (weight shift, USMCA held at 2024 baseline)
*   S1 -> S2 = USMCA surge (preference claiming response to tariff escalation)
*   S2 -> S3 = All-other preferences (Annex II / ITA / Ch98 / KORUS / GSP / FTAs)
*   S3 -> T  = Residual + timing/enforcement
*
* Input:
*   $working/merged_analysis.dta   (carries rate_2024, rate_usmca_monthly,
*                                   rate_all_pref, imports, con_val_mo)
*   $working/revenue_monthly.dta   (Treasury actual ETR)
*
* Output:
*   $working/counterfactual_ladder.dta      + $tables/counterfactual_ladder.csv
*   $working/counterfactual_by_country.dta  + $tables/counterfactual_by_country.csv
*   $tables/counterfactual_by_country_avg.csv  (period-averaged tier values
*       and gaps by partner_group)
* ==============================================================================

di as text _n "=========================================="
di as text "  02_counterfactual_ladder: Waterfall Decomposition"
di as text "==========================================" _n


* ======================================================================
* A. LOAD MASTER PANEL ONCE
* ======================================================================

di as text "  [A] Loading merged_analysis (used for both aggregate and country ladders)..."

use "$working/merged_analysis.dta", clear
keep if ym >= $start_ym & ym <= $end_ym
capture confirm variable partner_group
if _rc != 0 assign_partner_group cty_code

tempfile master
save `master'


* ======================================================================
* B. AGGREGATE LADDER
* ======================================================================

di as text _n "  [B] Computing aggregate ladder tiers..."

tempfile tier_s0 tier_s1 tier_s2 tier_s3

preserve
    di as text "      S0: rate_2024 x imports (2024 wts)"
    compute_tier, ratevar(rate_2024) weightvar(imports) ///
        outfile(`tier_s0') outvar(s0) percent
restore

preserve
    di as text "      S1: rate_2024 x con_val_mo (monthly wts)"
    compute_tier, ratevar(rate_2024) weightvar(con_val_mo) ///
        outfile(`tier_s1') outvar(s1) percent
restore

preserve
    di as text "      S2: rate_usmca_monthly x con_val_mo (monthly wts)"
    compute_tier, ratevar(rate_usmca_monthly) weightvar(con_val_mo) ///
        outfile(`tier_s2') outvar(s2) percent
restore

preserve
    di as text "      S3: rate_all_pref x con_val_mo (monthly wts)"
    compute_tier, ratevar(rate_all_pref) weightvar(con_val_mo) ///
        outfile(`tier_s3') outvar(s3) percent
restore


* ======================================================================
* C. TREASURY ACTUAL + COMBINE (aggregate)
* ======================================================================

di as text _n "  [C] Combining tiers and computing gaps..."

use `tier_s0', clear
merge 1:1 ym using `tier_s1', nogenerate
merge 1:1 ym using `tier_s2', nogenerate
merge 1:1 ym using `tier_s3', nogenerate
merge 1:1 ym using "$working/revenue_monthly.dta", ///
    keep(match master) keepusing(actual_rate) nogenerate
rename actual_rate treasury_actual
replace treasury_actual = treasury_actual * 100

* Validate
assert _N > 0
foreach v in s0 s1 s2 s3 {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "WARNING: `v' has " r(N) " missing values"
    }
}

* Gap channels (pp). Sequential: each rung subtracts one channel.
gen double gap_diversion = s0 - s1
gen double gap_usmca     = s1 - s2
gen double gap_others    = s2 - s3
gen double gap_residual  = s3 - treasury_actual if !missing(treasury_actual)
gen double gap_total     = s0 - treasury_actual if !missing(treasury_actual)

* Labels
label var s0               "S0: Statutory (USMCA 2024), 2024 wts (%)"
label var s1               "S1: Statutory (USMCA 2024), monthly wts (%)"
label var s2               "S2: Statutory (USMCA monthly), monthly wts (%)"
label var s3               "S3: + non-USMCA preferences, monthly wts (%)"
label var treasury_actual  "T: Treasury actual ETR (%)"
label var gap_diversion    "Trade diversion gap S0-S1 (pp)"
label var gap_usmca        "USMCA surge gap S1-S2 (pp)"
label var gap_others       "All-others preference gap S2-S3 (pp)"
label var gap_residual     "Residual gap S3-T (pp)"
label var gap_total        "Total gap S0-T (pp)"

di as text _n "  === Counterfactual Ladder ==="
format s0 s1 s2 s3 treasury_actual %9.2f
format gap_* %9.2f
list ym s0 s1 s2 s3 treasury_actual, clean noobs

di as text _n "  === Gap Decomposition (pp) ==="
list ym gap_diversion gap_usmca gap_others gap_residual gap_total, clean noobs

sort ym
compress
save "$working/counterfactual_ladder.dta", replace
export delimited using "$tables/counterfactual_ladder.csv", replace


* ======================================================================
* D. COUNTRY-LEVEL LADDER
* ======================================================================
*
* Mirrors the aggregate ladder but with byvar(partner_group). Treasury (T) is
* NOT joined here -- the Treasury revenue series isn't broken out by country,
* so there's no T to compute the S3 -> T residual against. Country-level
* analysis stops at S3.
*
* Column naming matches the aggregate ladder (s0/s1/s2/s3) so cross-references
* between the two datasets don't have to mentally translate suffixes.

di as text _n "  [D] Country-level ladder..."

tempfile cty_s0 cty_s1 cty_s2 cty_s3

use `master', clear

preserve
    di as text "      S0 by country"
    compute_tier, ratevar(rate_2024) weightvar(imports) ///
        outfile(`cty_s0') outvar(s0) byvar(partner_group) percent
restore

preserve
    di as text "      S1 by country"
    compute_tier, ratevar(rate_2024) weightvar(con_val_mo) ///
        outfile(`cty_s1') outvar(s1) byvar(partner_group) percent
restore

preserve
    di as text "      S2 by country"
    compute_tier, ratevar(rate_usmca_monthly) weightvar(con_val_mo) ///
        outfile(`cty_s2') outvar(s2) byvar(partner_group) percent
restore

preserve
    di as text "      S3 by country"
    compute_tier, ratevar(rate_all_pref) weightvar(con_val_mo) ///
        outfile(`cty_s3') outvar(s3) byvar(partner_group) percent
restore

use `cty_s0', clear
merge 1:1 ym partner_group using `cty_s1', nogenerate
merge 1:1 ym partner_group using `cty_s2', nogenerate
merge 1:1 ym partner_group using `cty_s3', nogenerate

assert _N > 0

gen double gap_diversion = s0 - s1
gen double gap_usmca     = s1 - s2
gen double gap_others    = s2 - s3
gen double gap_s0_s3     = s0 - s3

label var s0            "S0: Statutory (USMCA 2024), 2024 wts (%)"
label var s1            "S1: Statutory (USMCA 2024), monthly wts (%)"
label var s2            "S2: Statutory (USMCA monthly), monthly wts (%)"
label var s3            "S3: + non-USMCA preferences, monthly wts (%)"
label var gap_diversion "Trade diversion (pp)"
label var gap_usmca     "USMCA surge (pp)"
label var gap_others    "All-others preferences (pp)"
label var gap_s0_s3     "Total S0-S3 gap (pp)"

sort ym partner_group
compress
save "$working/counterfactual_by_country.dta", replace
export delimited using "$tables/counterfactual_by_country.csv", replace

* Summary: time-averaged by country (CSV exported for downstream / paper use).
preserve
    collapse (mean) s0 s1 s2 s3 ///
                    gap_diversion gap_usmca gap_others, ///
        by(partner_group)

    label var s0            "S0 period avg (%)"
    label var s1            "S1 period avg (%)"
    label var s2            "S2 period avg (%)"
    label var s3            "S3 period avg (%)"
    label var gap_diversion "Trade diversion period avg (pp)"
    label var gap_usmca     "USMCA surge period avg (pp)"
    label var gap_others    "All-others preferences period avg (pp)"

    di as text _n "  === Country-Level Ladder (period average) ==="
    format s0 s1 s2 s3 gap_diversion gap_usmca gap_others %9.2f
    list partner_group s0 s1 s2 s3 ///
         gap_diversion gap_usmca gap_others, clean noobs

    export delimited using "$tables/counterfactual_by_country_avg.csv", replace
restore


di as text _n "  02_counterfactual_ladder complete." _n
