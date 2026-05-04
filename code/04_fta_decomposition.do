* ==============================================================================
* 04_fta_decomposition.do
* Creator: John Iselin (ported from R_archive/R/02b_fta_decomposition.R)
* Date: April 2026
* Purpose: Decompose the S2 -> S3 (all-other preferences) channel of the
*          six-tier framework into preference / rate-provision categories
*          using IMDB detail data (cty_subco, rate_prov). Per-channel
*          duty savings show which preferences carry the gap and how
*          utilization rates evolve.
*
* Channels (mirrored in classify_pref_channel; see programs.do):
*   (a) USMCA: CA/MX imports under S/S+ preference codes
*   (b) KORUS: S. Korea under KR preference
*   (c) Other FTA: AU, IL, SG, CL, CO, PE, PA, JO, MA, OM, BH, etc.
*   (d) GSP/AGOA: A/A+/A*/D/E/J/W/Z/N codes
*   (e) Duty-free entries: rate_prov 10/18/19
*   (f) Ch99 dutiable: rate_prov 69/79
*   (g) MFN dutiable: rate_prov 61/62/64/70
*   (h) FTZ/bonded: rate_prov 00
*   (i) Other/residual
*
* Input:
*   $raw/imdb_detail.csv           (from R/00_pull_raw_data.R, rich parse)
*   $working/tracker_snapshots.dta (from 01_etr_clean.do)
*   $working/revision_dates.dta
*
* Output:
*   $tables/fta_decomp_monthly.csv
*   $tables/fta_decomp_by_country.csv
*   $tables/fta_utilization_rates.csv
* ==============================================================================

di as text _n "=========================================="
di as text "  04_fta_decomposition: FTA/Preference Channel Decomposition"
di as text "==========================================" _n


* ======================================================================
* A. LOAD AND CLASSIFY IMDB DETAIL DATA
* ======================================================================

di as text "  [A] Loading IMDB detail data..."

import delimited using "$raw/imdb_detail.csv", clear stringcols(1 2 3 4 5 6)

destring con_val_mo dut_val_mo cal_dut_mo, replace force

** Warn on coercion failures: `force` silently converts non-numeric to missing.
qui count if missing(con_val_mo)
if r(N) > 0 {
    di as error "WARNING: `=r(N)' rows have missing con_val_mo after destring force"
}

* Parse year/month from year_month string
gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm

* Keep analysis window only
keep if ym >= $start_ym & ym <= $end_ym

di as text "       `=_N' detail rows in analysis period"

* Assign partner groups (cty_code is already string from stringcols)
assign_partner_group cty_code


* --- Classify preference channels (program from programs.do) ---
classify_pref_channel cty_subco rate_prov cty_code

compress
tempfile imdb_classified
save `imdb_classified'
di as text "       Classification complete"


* ======================================================================
* B. MERGE WITH STATUTORY RATES
* ======================================================================

di as text "  [B] Merging with statutory rates..."

** Build month -> revision mapping (program from programs.do)
tempfile month_rev_map
build_month_rev_map, saving(`month_rev_map')

** Merge revision onto IMDB data via month
use `imdb_classified', clear
merge m:1 ym using `month_rev_map', keep(match master) nogenerate

* Merge statutory rates
merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) keepusing(total_rate) gen(_merge_snap)

qui count if _merge_snap == 3
local n_matched = r(N)
qui count if _merge_snap == 1
local n_unmatched = r(N)
local match_rate = 100 * `n_matched' / _N
di as text "       Snapshot match: `n_matched' matched, `n_unmatched' unmatched (" ///
    string(`match_rate', "%4.1f") "%)"
if `match_rate' < 90 {
    di as error "WARNING: snapshot match rate below 90% -- investigate"
}
drop _merge_snap

* Unmatched products get zero statutory rate (consistent with 01_etr_clean.do).
replace total_rate = 0 if missing(total_rate)

* Compute statutory vs actual duty at entry level
gen double statutory_duty = con_val_mo * total_rate
gen double actual_duty    = cond(missing(cal_dut_mo), 0, cal_dut_mo)
gen double duty_savings   = statutory_duty - actual_duty

label var statutory_duty "Implied statutory duty at tracker rate"
label var actual_duty    "Actual calculated duty (Census)"
label var duty_savings   "Duty savings (statutory - actual)"

compress
tempfile imdb_with_rates
save `imdb_with_rates'
di as text "       `=_N' entries with rates"


* ======================================================================
* C. MONTHLY CHANNEL DECOMPOSITION
* ======================================================================

di as text "  [C] Monthly channel decomposition..."

use `imdb_with_rates', clear

* Channel aggregation
collapse ///
    (count)  entries = con_val_mo ///
    (sum)    imports = con_val_mo ///
             actual_duties = actual_duty ///
             statutory_duties = statutory_duty ///
             duty_savings = duty_savings, ///
    by(ym pref_channel)

* Re-derive monthly total post-collapse (sum across channels per ym).
bysort ym: egen double total_imports_m = total(imports)

* Metrics
gen double import_share    = imports / total_imports_m
gen double gap_contrib_pp  = duty_savings / total_imports_m * 100
safe_divide actual_duties imports actual_etr
safe_divide statutory_duties imports statutory_etr

label var entries         "Number of entries"
label var imports         "Import value ($)"
label var actual_duties   "Actual duties ($)"
label var statutory_duties "Statutory duties ($)"
label var duty_savings    "Duty savings ($)"
label var import_share    "Share of monthly imports"
label var gap_contrib_pp  "Contribution to ETR gap (pp)"
label var actual_etr      "Actual ETR (ratio)"
label var statutory_etr   "Statutory ETR (ratio)"

sort ym pref_channel
compress
save "$working/fta_decomp_monthly.dta", replace
export delimited using "$tables/fta_decomp_monthly.csv", replace

di as text _n "  === Monthly FTA Decomposition ==="
format gap_contrib_pp import_share %9.3f
list ym pref_channel gap_contrib_pp import_share if ///
    abs(gap_contrib_pp) > 0.01, clean noobs


* ======================================================================
* C2. AGGREGATE S2->S3 STACKED BAR BY PREFERENCE CHANNEL  (Fig)
* ======================================================================
*
* Stacked bar by ym, segments = preference channels. Each segment is the
* per-channel contribution to the overall S2 -> S3 gap, in pp. Seven
* channels grouped into three policy-salience tiers:
*   Major IEEPA carve-outs:    duty_free  (Annex II / ITA / Ch98 / Pharma)
*   Bilateral FTAs:            korus, other_fta
*   GSP / AGOA:                gsp_agoa
*   Other (small):             ch99_dutiable, mfn_dutiable, ftz_bonded, other
* The "Other" group is rolled up into a single small segment for visual.

di as text _n "  [C2] S2 -> S3 stacked-bar figure..."

preserve
    use "$working/fta_decomp_monthly.dta", clear
    keep ym pref_channel gap_contrib_pp

    * Roll up the four "noise / non-preference" channels into one segment.
    gen str20 channel_grp = pref_channel
    replace channel_grp = "other_residual" if ///
        inlist(pref_channel, "ch99_dutiable", "mfn_dutiable", "ftz_bonded", "other")

    collapse (sum) gap_contrib_pp, by(ym channel_grp)

    * Reshape wide for the stacked-bar
    reshape wide gap_contrib_pp, i(ym) j(channel_grp) string
    foreach ch in usmca duty_free korus gsp_agoa other_fta other_residual {
        capture rename gap_contrib_pp`ch' c_`ch'
        capture confirm variable c_`ch'
        if _rc != 0 gen double c_`ch' = 0
        replace c_`ch' = 0 if missing(c_`ch')
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
            local fig_t "Other Preferences (S2 - S3 gap), by Channel"
            local fig_st "Stacked monthly contributions, pp"
            local sfx "_titled"
        }
        else {
            local fig_t ""
            local fig_st ""
            local sfx ""
        }
        graph bar (asis) c_duty_free c_korus c_other_fta c_gsp_agoa c_usmca c_other_residual, ///
            over(ym_idx, relabel(`relabel_str') ///
                         label(angle(45) labsize(vsmall))) ///
            stack ///
            bar(1, color("$color_statutory")) ///
            bar(2, color("$color_canada")) ///
            bar(3, color("$color_eu")) ///
            bar(4, color("$color_japan")) ///
            bar(5, color("$color_skorea")) ///
            bar(6, color("$color_gray")) ///
            legend(order( ///
                1 "Duty-free (Annex II/ITA/Ch98/Pharma)" ///
                2 "KORUS" ///
                3 "Other FTAs" ///
                4 "GSP / AGOA" ///
                5 "USMCA (residual after S0->S1)" ///
                6 "Other (Ch99, MFN, FTZ, residual)") ///
                rows(2) size(vsmall) position(6)) ///
            ytitle("Contribution to S2 - S3 gap (pp)") ///
            title("`fig_t'") ///
            subtitle("`fig_st'") ///
            graphregion(color(white))
        export_fig figure_others_channel_stack`sfx'
    }
restore


* ======================================================================
* D. COUNTRY x CHANNEL DETAIL
* ======================================================================

di as text _n "  [D] Country x channel detail..."

use `imdb_with_rates', clear

collapse ///
    (sum)   imports = con_val_mo ///
            actual_duties = actual_duty ///
            statutory_duties = statutory_duty ///
            duty_savings = duty_savings, ///
    by(ym partner_group pref_channel)

* Re-derive monthly total post-collapse (sum across all partner x channel cells per ym).
bysort ym: egen double total_imports_m = total(imports)

gen double gap_contrib_pp = duty_savings / total_imports_m * 100

label var imports          "Import value ($)"
label var actual_duties    "Actual duties ($)"
label var statutory_duties "Statutory duties ($)"
label var duty_savings     "Duty savings ($)"
label var total_imports_m  "Total monthly imports across all channels ($)"
label var gap_contrib_pp   "Contribution to ETR gap (pp)"

sort ym partner_group pref_channel
compress
save "$working/fta_decomp_by_country.dta", replace
export delimited using "$tables/fta_decomp_by_country.csv", replace


* ======================================================================
* E. FTA UTILIZATION RATES
* ======================================================================

di as text "  [E] FTA utilization rates..."

use `imdb_with_rates', clear

* Utilization rates use the canonical pref_channel column from
* classify_pref_channel (Section A) -- no inline cty_subco re-bucketing.
* Numerator: imports with the program's pref_channel; denominator: all
* imports from that program's eligible country/group.

* USMCA utilization for CA and MX
preserve
    keep if inlist(cty_code, "$cty_canada", "$cty_mexico")
    collapse (sum) pref_imports = con_val_mo ///
             if pref_channel == "usmca", by(ym partner_group)
    tempfile usmca_pref
    save `usmca_pref'
restore

preserve
    keep if inlist(cty_code, "$cty_canada", "$cty_mexico")
    collapse (sum) total_imports = con_val_mo, by(ym partner_group)
    merge 1:1 ym partner_group using `usmca_pref', nogenerate
    replace pref_imports = 0 if missing(pref_imports)
    safe_divide pref_imports total_imports utilization_rate
    gen str10 program = "USMCA"
    label var utilization_rate "Share of imports using preference"
    tempfile util_usmca
    save `util_usmca'
restore

* KORUS utilization
preserve
    keep if cty_code == "$cty_skorea"
    collapse (sum) pref_imports = con_val_mo ///
             if pref_channel == "korus", by(ym partner_group)
    tempfile korus_pref
    save `korus_pref'
restore

preserve
    keep if cty_code == "$cty_skorea"
    collapse (sum) total_imports = con_val_mo, by(ym partner_group)
    merge 1:1 ym partner_group using `korus_pref', nogenerate
    replace pref_imports = 0 if missing(pref_imports)
    safe_divide pref_imports total_imports utilization_rate
    gen str10 program = "KORUS"
    tempfile util_korus
    save `util_korus'
restore

* Combine utilization tables
use `util_usmca', clear
append using `util_korus'
sort ym program partner_group
compress
save "$working/fta_utilization_rates.dta", replace
export delimited using "$tables/fta_utilization_rates.csv", replace

di as text _n "  === USMCA/KORUS Utilization Rates ==="
format utilization_rate %9.3f
list ym partner_group program utilization_rate, clean noobs


di as text _n "  04_fta_decomposition complete." _n
