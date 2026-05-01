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
*   B. Tracker data (daily ETRs, snapshot rates, revision dates, weights,
*      and four counterfactual rate panels: cf_usmca_monthly [explainer],
*      cf_usmca2024 [S0], cf_h2avg [S1/S2], cf_pref_delta [S3 input])
*   C. Treasury revenue (actual ETR)
*   D. Merge: Census x tracker snapshots at HS10 x country x month
*   E. Compute trade weights + merge rate panels onto master
*   F. Integrity checks (key uniqueness, non-negative rates, S3 <= S2)
*
* Input (all from $raw, produced by R/00_pull_raw_data.R):
*   imdb_hs10_country_monthly.csv
*   daily_overall.csv, daily_by_country.csv
*   revision_dates.csv
*   snapshot_rates/snapshot_*.csv
*   import_weights_2024.csv
*   counterfactual_usmca_monthly.csv
*   counterfactual_usmca2024.csv
*   counterfactual_h2avg.csv
*   counterfactual_other_pref_delta_monthly.csv
*   tariff_revenue.csv
*
* Repo crosswalks:
*   $code/utils/product_groups.csv  (HS2 -> 9-group product classification)
*
* Output (all to $working unless noted):
*   census_hs10_clean.dta
*   tracker_daily.dta
*   tracker_daily_by_country.dta
*   cty_lookup.dta               (cty_code -> country_name; consumed by 05a/05b)
*   revision_dates.dta
*   tracker_snapshots.dta
*   weights_2024.dta
*   cf_usmca_monthly.dta, cf_usmca2024.dta, cf_h2avg.dta, cf_pref_delta.dta
*   revenue_monthly.dta
*   merged_analysis.dta          <-- master analytical dataset
*   $logs/merged_analysis_codebook.log  (data dictionary)
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
* 03_etr_analysis.do) collapse this dataset rather than importing from
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

** Run assign_partner_group on the Census country code column
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

** B2b. cty_code -> country_name lookup (consumed by 05a/05b diagnostics).
** Built once here so the diagnostic scripts don't have to re-derive it from
** tracker_daily_by_country.dta themselves.
preserve
    keep cty_code country_name
    duplicates drop
    bysort cty_code: keep if _n == 1   // belt-and-suspenders for unique cty_code
    label var cty_code     "Census country code"
    label var country_name "Country name"
    sort cty_code
    gisid cty_code
    compress
    save "$working/cty_lookup.dta", replace
    di as text "       cty_lookup: `=_N' unique countries"
restore


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

        ** Per-revision uniqueness check on small (~5M row) dataset.
        ** Catches duplicate (hs10, cty_code) keys early, before append. With
        ** different `rev' on every iteration, global (revision, hs10, cty_code)
        ** uniqueness is then guaranteed by construction -- no global gisid needed.
        gisid hs10 cty_code

        ** Row-count sanity: a healthy snapshot has millions of rows. A truncated
        ** or malformed CSV would silently shrink the appended panel; flag here
        ** so the failure isn't deferred to downstream merges.
        qui count
        if r(N) < 1000000 {
            di as error "WARNING: snapshot `rev' has only `=r(N)' rows -- expected millions"
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
* Global (revision, hs10, cty_code) uniqueness is guaranteed by construction:
* per-revision gisid above + unique `rev' per iteration. Skip the global check
* on the 200M+ row appended dataset (was the main step-1 bottleneck pre-gtools).
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
gisid hs10 cty_code            // gtools (faster than isid)
compress
save "$working/weights_2024.dta", replace
di as text "       `=_N' product-country pairs"


* --- B6. Counterfactual rates (USMCA at monthly shares) ---
*
* Day-weighted monthly statutory rate at HS10 x country x month,
* produced by R pull section 3e. Applies the month's actual product-level
* USMCA utilization share to pre-USMCA statutory components. This is the
* best estimate of the statutory rate embedding actual USMCA behavior.
* Used directly for tier S2.

di as text "  [B6] Counterfactual rates (USMCA monthly, S2 panel)..."

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
gisid hs10 cty_code ym         // gtools (faster than isid)
compress
save "$working/cf_usmca_monthly.dta", replace
di as text "       `=_N' HS10 x country x month rows"


* --- B7. Counterfactual rates (USMCA frozen at 2024 baseline) ---
*
* Day-weighted monthly statutory rate at HS10 x country x month with USMCA
* held at 2024 product-level utilization shares. Used for tiers S0
* (× 2024 weights) and S1 (× monthly weights).

di as text "  [B7] Counterfactual rates (USMCA 2024 baseline, S0/S1 panel)..."

import delimited using "$raw/counterfactual_usmca2024.csv", ///
    clear stringcols(1 2 3)
capture rename hts10 hs10

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

rename total_rate rate_2024

keep hs10 cty_code ym rate_2024
sort hs10 cty_code ym
gisid hs10 cty_code ym
compress
save "$working/cf_usmca2024.dta", replace
di as text "       `=_N' HS10 x country x month rows"


* --- B7b. Counterfactual rates (Post-July 2025 USMCA baseline, S1/S2 panel) ---
*
* Day-weighted monthly statutory rate at HS10 x country x month with USMCA
* held at the tracker's post-July 2025 production baseline shares (~89% CA/MX).
* Same day-weighting machinery as B6 (cf_usmca_monthly) and B7 (cf_usmca2024)
* so all three panels are apples-to-apples comparable across revisions.
* Replaces the old `rate_h2avg = total_rate` alias, which used per-revision
* tracker_snapshots and missed mid-month policy changes (e.g. Liberation Day
* on Apr 2, 2025 was invisible at the April-1 revision lookup).

di as text "  [B7b] Counterfactual rates (Post-July 2025 USMCA baseline, S1/S2 panel)..."

import delimited using "$raw/counterfactual_h2avg.csv", ///
    clear stringcols(1 2 3)
capture rename hts10 hs10

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

rename total_rate rate_h2avg

keep hs10 cty_code ym rate_h2avg
sort hs10 cty_code ym
gisid hs10 cty_code ym
compress
save "$working/cf_h2avg.dta", replace
di as text "       `=_N' HS10 x country x month rows"


* --- B8. Non-USMCA preference delta (S2 → S3) ---
*
* Sparse delta panel from R pull section 3g: per (HS10 × cty × ym) cell,
* the rate reduction implied by non-USMCA preference shares (Annex II /
* ITA / Ch98 / KORUS / GSP / other_fta) applied to pre-preference component
* rates. Subtracted from rate_usmca_monthly downstream to build rate_all_pref.

di as text "  [B8] Non-USMCA preference delta (S3 panel)..."

import delimited using "$raw/counterfactual_other_pref_delta_monthly.csv", ///
    clear stringcols(1 2 3)
capture rename hts10 hs10

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month

keep hs10 cty_code ym delta_base delta_recip
sort hs10 cty_code ym
gisid hs10 cty_code ym
compress
save "$working/cf_pref_delta.dta", replace
di as text "       `=_N' delta rows"


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

** Sanity-check effective_rate is in percent units (not already a ratio).
** Catches upstream unit-confusion bugs before they propagate to downstream tiers.
assert effective_rate >= 0 & effective_rate < 100 if !missing(effective_rate)

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

** Defensive check: build_month_rev_map should have added `revision`. If the
** crosswalk was empty or malformed, `revision` is missing and the next merge
** fails with a confusing "variable revision not found" error. Catch it here.
capture confirm variable revision
if _rc != 0 {
    di as error "FATAL: 'revision' missing on master after month_rev_map merge."
    di as error "       Likely build_month_rev_map produced an empty or"
    di as error "       malformed crosswalk (check revision_dates.dta and the"
    di as error "       \$start_ym/\$end_ym window globals)."
    error 111
}
qui count if missing(revision)
if r(N) == _N {
    di as error "FATAL: revision is all-missing after month_rev_map merge."
    error 459
}

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

** Merge S2 rate panel: USMCA at monthly shares
merge 1:1 hs10 cty_code ym using "$working/cf_usmca_monthly.dta", ///
    keep(match master) gen(_merge_cfm)
qui count if _merge_cfm == 3
local n_cfm_match = r(N)
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)
drop _merge_cfm
local cfm_pct = 100 * `n_cfm_match' / _N
di as text "      USMCA-monthly rate matched: `n_cfm_match' / " _N ///
    " (" string(`cfm_pct', "%4.1f") "%)"

** Merge S0 rate panel: USMCA frozen at 2024 baseline
merge 1:1 hs10 cty_code ym using "$working/cf_usmca2024.dta", ///
    keep(match master) gen(_merge_cf24)
qui count if _merge_cf24 == 3
local n_cf24_match = r(N)
replace rate_2024 = 0 if missing(rate_2024)
drop _merge_cf24
local cf24_pct = 100 * `n_cf24_match' / _N
di as text "      USMCA-2024 rate matched: `n_cf24_match' / " _N ///
    " (" string(`cf24_pct', "%4.1f") "%)"
** cf_usmca2024 is built from the same R pipeline universe as cf_usmca_monthly,
** so its match rate should approach 100%. A drop signals an upstream regression.
if `cf24_pct' < 95 {
    di as error "WARNING: cf_usmca2024 match rate below 95% -- investigate"
    di as error "         (expected to match cf_usmca_monthly universe)"
}

** Merge S1/S2 rate panel: Post-July 2025 USMCA baseline (rate_h2avg)
merge 1:1 hs10 cty_code ym using "$working/cf_h2avg.dta", ///
    keep(match master) gen(_merge_h2avg)
qui count if _merge_h2avg == 3
local n_h2avg_match = r(N)
replace rate_h2avg = 0 if missing(rate_h2avg)
drop _merge_h2avg
local h2avg_pct = 100 * `n_h2avg_match' / _N
di as text "      USMCA-h2avg rate matched: `n_h2avg_match' / " _N ///
    " (" string(`h2avg_pct', "%4.1f") "%)"
if `h2avg_pct' < 95 {
    di as error "WARNING: cf_h2avg match rate below 95% -- investigate"
    di as error "         (expected to match cf_usmca_monthly universe)"
}

** Merge S3 preference delta and build rate_all_pref.
** cf_pref_delta is sparse by design: only cells with positive non-USMCA
** preference share appear. A low match rate here is expected -- no floor check.
**
** rate_all_pref subtracts the non-USMCA preference delta from rate_h2avg
** (the day-weighted h2avg-USMCA panel), so the framework's S2 -> S3 step
** holds USMCA at the stable post-July 2025 baseline; monthly USMCA noise is
** absorbed in S0 -> S1 instead.
merge 1:1 hs10 cty_code ym using "$working/cf_pref_delta.dta", ///
    keep(match master) gen(_merge_delta)
replace delta_base  = 0 if missing(delta_base)
replace delta_recip = 0 if missing(delta_recip)
gen double rate_all_pref = max(0, rate_h2avg - delta_base - delta_recip)
drop delta_base delta_recip _merge_delta

** rate_h2avg is now merged in as a day-weighted panel from cf_h2avg.dta
** (B7b above). The earlier `gen rate_h2avg = total_rate` alias is gone:
** total_rate is per-revision-snapshot and missed mid-month policy changes
** (e.g. Liberation Day on Apr 2, 2025 was invisible at the April-1 lookup).
** Both rate_h2avg and total_rate now exist on the dataset; rate_h2avg is
** the framework input, total_rate is retained as the raw tracker per-
** revision rate for diagnostics (06).

** Implied tariff revenue (under alternative statutory rate definitions)
gen double tariff_revenue_statutory = total_rate * con_val_mo
gen double tariff_revenue_2024      = total_rate * imports
gen double tariff_revenue_usmca_mo  = rate_usmca_monthly * con_val_mo

** Defensive: hs2 and partner_group are set in Section A (lines 69, 75) and
** survive the merges, so the `capture confirm` checks should never fire.
** Kept as belt-and-suspenders in case Section A is ever refactored to drop
** these columns before the merge sequence; can be removed if confirmed safe.
capture confirm variable hs2
if _rc != 0 {
    gen str2 hs2 = substr(hs10, 1, 2)
}
capture confirm variable partner_group
if _rc != 0 {
    assign_partner_group cty_code
}

** Merge the HS2 -> 9-product-group crosswalk (code/utils/product_groups.csv).
** Used by 03 Section B (S0->S1 product-side Shapley) and Section D7
** (product-group gap figures). Crosswalk covers HS2 01-99; any HS2 in the
** data that's missing from the crosswalk gets caught by the assert below.
preserve
    import delimited using "${code}utils/product_groups.csv", ///
        clear stringcols(1) varnames(1)
    sort hs2
    gisid hs2
    tempfile pg_xwalk
    save `pg_xwalk'
restore
merge m:1 hs2 using `pg_xwalk', keep(match master) gen(_merge_pg)
qui count if _merge_pg == 1
if r(N) > 0 {
    di as error "ERROR: `=r(N)' rows have hs2 not in product_groups.csv"
    di as error "       Inspect with: tab hs2 if _merge_pg == 1"
    error 459
}
drop _merge_pg
label var product_group "9-group HS2 product classification"

** Set up labels
label var w_monthly                 "Monthly import weight share"
label var total_imports_monthly     "Total monthly imports (USD)"
label var imports                   "2024 imports (USD)"
label var w_2024                    "2024 annual weight share"
label var tariff_revenue_statutory  "Implied statutory revenue (monthly wts)"
label var tariff_revenue_2024       "Implied statutory revenue (2024 wts)"
label var rate_usmca_monthly        "Empirical monthly USMCA rate (explainer; not a tier input)"
label var rate_2024                 "Statutory rate, USMCA at 2024 baseline shares (S0 panel)"
label var rate_h2avg                "Statutory rate, Post-July 2025 USMCA average (S1/S2 panel; day-weighted)"
label var rate_all_pref             "Statutory rate, h2avg USMCA + non-USMCA prefs (S3 panel)"
label var tariff_revenue_usmca_mo   "Implied revenue (monthly-USMCA rate)"

order ym year month hs2 product_group hs10 cty_code partner_group ///
      con_val_mo cal_dut_mo census_etr ///
      total_rate rate_h2avg rate_2024 rate_usmca_monthly rate_all_pref ///
      tariff_revenue_statutory tariff_revenue_2024 tariff_revenue_usmca_mo ///
      w_monthly w_2024 imports revision

sort ym hs10 cty_code
compress


* ======================================================================
* F. INTEGRITY CHECKS ON merged_analysis.dta
* ======================================================================
*
* Final invariants on the master analytical dataset. Each downstream script
* consumes merged_analysis.dta and assumes these hold; failing fast here is
* cheaper than chasing weird tier values later.

di as text _n "  [F] Integrity checks..."

** Key uniqueness (the 1:1 merges in E claim this; verify it).
gisid hs10 cty_code ym

** HS10 format: every code should be exactly 10 numeric characters. A
** truncation or padding bug upstream would silently corrupt the merge keys
** AND the substr(hs10,1,2) HS2 derivation. Flag (don't fail) so we still
** save the dataset for inspection if anything looks off.
qui count if length(hs10) != 10 | !regexm(hs10, "^[0-9]{10}$")
if r(N) > 0 {
    di as error "WARNING: `=r(N)' rows have malformed hs10 (not 10 digits)"
    di as error "         Inspect with: list hs10 in 1/20 if length(hs10) != 10"
}

** Non-negative invariants on rates and value columns.
assert total_rate          >= 0 if !missing(total_rate)
assert rate_h2avg          >= 0 if !missing(rate_h2avg)
assert rate_2024           >= 0 if !missing(rate_2024)
assert rate_usmca_monthly  >= 0 if !missing(rate_usmca_monthly)
assert rate_all_pref       >= 0 if !missing(rate_all_pref)
assert con_val_mo          >= 0 if !missing(con_val_mo)
assert cal_dut_mo          >= 0 if !missing(cal_dut_mo)
assert imports             >= 0 if !missing(imports)

** S3 <= S2 by construction: rate_all_pref = max(0, rate_h2avg - delta), and
** delta is non-negative by R section 3g math. A violation would mean the R
** pipeline emitted negative deltas; the max(0,...) guards the floor but
** cannot catch upper-bound violations.
gen double _s3_excess = rate_all_pref - rate_h2avg
qui sum _s3_excess
if r(max) > 1e-9 {
    qui count if _s3_excess > 1e-9
    di as error "ERROR: rate_all_pref > rate_h2avg in `=r(N)' rows"
    di as error "       Max excess: `=string(r(max), "%9.6f")' -- check delta panel"
    error 459
}
drop _s3_excess

di as text "      All integrity checks passed."

save "$working/merged_analysis.dta", replace

** Codebook for downstream consumers (skill recommendation: data dictionary
** alongside the cleaned dataset).
log using "$logs/merged_analysis_codebook.log", replace text name(_codebook)
codebook, compact
log close _codebook

di as text _n "  Master analytical dataset: `=_N' observations"
di as text "  01_etr_clean complete." _n
