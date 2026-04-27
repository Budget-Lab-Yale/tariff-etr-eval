* ==============================================================================
* 01_etr_clean.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Import all raw CSVs, clean, merge, and build the master analytical
*          dataset (merged_analysis.dta).
*
* Sections:
*   A. Census trade data (HS10 x country x month from IMDB; HS2 derived
*      downstream via substr(hs10,1,2))
*   B. Tracker data (daily ETRs, snapshot rates, revision dates, weights)
*   C. Treasury revenue (actual ETR)
*   D. Merge: Census x tracker snapshots at HS10 x country x month
*   E. Compute trade weights (2024 fixed + monthly)
*
* Input (all from $raw, produced by R/00_pull_raw_data.R):
*   imdb_hs10_country_monthly.csv
*   daily_overall.csv, daily_by_country.csv
*   revision_dates.csv
*   snapshot_rates/snapshot_*.csv
*   import_weights_2024.csv
*   tariff_revenue.csv
*
* Output (all to $working):
*   census_hs10_clean.dta
*   tracker_daily.dta
*   tracker_daily_by_country.dta
*   revision_dates.dta
*   tracker_snapshots.dta
*   weights_2024.dta
*   revenue_monthly.dta
*   merged_analysis.dta          <-- master analytical dataset
*
* Note: census_hs2_country_monthly.csv (Census HS2 API) is no longer imported
* here. HS2-level analyses aggregate IMDB HS10 data instead. The R section
* that pulls HS2 from the Census API is preserved for ad-hoc use but not
* consumed by this pipeline.
* ==============================================================================

di as text _n "=========================================="
di as text "  01_etr_clean: Import, Clean, and Merge"
di as text "==========================================" _n


* ======================================================================
* A. CENSUS TRADE DATA
* ======================================================================
*
* HS10 x country x month from the IMDB bulk parse. HS2 chapter is derived
* via substr(hs10, 1, 2) and HS2-level rollups (e.g. chapter ranking in
* 02_etr_analysis.do) collapse this dataset rather than importing from
* the Census HS2 API.

* --- A1. HS10 x country x month (IMDB source) ---

di as text "  [A1] Census HS10 x country (IMDB)..."

import delimited using "$raw/imdb_hs10_country_monthly.csv", ///
    clear stringcols(1 2 3)

** Generate date information 
gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year_month 

** Run assign partern code 
assign_partner_group cty_code

** Calculate census ETR 
safe_divide cal_dut_mo con_val_mo census_etr

** Get HS2 value 
gen str2 hs2 = substr(hs10, 1, 2)

** Set up labels
label var hs10       "HTS10 product code"
label var cty_code   "Census country code"
label var con_val_mo "Consumption value (USD)"
label var cal_dut_mo "Calculated duty (USD)"
label var census_etr "Census ETR (ratio)"
label var hs2        "HS2 chapter"
label var ym         "Month (Stata date)"
label var partner_group "Trading partner group"

sort ym year month hs2 hs10 cty_code partner_group
order ym year month hs2 hs10 cty_code partner_group

compress
save "$working/census_hs10_clean.dta", replace
di as text "       `=_N' obs saved"


* ======================================================================
* B. TRACKER DATA
* ======================================================================

* --- B1. Daily overall ETR ---

di as text "  [B1] Daily overall ETR..."

import delimited using "$raw/daily_overall.csv", clear stringcols(2)

** Generate date
gen daily_date = date(date, "YMD")
format daily_date %td
drop date

** Keep relevant variables
keep daily_date revision weighted_etr weighted_etr_additional ///
     matched_imports_b total_imports_b

** Set up labels
label var daily_date              "Date"
label var revision                "HTS revision"
label var weighted_etr            "Import-weighted statutory ETR"
label var weighted_etr_additional "Additional statutory ETR"
label var matched_imports_b       "Matched imports ($B)"
label var total_imports_b         "Total imports ($B)"

order daily_date revision weighted_etr
sort daily_date
compress
save "$working/tracker_daily.dta", replace
di as text "       `=_N' daily obs"


* --- B2. Daily ETR by country ---

di as text "  [B2] Daily ETR by country..."

import delimited using "$raw/daily_by_country.csv", clear stringcols(2 3 4)

** Generate date and standardize column names
gen daily_date = date(date, "YMD")
format daily_date %td
rename country cty_code
drop date

** Keep relevant variables
keep daily_date cty_code country_name revision weighted_etr

** Set up labels
label var daily_date    "Date"
label var cty_code      "Census country code"
label var country_name  "Country name"
label var revision      "HTS revision"
label var weighted_etr  "Import-weighted statutory ETR"

order daily_date cty_code country_name revision weighted_etr
sort daily_date cty_code
compress
save "$working/tracker_daily_by_country.dta", replace
di as text "       `=_N' country-day obs"


* --- B3. Revision dates ---

di as text "  [B3] Revision dates..."

import delimited using "$raw/revision_dates.csv", clear varnames(1)

** Generate date information
gen eff_date = date(effective_date, "YMD")
format eff_date %td
gen int eff_ym = mofd(eff_date)
format eff_ym %tm
capture tostring revision, replace

** Keep relevant variables
keep revision eff_date eff_ym policy_event

** Set up labels
label var revision     "HTS revision identifier"
label var eff_date     "Effective date"
label var eff_ym       "Effective month"
label var policy_event "Policy event description"

order revision eff_date eff_ym policy_event
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

        ** Standardize column names
        capture rename country cty_code
        capture rename hts10 hs10

        ** Destring numeric rate and share columns
        foreach v of varlist total_rate statutory_rate_* rate_232 ///
                             metal_share steel_share aluminum_share ///
                             copper_share {
            capture destring `v', replace force
        }

        ** Convert logical columns from "TRUE"/"FALSE" to byte
        capture confirm variable usmca_eligible
        if _rc == 0 {
            gen byte usmca = (usmca_eligible == "TRUE")
            drop usmca_eligible
            rename usmca usmca_eligible
        }

        capture confirm variable s232_usmca_eligible
        if _rc == 0 {
            gen byte s232_usmca = (s232_usmca_eligible == "TRUE")
            drop s232_usmca_eligible
            rename s232_usmca s232_usmca_eligible
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

** Set up labels
label var hs10       "HTS10 product code"
label var cty_code   "Census country code"
label var total_rate "Total statutory tariff rate"
label var revision   "HTS revision"
capture label var usmca_eligible      "USMCA-eligible product (S/S+)"
capture label var s232_usmca_eligible "232 USMCA-eligible (auto/MHD)"

order revision hs10 cty_code total_rate
sort revision hs10 cty_code
isid revision hs10 cty_code
compress
save "$working/tracker_snapshots.dta", replace
di as text "       `=_N' snapshot obs (all revisions)"


* --- B5. 2024 import weights ---

di as text "  [B5] 2024 import weights..."

import delimited using "$raw/import_weights_2024.csv", clear stringcols(1 2)

** Destring and compute weight shares
destring imports, replace force
egen double total_imports = total(imports)
gen double w_2024 = imports / total_imports

** Set up labels
label var hs10          "HTS10 product code"
label var cty_code      "Census country code"
label var imports       "2024 imports (USD)"
label var total_imports "Total 2024 imports (USD)"
label var w_2024        "2024 import weight share"

order hs10 cty_code imports total_imports w_2024
sort hs10 cty_code
isid hs10 cty_code
compress
save "$working/weights_2024.dta", replace
di as text "       `=_N' product-country pairs"


* --- B6. Counterfactual rates (USMCA at monthly shares) ---
*
* Day-weighted monthly statutory rate at HS10 x country x month,
* produced by R pull section 3e. Applies the month's actual product-level
* USMCA utilization share to pre-USMCA statutory components. This is the
* best estimate of the statutory rate embedding actual USMCA behavior.

di as text "  [B6] Counterfactual rates (USMCA monthly)..."

import delimited using "$raw/counterfactual_usmca_monthly.csv", ///
    clear stringcols(1 2 3)
capture rename hts10 hs10

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

rename total_rate rate_usmca_monthly

keep hs10 cty_code ym rate_usmca_monthly
sort hs10 cty_code ym
isid hs10 cty_code ym
compress
save "$working/cf_usmca_monthly.dta", replace
di as text "       `=_N' HS10 x country x month rows"


* ======================================================================
* C. TREASURY REVENUE
* ======================================================================

di as text "  [C] Treasury revenue..."

import delimited using "$raw/tariff_revenue.csv", clear

** Destring variables
destring imports_value effective_rate, replace force

** Generate date information
gen daily_date = date(date, "YMD")
format daily_date %td
gen int ym = mofd(daily_date)
format ym %tm
drop date

** Compute actual ETR as ratio
gen double actual_rate = effective_rate / 100

** Set up labels
label var daily_date     "Date (first of month)"
label var ym             "Month (Stata date)"
label var customs_duties "Customs duties ($M, SAAR)"
label var imports_value  "Goods imports value ($M, SAAR)"
label var effective_rate "Actual ETR (%)"
label var actual_rate    "Actual ETR (ratio)"

order ym daily_date customs_duties imports_value effective_rate actual_rate
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

tempfile month_rev_map
build_month_rev_map, saving(`month_rev_map')
list, clean noobs

* --- D2. Merge Census with snapshot rates ---

di as text "      Merging Census x snapshots..."

use "$working/census_hs10_clean.dta", clear
keep if ym >= $start_ym & ym <= $end_ym

local n_start = _N
di as text "      Census obs in analysis period: `n_start'"

** Map each month to its active HTS revision
merge m:1 ym using `month_rev_map', keep(match master) gen(_merge_rev)
qui count if _merge_rev == 1
if r(N) > 0 {
    di as error "ERROR: `=r(N)' Census obs did not map to any revision"
    error 459
}
drop _merge_rev
assert _N > 0

** Merge tracker statutory rates on (hs10, country, revision)
merge m:1 hs10 cty_code revision using "$working/tracker_snapshots.dta", ///
    keep(match master) gen(_merge_snap)

** Report match rates; unmatched products get zero statutory rate
qui count if _merge_snap == 1
local n_unmatched = r(N)
qui count if _merge_snap == 3
local n_matched = r(N)
gen byte has_snap_rate = (_merge_snap == 3)
label var has_snap_rate "Product matched to tracker snapshot"
replace total_rate = 0 if missing(total_rate)
drop _merge_snap
local match_rate = 100 * `n_matched' / _N
di as text "      Snapshot matched: `n_matched', unmatched: `n_unmatched'"
di as text "      Match rate: " string(`match_rate', "%4.1f") "%"
if `match_rate' < 90 {
    di as error "WARNING: snapshot match rate below 90% — investigate"
}


* ======================================================================
* E. COMPUTE TRADE WEIGHTS
* ======================================================================

di as text "      Computing trade weights..."

** Monthly weights (Census trade values)
bysort ym: egen double total_imports_monthly = total(con_val_mo)
gen double w_monthly = con_val_mo / total_imports_monthly

** 2024 annual weights (from tracker import data)
merge m:1 hs10 cty_code using "$working/weights_2024.dta", ///
    keep(match master) keepusing(imports w_2024) gen(_merge_wt)
qui count if _merge_wt == 3
local n_wt_match = r(N)
gen byte has_2024_wt = (_merge_wt == 3)
label var has_2024_wt "Product has 2024 import weight"
drop _merge_wt
di as text "      2024 weight match: `n_wt_match' of " _N " obs"
replace imports = 0 if missing(imports)
replace w_2024  = 0 if missing(w_2024)

** Merge counterfactual statutory rate with monthly USMCA shares
merge 1:1 hs10 cty_code ym using "$working/cf_usmca_monthly.dta", ///
    keep(match master) gen(_merge_cfm)
qui count if _merge_cfm == 3
local n_cfm_match = r(N)
qui count if _merge_cfm == 1
local n_cfm_miss  = r(N)
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)
drop _merge_cfm
local cfm_pct = 100 * `n_cfm_match' / _N
di as text "      USMCA-monthly rate matched: `n_cfm_match' / " _N ///
    " (" string(`cfm_pct', "%4.1f") "%)"

** Implied tariff revenue (under alternative statutory rate definitions)
gen double tariff_revenue_statutory = total_rate * con_val_mo
gen double tariff_revenue_2024      = total_rate * imports
gen double tariff_revenue_usmca_mo  = rate_usmca_monthly * con_val_mo

** Ensure HS2 and partner group exist
capture confirm variable hs2
if _rc != 0 {
    gen str2 hs2 = substr(hs10, 1, 2)
}
capture confirm variable partner_group
if _rc != 0 {
    assign_partner_group cty_code
}

** Set up labels
label var w_monthly                 "Monthly import weight share"
label var total_imports_monthly     "Total monthly imports (USD)"
label var imports                   "2024 imports (USD)"
label var w_2024                    "2024 annual weight share"
label var tariff_revenue_statutory  "Implied statutory revenue (monthly wts)"
label var tariff_revenue_2024       "Implied statutory revenue (2024 wts)"
label var rate_usmca_monthly        "Statutory rate w/ monthly USMCA shares"
label var tariff_revenue_usmca_mo   "Implied revenue (monthly-USMCA rate)"

order ym year month hs2 hs10 cty_code partner_group ///
      con_val_mo cal_dut_mo census_etr ///
      total_rate rate_usmca_monthly ///
      tariff_revenue_statutory tariff_revenue_2024 tariff_revenue_usmca_mo ///
      w_monthly w_2024 imports revision

sort ym hs10 cty_code
compress
save "$working/merged_analysis.dta", replace

di as text _n "  Master analytical dataset: `=_N' observations"
di as text "  01_etr_clean complete." _n
