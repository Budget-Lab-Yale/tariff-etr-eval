* ==============================================================================
* validate_s3.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Sanity-check the new S3 (all-other preferences) tier in the six-tier
*          framework. Run after 02_counterfactual_ladder.do has executed.
*
* Checks:
*   1. Aggregate ETR identity: gap_total = sum of channel gaps to numerical precision
*   2. Sign-reversal months (aggregate): months where S0 < S1 (reverse diversion)
*      or S1 < S2 (USMCA claim-rate dip). NOT bugs -- channels are bidirectional.
*      S2 < S3 SHOULD be impossible (delta math is non-negative); flagged as bug
*      if observed.
*   3. Sign-reversal cells (country x month): same pattern, per partner_group.
*   4. Cross-check vs 04 fta_decomp_monthly: S2-S3 magnitude vs sum of
*      gap_contrib_pp for {duty_free, korus, gsp_agoa, other_fta}. Directional
*      consistency expected; magnitudes differ (S2-S3 includes only base + recip
*      per the applicability matrix; 04's gap_contrib_pp uses full pre-pref rate).
*   5. Country-level expected pattern:
*        gap_others ~ 0    for CA / MX (preference activity already in USMCA)
*        gap_others > 0    for KR (KORUS), ROW, EU/JP (Annex II, GSP, FTAs)
*
* See docs/six_tier_framework_plan.md sec. 5a for the bidirectional channels
* discussion (why negative gap_diversion / gap_usmca months are findings, not bugs).
*
* Usage:
*   cd "C:/Users/ji252/Documents/GitHub/tariff-etr-eval"
*   do scripts/validate_s3.do
* ==============================================================================

* Setup: mirrors orchestrator
clear all
set more off
set maxvar 10000
global dir "`c(pwd)'/"
global dir : subinstr global dir "\" "/" , all
do "${dir}code/utils/globals.do"
do "${dir}code/utils/programs.do"

di as text _n "=========================================="
di as text "  validate_s3: six-tier sanity checks"
di as text "==========================================" _n


* ======================================================================
* 1. Aggregate ETR identity (gap accounting closes)
* ======================================================================

di as text "  [1] Aggregate ETR identity..."

use "${working}/counterfactual_ladder.dta", clear

gen double gap_check = gap_diversion + gap_usmca + gap_others + gap_residual
gen double gap_diff  = gap_check - gap_total

qui sum gap_diff, detail
local max_abs = max(abs(r(min)), abs(r(max)))
di as text "      max |gap_check - gap_total| = " %9.6f `max_abs'

if `max_abs' > 1e-6 {
    di as error "      FAIL: gap accounting does not close (tol 1e-6)"
    list ym gap_diversion gap_usmca gap_others gap_residual gap_total gap_check ///
        if abs(gap_diff) > 1e-6
}
else {
    di as text "      PASS"
}


* ======================================================================
* 2. Aggregate sign-reversal months
* ======================================================================
*
* S0->S1 sign flip: monthly weights produced higher ETR than 2024 weights
*   (reverse trade diversion -- composition shifted INTO higher-tariff cells)
* S1->S2 sign flip: monthly USMCA claims fell below 2024 baseline
*   (early-period firm-response lag; the canonical mid-2025 ramp dominates)
* S2->S3 sign flip: SHOULD NEVER OCCUR (delta math is non-negative)

di as text _n "  [2] Aggregate sign-reversal months..."

foreach pair in s0_s1 s1_s2 s2_s3 {
    if "`pair'" == "s0_s1" local pair_diff "s0 - s1"
    if "`pair'" == "s1_s2" local pair_diff "s1 - s2"
    if "`pair'" == "s2_s3" local pair_diff "s2 - s3"

    qui count if (`pair_diff') < -1e-3
    local n = r(N)
    di as text "      `pair' (`pair_diff') < 0: `n' months"
}

qui count if (s2 - s3) < -1e-3
local n_s2s3 = r(N)
if `n_s2s3' > 0 {
    di as error "      BUG: `n_s2s3' months have S2 < S3 (delta math should preclude this)"
}
else {
    di as text "      PASS: S2 >= S3 holds in every month (delta math sound)"
}


* ======================================================================
* 3. Country-level sign-reversal cells
* ======================================================================

di as text _n "  [3] Country-level sign-reversal cells..."

use "${working}/counterfactual_by_country.dta", clear

foreach pair in s0_s1 s1_s2 s2_s3 {
    if "`pair'" == "s0_s1" local pair_diff "s0_etr - s1_etr"
    if "`pair'" == "s1_s2" local pair_diff "s1_etr - s2_etr"
    if "`pair'" == "s2_s3" local pair_diff "s2_etr - s3_etr"

    qui count if (`pair_diff') < -1e-3
    local n = r(N)
    di as text "      `pair' (`pair_diff') < 0: `n' cty x ym cells"
}

qui count if (s2_etr - s3_etr) < -1e-3
local n_s2s3 = r(N)
if `n_s2s3' > 0 {
    di as error "      BUG: `n_s2s3' cty x ym cells have S2 < S3"
}
else {
    di as text "      PASS: S2 >= S3 holds in every cty x ym cell"
}

* Per-country diagnostic on sign-bearing channels
di as text _n "      Per-country diagnostic (period averages):"

preserve
    collapse (mean) gap_diversion gap_usmca gap_others, by(partner_group)

    gen str10 div_sign  = cond(gap_diversion < -0.05, "neg",   ///
                          cond(gap_diversion >  0.05, "pos", "~0"))
    gen str10 usm_sign  = cond(gap_usmca < -0.05,    "neg",   ///
                          cond(gap_usmca >  0.05,    "pos", "~0"))
    gen str10 oth_sign  = cond(gap_others <  0,      "BUG",   ///
                          cond(gap_others >  0.05,   "pos", "~0"))

    format gap_diversion gap_usmca gap_others %9.2f
    list partner_group gap_diversion div_sign gap_usmca usm_sign ///
         gap_others oth_sign, clean noobs
restore


* ======================================================================
* 4. Cross-check S2-S3 vs 03 fta_decomp duty_free + korus + gsp + other_fta
* ======================================================================

di as text _n "  [4] Cross-check S2-S3 vs 03 fta_decomp (directional)..."
di as text "      (These will not match exactly: 03's gap_contrib_pp uses the"
di as text "       full pre-preference rate, while S2-S3 uses only base + recip"
di as text "       per the applicability matrix. We expect S2-S3 < 03's sum.)"

* Aggregate s2-s3 by month
use "${working}/counterfactual_ladder.dta", clear
keep ym gap_others
rename gap_others s2_minus_s3
tempfile s23
save `s23'

* 03's monthly preference channel contribution
use "${working}/fta_decomp_monthly.dta", clear
keep if inlist(pref_channel, "duty_free", "korus", "gsp_agoa", "other_fta")
collapse (sum) gap_contrib_pp_03 = gap_contrib_pp, by(ym)

merge 1:1 ym using `s23', nogenerate

format s2_minus_s3 gap_contrib_pp_03 %9.3f
di as text "      Month-by-month: S2-S3 vs 03 sum"
list ym s2_minus_s3 gap_contrib_pp_03, clean noobs


* ======================================================================
* 5. Country-level expected pattern check
* ======================================================================

di as text _n "  [5] Country-level expected pattern check..."
di as text "      Expected: CA/MX gap_others ~ 0 (preferences captured by USMCA)"
di as text "                KR gap_others > 0 (KORUS)"
di as text "                ROW gap_others > 0 (Annex II / ITA)"

use "${working}/counterfactual_by_country.dta", clear
collapse (mean) gap_usmca gap_others, by(partner_group)
format gap_usmca gap_others %9.2f
list partner_group gap_usmca gap_others, clean noobs

* Spot-check assertions
foreach cty in "Canada" "Mexico" {
    qui sum gap_others if partner_group == "`cty'"
    if abs(r(mean)) > 0.5 {
        di as error "      WARNING: `cty' gap_others = " %5.2f r(mean) " (expected ~0)"
    }
}

qui sum gap_others if partner_group == "S. Korea"
if r(mean) < 0.3 {
    di as error "      WARNING: S. Korea gap_others = " %5.2f r(mean) " (expected > 0.3)"
}

qui sum gap_others if partner_group == "ROW"
if r(mean) < 0.3 {
    di as error "      WARNING: ROW gap_others = " %5.2f r(mean) " (expected > 0.3)"
}


di as text _n "  validate_s3 complete." _n
