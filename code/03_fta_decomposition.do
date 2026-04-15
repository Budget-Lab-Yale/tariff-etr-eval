* ==============================================================================
* 03_fta_decomposition.do
* Creator: John Iselin (ported from R_archive/R/02b_fta_decomposition.R)
* Date: April 2026
* Purpose: Decompose the Tier 2 → Tier 3 exemptions gap into preference
*          channels using IMDB detail data (cty_subco, rate_prov).
*
* Channels:
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
di as text "  03_fta_decomposition: FTA/Preference Channel Decomposition"
di as text "==========================================" _n


* ======================================================================
* A. LOAD AND CLASSIFY IMDB DETAIL DATA
* ======================================================================

di as text "  [A] Loading IMDB detail data..."

import delimited using "$raw/imdb_detail.csv", clear stringcols(1 2 3 4 5 6)

destring con_val_mo dut_val_mo cal_dut_mo, replace force

* Parse year/month from year_month string
gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm

* Keep analysis window only
keep if ym >= $start_ym & ym <= $end_ym

di as text "       `=_N' detail rows in analysis period"

* Assign partner groups
rename hs10 hs10_orig
rename cty_code cty_code_orig
gen str10 cty_code = cty_code_orig
assign_partner_group cty_code
rename hs10_orig hs10
rename cty_code_orig cty_code_str
rename cty_code cty_code_tmp
rename cty_code_str cty_code
drop cty_code_tmp


* --- Classify preference channels ---
gen str20 pref_channel = ""

* (a) USMCA: CA/MX with S/S+ preference codes
replace pref_channel = "usmca" if ///
    inlist(cty_subco, "S", "S+", "CA", "MX") & inlist(cty_code, "1220", "2010")

* (b) KORUS
replace pref_channel = "korus" if cty_subco == "KR"

* (c) Other bilateral FTAs
replace pref_channel = "other_fta" if pref_channel == "" & ///
    inlist(cty_subco, "AU", "IL", "SG", "CL", "CO", "PE", "PA", "JO")
replace pref_channel = "other_fta" if pref_channel == "" & ///
    inlist(cty_subco, "MA", "OM", "BH", "P", "P+", "R", "JP", "NP")

* (d) GSP / AGOA
replace pref_channel = "gsp_agoa" if pref_channel == "" & ///
    inlist(cty_subco, "A", "A+", "A*", "D", "E", "E*", "J", "J+", "J*")
replace pref_channel = "gsp_agoa" if pref_channel == "" & ///
    inlist(cty_subco, "W", "Z", "N")

* (e-i) Rate provision based channels (only if no preference already assigned)
replace pref_channel = "duty_free"     if pref_channel == "" & ///
    inlist(rate_prov, "10", "18", "19")
replace pref_channel = "ch99_dutiable" if pref_channel == "" & ///
    inlist(rate_prov, "69", "79")
replace pref_channel = "mfn_dutiable"  if pref_channel == "" & ///
    inlist(rate_prov, "61", "62", "64", "70")
replace pref_channel = "ftz_bonded"    if pref_channel == "" & rate_prov == "00"
replace pref_channel = "other"         if pref_channel == ""

label var pref_channel "Preference/rate channel"

compress
tempfile imdb_classified
save `imdb_classified'
di as text "       Classification complete"


* ======================================================================
* B. MERGE WITH STATUTORY RATES
* ======================================================================

di as text "  [B] Merging with statutory rates..."

* Map months to revisions
use "$working/revision_dates.dta", clear
sort eff_date
tempfile rev_dates
save `rev_dates'

use `imdb_classified', clear

* Cross with revision dates to find applicable revision per month
gen first_of_month = dofm(ym)
format first_of_month %td
cross using `rev_dates'
keep if eff_date <= first_of_month
bysort ym hs10 cty_code cty_subco dist_entry rate_prov (eff_date): keep if _n == _N
drop first_of_month eff_date eff_ym policy_event

* Merge statutory rates
merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) keepusing(total_rate) nogenerate
replace total_rate = 0 if missing(total_rate)

* Compute statutory vs actual duty at entry level
gen double statutory_duty = con_val_mo * total_rate
gen double actual_duty    = coalesce(cal_dut_mo, 0)
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

* Monthly total imports (for denominator)
bysort ym: egen double total_imports_m = total(con_val_mo)

* Channel aggregation
collapse ///
    (count)  entries = con_val_mo ///
    (sum)    imports = con_val_mo ///
             actual_duties = actual_duty ///
             statutory_duties = statutory_duty ///
             duty_savings = duty_savings ///
    (first)  total_imports_m, ///
    by(ym pref_channel)

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
* D. COUNTRY x CHANNEL DETAIL
* ======================================================================

di as text _n "  [D] Country x channel detail..."

use `imdb_with_rates', clear

bysort ym: egen double total_imports_m = total(con_val_mo)

collapse ///
    (sum)   imports = con_val_mo ///
            actual_duties = actual_duty ///
            statutory_duties = statutory_duty ///
            duty_savings = duty_savings ///
    (first) total_imports_m, ///
    by(ym partner_group pref_channel)

gen double gap_contrib_pp = duty_savings / total_imports_m * 100

sort ym partner_group pref_channel
compress
save "$working/fta_decomp_by_country.dta", replace
export delimited using "$tables/fta_decomp_by_country.csv", replace


* ======================================================================
* E. FTA UTILIZATION RATES
* ======================================================================

di as text "  [E] FTA utilization rates..."

use `imdb_with_rates', clear

* USMCA utilization for CA and MX
preserve
    keep if inlist(cty_code, "1220", "2010")
    gen byte is_usmca = inlist(cty_subco, "S", "S+", "CA", "MX")

    collapse (sum) total_imports = con_val_mo ///
                   usmca_imports = con_val_mo ///
             if is_usmca == 1, by(ym partner_group)
    * Need total imports for denominator — reload
    rename total_imports pref_imports
    tempfile usmca_pref
    save `usmca_pref'
restore

preserve
    keep if inlist(cty_code, "1220", "2010")
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
    keep if cty_code == "5800"
    gen byte is_korus = (cty_subco == "KR")
    collapse (sum) total_imports = con_val_mo ///
                   pref_imports = con_val_mo ///
             if is_korus == 1, by(ym partner_group)
    rename pref_imports korus_imports
    tempfile korus_pref
    save `korus_pref'
restore

preserve
    keep if cty_code == "5800"
    collapse (sum) total_imports = con_val_mo, by(ym partner_group)
    merge 1:1 ym partner_group using `korus_pref', nogenerate
    replace korus_imports = 0 if missing(korus_imports)
    rename korus_imports pref_imports
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


di as text _n "  03_fta_decomposition complete." _n
