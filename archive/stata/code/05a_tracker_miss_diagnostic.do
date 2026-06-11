* ==============================================================================
* 05a_tracker_miss_diagnostic.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Identify what countries / products are being missed by the
*          tariff-rate-tracker -- cells where the tracker's monthly-USMCA
*          statutory rate is zero but Census reports positive duties
*          collected. Produces five diagnostic CSVs intended for delivery
*          to the tracker maintainer to help localize bugs and gaps.
*
* Trackermiss criterion (matches Section D5 of 03_etr_analysis.do):
*     rate_usmca_monthly == 0  &  cal_dut_mo > 0
*
* Likely root causes (signature in parentheses):
*   - Authority not parsed         (rate_prov is a Chapter 99 code unknown to tracker)
*   - Specific-duty AVE failure    (rate_prov is base HTS line; HS10 has specific duty)
*   - AD/CVD                       (rate_prov is base HTS line; not in HTS at all)
*   - Country override miss        (recognized Chapter 99 line; carve-out absent)
*   - Importer misclassification   (rate_prov mismatches HS10)
*   - Stacking/floor logic bug     (recognized line; tracker silently zeros out)
*
* Input:
*   $working/merged_analysis.dta   (HS10 x cty x ym, rate_usmca_monthly, cal_dut_mo)
*   $raw/imdb_detail.csv           (HS10 x cty x district x rate_prov x ym)
*
* Output (all in $tables/):
*   tracker_miss_top_cells.csv      Top 200 (HS10, cty, ym) cells by $ duty,
*                                   enriched with top-3 rate_prov per cell.
*                                   The click-and-fix worst-offender list.
*   tracker_miss_by_rate_prov.csv   Global rate_prov ranking by $ duty.
*                                   The single most actionable file -- ranks
*                                   missing authorities/HTS lines by total $.
*   tracker_miss_by_hs2.csv         HS2 chapter ranking, summed over months.
*   tracker_miss_by_country.csv     Partner-group ranking, summed over months.
*   tracker_miss_by_revision.csv    Revision in which each (HS10, cty) FIRST
*                                   went trackermiss -- localizes parsing
*                                   regressions to specific tracker revisions.
* ==============================================================================

di as text _n "=========================================="
di as text "  05a_tracker_miss_diagnostic"
di as text "==========================================" _n


* ======================================================================
* A. BUILD TRACKERMISS PANEL FROM merged_analysis
* ======================================================================

di as text "  [A] Loading merged_analysis and selecting trackermiss cells..."

use "$working/merged_analysis.dta", clear
keep hs10 cty_code partner_group ym imports con_val_mo cal_dut_mo ///
     rate_usmca_monthly total_rate revision

* Trackermiss = tracker rate exactly zero AND Census shows positive duties
gen byte trackermiss = (rate_usmca_monthly == 0 & cal_dut_mo > 0)

qui count
local n_total = r(N)
qui count if trackermiss
local n_miss = r(N)
local pct_miss = 100 * `n_miss' / `n_total'
di as text "       `n_miss' of `n_total' rows are trackermiss " ///
   "(" string(`pct_miss', "%4.2f") "%)"

keep if trackermiss == 1

* Implied Census-derived rate (informational; can be high if duty class != ad val)
safe_divide cal_dut_mo con_val_mo implied_rate
replace implied_rate = implied_rate * 100
label var implied_rate "Census-implied ETR on cell (%)"

tempfile miss_panel
save `miss_panel'

di as text "       trackermiss cells:                  `n_miss'"
qui sum cal_dut_mo
di as text "       trackermiss duties total:           " ///
    string(r(sum)/1e9, "%9.2f") "B"
qui sum con_val_mo
di as text "       trackermiss imports value total:    " ///
    string(r(sum)/1e9, "%9.2f") "B"


* ======================================================================
* B. AGGREGATE IMDB DETAIL TO (hs10, cty, ym, rate_prov)
* ======================================================================

di as text _n "  [B] Aggregating IMDB detail by rate_prov..."

* Note: this script intentionally does NOT call classify_pref_channel.
* The whole point is to surface raw rate_prov codes that the tracker missed,
* including ones the classifier doesn't know about. Aggregating by raw
* rate_prov is the operator-handoff signal we want.

import delimited using "$raw/imdb_detail.csv", clear stringcols(1 2 3 4 5 6)
destring con_val_mo dut_val_mo cal_dut_mo, replace force

** Warn on coercion failures: `force` silently converts non-numeric to missing.
qui count if missing(con_val_mo)
if r(N) > 0 {
    di as error "WARNING: `=r(N)' rows have missing con_val_mo after destring force"
}

gen year  = real(substr(year_month, 1, 4))
gen month = real(substr(year_month, 6, 7))
gen int ym = ym(year, month)
format ym %tm
drop year month year_month
keep if ym >= $start_ym & ym <= $end_ym

* Collapse over districts (rate_prov is the diagnostic axis we care about)
collapse (sum) cal_dut_mo con_val_mo, by(hs10 cty_code ym rate_prov)

* Inner-join to trackermiss panel: keeps only rate_prov rows for trackermiss cells
merge m:1 hs10 cty_code ym using `miss_panel', keep(match) ///
    keepusing(rate_usmca_monthly trackermiss) nogenerate

tempfile rp_detail
save `rp_detail'

qui count
di as text "       `=_N' rate_prov rows in trackermiss cells"


* ======================================================================
* C. TOP-3 rate_prov PER CELL  (for cell-level enrichment)
* ======================================================================

di as text _n "  [C] Computing top-3 rate_prov per trackermiss cell..."

use `rp_detail', clear

* Cell total (across all rate_prov in the cell) for share computation
bysort hs10 cty_code ym: egen double cell_total = total(cal_dut_mo)

* Rank by $ duty within (hs10, cty, ym), descending
gsort hs10 cty_code ym -cal_dut_mo
by hs10 cty_code ym: gen rank = _n
keep if rank <= 3

gen double rp_share = 100 * cal_dut_mo / cell_total

keep hs10 cty_code ym rank rate_prov rp_share
reshape wide rate_prov rp_share, i(hs10 cty_code ym) j(rank)

rename rate_prov1 rp_top1
rename rate_prov2 rp_top2
rename rate_prov3 rp_top3
rename rp_share1  rp_top1_pct
rename rp_share2  rp_top2_pct
rename rp_share3  rp_top3_pct

* Cells with fewer than 3 rate_prov values get missing on rp_top2/3 -- expected
foreach v in rp_top1 rp_top2 rp_top3 {
    capture confirm string variable `v'
    if _rc != 0 gen str10 `v' = ""
    replace `v' = "" if missing(`v')
}

tempfile rp_wide
save `rp_wide'


* ======================================================================
* D. TOP CELLS WITH rate_prov ENRICHMENT
* ======================================================================

di as text _n "  [D] Building top-cells output..."

use `miss_panel', clear
merge 1:1 hs10 cty_code ym using `rp_wide', keep(match master) nogenerate

gsort -cal_dut_mo
gen long rank_global = _n

* Keep the top-N cells or all above the $-floor (whichever is more inclusive).
* Thresholds in globals.do: $diagnostic_top_n_cells, $diagnostic_cell_floor.
keep if rank_global <= $diagnostic_top_n_cells | cal_dut_mo > $diagnostic_cell_floor

format con_val_mo cal_dut_mo %20.0fc
format implied_rate rp_top1_pct rp_top2_pct rp_top3_pct %5.2f

label var rank_global    "Rank by trackermiss $"
label var hs10           "HS10 product code"
label var cty_code       "Census country code"
label var partner_group  "Partner group"
label var ym             "Month"
label var con_val_mo     "Imports value (USD)"
label var cal_dut_mo     "Census duty (USD)"
label var implied_rate   "Census-implied ETR (%)"
label var revision       "Active HTS revision"
label var rp_top1        "Top rate_prov by \$ duty"
label var rp_top2        "2nd rate_prov"
label var rp_top3        "3rd rate_prov"
label var rp_top1_pct    "Top rate_prov \$ share (%)"
label var rp_top2_pct    "2nd rate_prov \$ share (%)"
label var rp_top3_pct    "3rd rate_prov \$ share (%)"

order rank_global hs10 cty_code partner_group ym revision ///
      con_val_mo cal_dut_mo implied_rate ///
      rp_top1 rp_top1_pct rp_top2 rp_top2_pct rp_top3 rp_top3_pct

di as text _n "  === Top ${diagnostic_top_n_print} trackermiss cells by \$ duty ==="
list rank_global hs10 cty_code ym cal_dut_mo implied_rate rp_top1 ///
    if _n <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_miss_top_cells.csv", replace
di as text "       wrote `=_N' rows -> tracker_miss_top_cells.csv"


* ======================================================================
* E. BY rate_prov  (the most actionable file)
* ======================================================================

di as text _n "  [E] Aggregating by rate_prov..."

use `rp_detail', clear

* Empty rate_prov gets a placeholder so it's distinguishable from real codes
replace rate_prov = "<empty>" if missing(rate_prov) | trim(rate_prov) == ""

collapse (sum) cal_dut_mo con_val_mo (count) n_cell_rows = cal_dut_mo, ///
    by(rate_prov)
egen double total_dut = total(cal_dut_mo)
gen double share_pct = 100 * cal_dut_mo / total_dut
drop total_dut
gsort -cal_dut_mo

format cal_dut_mo con_val_mo %20.0fc
format share_pct %6.2f
format n_cell_rows %9.0fc

label var rate_prov    "HTS rate provision (importer-declared)"
label var cal_dut_mo   "Trackermiss duty in this rate_prov (USD)"
label var con_val_mo   "Trackermiss imports in this rate_prov (USD)"
label var n_cell_rows  "(hs10 x cty x ym) cell-rows in this rate_prov"
label var share_pct    "Share of total trackermiss \$ (%)"

di as text _n "  === Top ${diagnostic_top_n_print} rate_prov by trackermiss \$ ==="
list rate_prov n_cell_rows cal_dut_mo share_pct if _n <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_miss_by_rate_prov.csv", replace
di as text "       wrote `=_N' rate_prov rows -> tracker_miss_by_rate_prov.csv"


* ======================================================================
* F. BY HS2 CHAPTER
* ======================================================================

di as text _n "  [F] Aggregating by HS2 chapter..."

use `miss_panel', clear
gen str2 hs2 = substr(hs10, 1, 2)
destring hs2, gen(hs2_num) force

collapse (sum) cal_dut_mo con_val_mo (count) n_cells = cal_dut_mo, by(hs2 hs2_num)
egen double total_dut = total(cal_dut_mo)
gen double share_pct = 100 * cal_dut_mo / total_dut
drop total_dut
gsort -cal_dut_mo

label values hs2_num hs2_lbl
format cal_dut_mo con_val_mo %20.0fc
format share_pct %6.2f
format n_cells %9.0fc

label var hs2          "HS2 chapter"
label var hs2_num      "HS2 chapter (numeric, labeled)"
label var n_cells      "(hs10 x cty x ym) trackermiss cells in chapter"
label var cal_dut_mo   "Trackermiss duty (USD)"
label var con_val_mo   "Trackermiss imports value (USD)"
label var share_pct    "Share of total trackermiss \$ (%)"

di as text _n "  === Top ${diagnostic_top_n_print} HS2 chapters by trackermiss \$ ==="
list hs2_num n_cells cal_dut_mo share_pct if _n <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_miss_by_hs2.csv", replace
di as text "       wrote `=_N' chapters -> tracker_miss_by_hs2.csv"


* ======================================================================
* G. BY PARTNER GROUP
* ======================================================================

di as text _n "  [G] Aggregating by partner group..."

use `miss_panel', clear
collapse (sum) cal_dut_mo con_val_mo (count) n_cells = cal_dut_mo ///
              (sum) imports = imports ///
        , by(partner_group)
egen double total_dut = total(cal_dut_mo)
gen double share_pct = 100 * cal_dut_mo / total_dut
drop total_dut
gsort -cal_dut_mo

format cal_dut_mo con_val_mo imports %20.0fc
format share_pct %6.2f
format n_cells %9.0fc

label var partner_group "Partner group"
label var n_cells       "(hs10 x cty x ym) trackermiss cells in partner group"
label var cal_dut_mo    "Trackermiss duty (USD)"
label var con_val_mo    "Trackermiss imports value (USD)"
label var imports       "2024 imports (USD) -- universe size proxy"
label var share_pct     "Share of total trackermiss \$ (%)"

di as text _n "  === Trackermiss by partner group ==="
list partner_group n_cells cal_dut_mo share_pct, clean noobs

export delimited using "$tables/tracker_miss_by_country.csv", replace
di as text "       wrote `=_N' partner groups -> tracker_miss_by_country.csv"


* ======================================================================
* G2. PER-COUNTRY DETAIL  (drills inside ROW)
* ======================================================================
*
* Partner-group aggregation in G hides individual countries inside the ROW
* and EU buckets. To track the impact of country-specific fixes (e.g. EO
* 14323 for Brazil at 9903.01.77, EO 9903.01.84 for India, Section 201 on
* products from KR/Vietnam), break down by Census cty_code with country
* names from the tracker's daily-by-country output.
*
* Output: top 50 countries globally by trackermiss $, with partner_group
* tag and country name. The Brazil/India rows in particular should drop
* sharply once the corresponding tracker fixes land.

di as text _n "  [G2] Per-country detail (top 50 countries globally)..."

use `miss_panel', clear
collapse (sum) cal_dut_mo con_val_mo (count) n_cells = cal_dut_mo, ///
    by(cty_code partner_group)

* cty_lookup.dta is built once in 01_etr_clean.do Section B2b.
merge m:1 cty_code using "$working/cty_lookup.dta", keep(match master) nogenerate

egen double total_dut = total(cal_dut_mo)
gen double share_pct = 100 * cal_dut_mo / total_dut
drop total_dut

gsort -cal_dut_mo
gen long rank_global = _n

* Keep the global top-N; this captures Brazil/India and the major ROW
* contributors while keeping the file small.
* Threshold: $diagnostic_top_n_countries in globals.do.
keep if rank_global <= $diagnostic_top_n_countries

format cal_dut_mo con_val_mo %20.0fc
format share_pct %6.2f
format n_cells %9.0fc

label var cty_code      "Census country code"
label var country_name  "Country name"
label var partner_group "Partner group"
label var n_cells       "Trackermiss cells"
label var cal_dut_mo    "Trackermiss duty (USD)"
label var con_val_mo    "Trackermiss imports (USD)"
label var share_pct     "Share of total trackermiss \$ (%)"
label var rank_global   "Rank by trackermiss \$"

order rank_global country_name cty_code partner_group n_cells ///
      cal_dut_mo con_val_mo share_pct

di as text _n "  === Top ${diagnostic_top_n_print} countries by trackermiss \$ ==="
list rank_global country_name partner_group n_cells cal_dut_mo share_pct ///
    if rank_global <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_miss_by_country_detail.csv", replace
di as text "       wrote `=_N' rows -> tracker_miss_by_country_detail.csv"


* ======================================================================
* H. FIRST-MISS REVISION  (regression localization)
* ======================================================================
*
* For each (HS10, cty), find the earliest month it became trackermiss and
* the active HTS revision at that month. Counting first-misses by revision
* reveals whether trackermiss spikes are tied to specific tracker revisions
* (i.e., parsing/stacking changes that introduced new gaps).

di as text _n "  [H] First-miss revision pattern..."

use `miss_panel', clear
sort hs10 cty_code ym
by hs10 cty_code: gen byte first_miss = (_n == 1)

preserve
    keep if first_miss == 1
    collapse (count) n_first_miss = first_miss ///
            (sum)   first_miss_dut = cal_dut_mo, ///
        by(revision)
    egen double total_first_dut = total(first_miss_dut)
    gen double share_pct = 100 * first_miss_dut / total_first_dut
    drop total_first_dut
    gsort -first_miss_dut

    format first_miss_dut %20.0fc
    format n_first_miss %9.0fc
    format share_pct %6.2f

    label var revision        "HTS revision"
    label var n_first_miss    "(hs10 x cty) cells first appearing in this revision"
    label var first_miss_dut  "First-month duty in cells first-missing here (USD)"
    label var share_pct       "Share of total first-miss \$ (%)"

    di as text _n "  === First-miss revisions ==="
    list revision n_first_miss first_miss_dut share_pct if _n <= $diagnostic_top_n_print, clean noobs

    export delimited using "$tables/tracker_miss_by_revision.csv", replace
    di as text "       wrote `=_N' revisions -> tracker_miss_by_revision.csv"
restore


* ======================================================================
* I. RUN SUMMARY
* ======================================================================

di as text _n "  === Outputs written to ${tables} ==="
foreach f in tracker_miss_top_cells.csv ///
             tracker_miss_by_rate_prov.csv ///
             tracker_miss_by_hs2.csv ///
             tracker_miss_by_country.csv ///
             tracker_miss_by_country_detail.csv ///
             tracker_miss_by_revision.csv {
    capture confirm file "${tables}`f'"
    if _rc == 0 {
        di as text "      OK    `f'"
    }
    else {
        di as error "      MISSING  `f'"
    }
}

di as text _n "  05a_tracker_miss_diagnostic complete." _n
