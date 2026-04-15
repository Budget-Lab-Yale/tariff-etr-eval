* ==============================================================================
* 01_etr_clean.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Import all raw CSVs, clean, merge, and build the master analytical
*          dataset (merged_analysis.dta).
*
* Sections:
*   A. Census trade data (HS2 and HS10 x country x month)
*   B. Tracker data (daily ETRs, snapshot rates, revision dates, weights)
*   C. Treasury revenue (actual ETR)
*   D. Merge: Census x tracker snapshots at HS10 x country x month
*   E. Compute trade weights (2024 fixed + monthly)
*
* Input (all from $raw, produced by R/00_pull_raw_data.R):
*   census_hs2_country_monthly.csv
*   imdb_hs10_country_monthly.csv
*   daily_overall.csv, daily_by_country.csv
*   revision_dates.csv
*   snapshot_rates/snapshot_*.csv
*   import_weights_2024.csv
*   tariff_revenue.csv
*
* Output (all to $working):
*   census_hs2_clean.dta
*   census_hs10_clean.dta
*   tracker_daily.dta
*   tracker_daily_by_country.dta
*   revision_dates.dta
*   tracker_snapshots.dta
*   weights_2024.dta
*   revenue_monthly.dta
*   merged_analysis.dta          <-- master analytical dataset
* ==============================================================================

di as text _n "=========================================="
di as text "  01_etr_clean: Import, Clean, and Merge"
di as text "==========================================" _n


* ======================================================================
* A. CENSUS TRADE DATA
* ======================================================================

* --- A1. HS2 x country x month ---

di as text "  [A1] Census HS2 x country..."

import delimited using "$raw/census_hs2_country_monthly.csv", ///
    clear stringcols(1 2 5)

destring year month con_val_mo dut_val_mo effective_rate, replace force
gen int ym = ym(year, month)
format ym %tm

destring hs2, gen(hs2_num) force
label values hs2_num hs2_lbl

assign_partner_group cty_code

label var hs2           "HS2 chapter code"
label var cty_code      "Census country code"
label var con_val_mo    "Consumption value (USD)"
label var dut_val_mo    "Dutiable value (USD)"
label var effective_rate "Calculated duty ETR (%)"
label var ym            "Month (Stata date)"
label var partner_group "Trading partner group"

sort ym hs2 cty_code
compress
save "$working/census_hs2_clean.dta", replace
di as text "       `=_N' obs saved"


* --- A2. HS10 x country x month (IMDB source) ---

di as text "  [A2] Census HS10 x country (IMDB)..."

import delimited using "$raw/imdb_hs10_country_monthly.csv", ///
    clear stringcols(1 2 3)

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm

destring con_val_mo cal_dut_mo, replace force
safe_divide cal_dut_mo con_val_mo census_etr
gen str2 hs2 = substr(hs10, 1, 2)
assign_partner_group cty_code

label var hs10       "HTS10 product code"
label var cty_code   "Census country code"
label var con_val_mo "Consumption value (USD)"
label var cal_dut_mo "Calculated duty (USD)"
label var census_etr "Census ETR (ratio)"
label var hs2        "HS2 chapter"
label var ym         "Month (Stata date)"

sort ym hs10 cty_code
compress
save "$working/census_hs10_clean.dta", replace
di as text "       `=_N' obs saved"


* ======================================================================
* B. TRACKER DATA
* ======================================================================

* --- B1. Daily overall ETR ---

di as text "  [B1] Daily overall ETR..."

import delimited using "$raw/daily_overall.csv", clear stringcols(2)

gen daily_date = date(date, "YMD")
format daily_date %td

keep daily_date revision weighted_etr weighted_etr_additional ///
     matched_imports_b total_imports_b

label var daily_date    "Date"
label var revision      "HTS revision"
label var weighted_etr  "Import-weighted statutory ETR"

sort daily_date
compress
save "$working/tracker_daily.dta", replace
di as text "       `=_N' daily obs"


* --- B2. Daily ETR by country ---

di as text "  [B2] Daily ETR by country..."

import delimited using "$raw/daily_by_country.csv", clear stringcols(2 3 4)

gen daily_date = date(date, "YMD")
format daily_date %td
rename country cty_code
keep daily_date cty_code country_name revision weighted_etr

sort daily_date cty_code
compress
save "$working/tracker_daily_by_country.dta", replace
di as text "       `=_N' country-day obs"


* --- B3. Revision dates ---

di as text "  [B3] Revision dates..."

import delimited using "$raw/revision_dates.csv", clear varnames(1)

gen eff_date = date(effective_date, "YMD")
format eff_date %td
gen int eff_ym = mofd(eff_date)
format eff_ym %tm
capture tostring revision, replace

keep revision eff_date eff_ym policy_event
label var revision  "HTS revision identifier"
label var eff_date  "Effective date"
label var eff_ym    "Effective month"

sort eff_date
compress
save "$working/revision_dates.dta", replace
di as text "       `=_N' revisions"


* --- B4. Snapshot rates (loop over CSVs, append) ---

di as text "  [B4] Snapshot rates..."

local snap_dir "$raw/snapshot_rates"
local snap_files : dir "`snap_dir'" files "snapshot_*.csv"
local n_snaps : word count `snap_files'
di as text "       Found `n_snaps' snapshot CSV files"

tempfile snap_combined
local first_snap = 1

foreach f of local snap_files {
    local rev = subinstr("`f'", "snapshot_", "", 1)
    local rev = subinstr("`rev'", ".csv", "", 1)

    quietly {
        import delimited using "`snap_dir'/`f'", clear stringcols(1 2)
        gen str30 revision = "`rev'"

        capture rename country cty_code
        capture rename hts10 hs10

        foreach v of varlist total_rate statutory_rate_* rate_232 ///
                             metal_share steel_share aluminum_share ///
                             copper_share {
            capture destring `v', replace force
        }

        capture confirm variable usmca_eligible
        if _rc == 0 {
            gen byte usmca = (usmca_eligible == "TRUE")
            drop usmca_eligible
            rename usmca usmca_eligible
        }
    }

    if `first_snap' {
        save `snap_combined', replace
        local first_snap = 0
    }
    else {
        append using `snap_combined'
        save `snap_combined', replace
    }
}

use `snap_combined', clear
label var hs10       "HTS10 product code"
label var cty_code   "Census country code"
label var total_rate "Total statutory tariff rate"
label var revision   "HTS revision"

sort revision hs10 cty_code
compress
save "$working/tracker_snapshots.dta", replace
di as text "       `=_N' snapshot obs (all revisions)"


* --- B5. 2024 import weights ---

di as text "  [B5] 2024 import weights..."

import delimited using "$raw/import_weights_2024.csv", clear stringcols(1 2)
destring imports, replace force

egen double total_imports = total(imports)
gen double w_2024 = imports / total_imports

label var hs10          "HTS10 product code"
label var cty_code      "Census country code"
label var imports       "2024 imports (USD)"
label var total_imports "Total 2024 imports (USD)"
label var w_2024        "2024 import weight share"

sort hs10 cty_code
compress
save "$working/weights_2024.dta", replace
di as text "       `=_N' product-country pairs"


* ======================================================================
* C. TREASURY REVENUE
* ======================================================================

di as text "  [C] Treasury revenue..."

import delimited using "$raw/tariff_revenue.csv", clear
destring imports_value effective_rate, replace force

gen daily_date = date(date, "YMD")
format daily_date %td
gen int ym = mofd(daily_date)
format ym %tm

gen double actual_rate = effective_rate / 100

label var daily_date     "Date (first of month)"
label var ym             "Month (Stata date)"
label var customs_duties "Customs duties ($M, SAAR)"
label var imports_value  "Goods imports value ($M, SAAR)"
label var effective_rate "Actual ETR (%)"
label var actual_rate    "Actual ETR (ratio)"

sort ym
compress
save "$working/revenue_monthly.dta", replace
di as text "       `=_N' monthly obs"


* ======================================================================
* D. MERGE: Census HS10 x Tracker Snapshots
* ======================================================================

di as text _n "  [D] Building master analytical dataset..."

* --- D1. Month -> revision mapping ---

di as text "      Month-revision crosswalk..."

clear
local n_months = $end_ym - $start_ym + 1

set obs `n_months'
gen int ym = $start_ym + _n - 1
format ym %tm
gen first_of_month = dofm(ym)
format first_of_month %td

cross using "$working/revision_dates.dta"
keep if eff_date <= first_of_month
bysort ym (eff_date): keep if _n == _N

keep ym revision
tempfile month_rev_map
save `month_rev_map'
list, clean noobs

* --- D2. Merge Census with snapshot rates ---

di as text "      Merging Census x snapshots..."

use "$working/census_hs10_clean.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

local n_start = _N
di as text "      Census obs in analysis period: `n_start'"

merge m:1 ym using `month_rev_map', keep(match master) nogenerate
assert _N > 0

merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) nogenerate

* Unmatched products get zero statutory rate
local n_unmatched = _N - r(N)
replace total_rate = 0 if missing(total_rate)
di as text "      Snapshot match rate: " ///
    string(100 - 100 * `n_unmatched' / _N, "%4.1f") "%"


* ======================================================================
* E. COMPUTE TRADE WEIGHTS
* ======================================================================

di as text "      Computing trade weights..."

* Monthly weights
bysort ym: egen double total_imports_monthly = total(con_val_mo)
gen double w_monthly = con_val_mo / total_imports_monthly

* 2024 annual weights
merge m:1 hs10 cty_code using "$working/weights_2024.dta", ///
    keep(match master) keepusing(imports w_2024) nogenerate
replace imports = 0 if missing(imports)
replace w_2024  = 0 if missing(w_2024)

* Implied tariff revenue
gen double tariff_revenue_statutory = total_rate * con_val_mo
gen double tariff_revenue_2024      = total_rate * imports

* Ensure HS2 and partner group exist
capture confirm variable hs2
if _rc != 0 {
    gen str2 hs2 = substr(hs10, 1, 2)
}
capture confirm variable partner_group
if _rc != 0 {
    assign_partner_group cty_code
}

* Labels
label var w_monthly                 "Monthly import weight share"
label var total_imports_monthly     "Total monthly imports (USD)"
label var imports                   "2024 imports (USD)"
label var w_2024                    "2024 annual weight share"
label var tariff_revenue_statutory  "Implied statutory revenue (monthly wts)"
label var tariff_revenue_2024       "Implied statutory revenue (2024 wts)"

order ym hs10 hs2 cty_code partner_group ///
      con_val_mo cal_dut_mo census_etr ///
      total_rate tariff_revenue_statutory tariff_revenue_2024 ///
      w_monthly w_2024 imports revision

sort ym hs10 cty_code
compress
save "$working/merged_analysis.dta", replace

di as text _n "  Master analytical dataset: `=_N' observations"
di as text "  01_etr_clean complete." _n
