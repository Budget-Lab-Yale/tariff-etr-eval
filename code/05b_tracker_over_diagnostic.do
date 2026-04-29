* ==============================================================================
* 05b_tracker_over_diagnostic.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Identify cells where the tariff-rate-tracker OVER-states the
*          statutory rate -- tracker rate is positive but actual collected
*          duty is much lower (or zero). Mirrors 05a on the opposite error.
*
* Trackerover criterion (entry-level, after pref_channel classification):
*     rate_usmca_monthly > 0
*     AND  con_val_mo * rate_usmca_monthly  >  cal_dut_mo
*     -> over_dollars = statutory_duty - actual_duty > 0
*
* Channel partition (classifier from programs.do):
*   LEGIT (preference-claimed; expected gap, NOT a tracker bug)
*     usmca, korus, other_fta, gsp_agoa
*   BUG-LIKELY (tracker error candidates)
*     duty_free      -- tracker missed an HTS exemption (Ch98, ITA, Berman)
*     mfn_dutiable   -- tracker rate higher than actual MFN
*     ch99_dutiable  -- Chapter 99 line parsed wrong
*   NOISE
*     ftz_bonded     -- duties deferred, not a rate error
*     other          -- residual
*
* Ranking outputs (top_cells / by_rate_prov / by_hs2 / by_country /
* by_country_detail / by_revision) filter to BUG-LIKELY only. by_channel
* shows the full split (legit + bug + noise) so the reader can sanity-check
* the partition.
*
* Input:
*   $working/merged_analysis.dta   (HS10 x cty x ym, rate_usmca_monthly)
*   $raw/imdb_detail.csv           (HS10 x cty x district x rate_prov x ym)
*   $working/revision_dates.dta    (via build_month_rev_map)
*   $working/tracker_daily_by_country.dta  (cty_code -> country_name lookup)
*
* Output (all in $tables/):
*   tracker_over_top_cells.csv         Top 200 BUG-LIKELY cells, with top-3
*                                      rate_prov per cell (channel-tagged).
*   tracker_over_by_rate_prov.csv      rate_prov ranking within BUG-LIKELY.
*   tracker_over_by_hs2.csv            HS2 chapter ranking, BUG-LIKELY only.
*   tracker_over_by_country.csv        Partner-group ranking, BUG-LIKELY.
*   tracker_over_by_country_detail.csv Top 50 countries, BUG-LIKELY.
*   tracker_over_by_channel.csv        Full pref_channel breakdown.
*   tracker_over_by_revision.csv       First-over revision (regression
*                                      localization), BUG-LIKELY only.
* ==============================================================================

di as text _n "=========================================="
di as text "  05b_tracker_over_diagnostic"
di as text "==========================================" _n


* ======================================================================
* A. LOAD IMDB DETAIL, CLASSIFY pref_channel, COLLAPSE TO ENTRY GRAIN
* ======================================================================

di as text "  [A] Loading IMDB detail and classifying pref_channel..."

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

* Classify BEFORE collapsing -- pref_channel depends on cty_subco
classify_pref_channel cty_subco rate_prov cty_code

* Collapse over districts (and over cty_subco within pref_channel)
collapse (sum) cal_dut_mo con_val_mo, by(hs10 cty_code ym rate_prov pref_channel)

assign_partner_group cty_code

tempfile entries
save `entries'

di as text "       `=_N' entry rows after district collapse"


* ======================================================================
* B. MERGE TRACKER RATE AND COMPUTE OVER-STATEMENT
* ======================================================================

di as text _n "  [B] Merging tracker rate, computing over_dollars..."

* Build month -> revision crosswalk (program in programs.do; clears in-memory)
tempfile month_rev_map
build_month_rev_map, saving(`month_rev_map')

* Pull rate_usmca_monthly from merged_analysis (it is cell-level, not entry-level).
* merged_analysis is keyed unique on (hs10, cty_code, ym) by 01 Section F's
* gisid check; assert here so any upstream regression surfaces loudly rather
* than getting silently masked by `duplicates drop ..., force`.
use "$working/merged_analysis.dta", clear
keep hs10 cty_code ym rate_usmca_monthly
gisid hs10 cty_code ym
tempfile rates
save `rates'

use `entries', clear
merge m:1 ym using `month_rev_map', keep(match master) nogenerate
merge m:1 hs10 cty_code ym using `rates', keep(match master) nogenerate
replace rate_usmca_monthly = 0 if missing(rate_usmca_monthly)

* Compute over-statement at entry granularity
gen double statutory_duty = con_val_mo * rate_usmca_monthly
gen double actual_duty    = cond(missing(cal_dut_mo), 0, cal_dut_mo)
gen double over_dollars   = max(0, statutory_duty - actual_duty)

* Diagnostic groups (channel lists in globals.do).
gen byte legit   = inlist(pref_channel, $over_legit_channels)
gen byte buglike = inlist(pref_channel, $over_buglike_channels)
gen byte noise   = inlist(pref_channel, $over_noise_channels)

label var statutory_duty "Implied statutory duty at tracker rate"
label var actual_duty    "Census actual duty"
label var over_dollars   "Tracker over-statement (USD)"

* Filter to over-stating entries with positive tracker rate
keep if rate_usmca_monthly > 0 & over_dollars > 0

tempfile over_entries
save `over_entries'

qui count
local n_over = r(N)
qui sum over_dollars
local total_over = r(sum)
di as text "       `n_over' over-stating entries, total over-\$" ///
    string(`total_over'/1e9, "%9.2f") "B"
qui sum over_dollars if buglike
di as text "       BUG-LIKELY:    \$" string(r(sum)/1e9, "%9.2f") "B"
qui sum over_dollars if legit
di as text "       LEGIT (pref):  \$" string(r(sum)/1e9, "%9.2f") "B"
qui sum over_dollars if noise
di as text "       NOISE:         \$" string(r(sum)/1e9, "%9.2f") "B"


* ======================================================================
* C. CHANNEL BREAKDOWN  (full split: legit + bug + noise)
* ======================================================================

di as text _n "  [C] Channel breakdown..."

use `over_entries', clear
collapse (sum) over_dollars actual_duty statutory_duty con_val_mo ///
         (count) n_entries = over_dollars, by(pref_channel)

egen double total_over = total(over_dollars)
gen double share_pct = 100 * over_dollars / total_over
drop total_over

gen str10 group = "noise"
replace group = "legit"   if inlist(pref_channel, $over_legit_channels)
replace group = "buglike" if inlist(pref_channel, $over_buglike_channels)

gsort group -over_dollars

format over_dollars actual_duty statutory_duty con_val_mo %20.0fc
format share_pct %6.2f
format n_entries %12.0fc

label var pref_channel    "Preference/rate channel"
label var group           "Diagnostic group"
label var n_entries       "Entries in channel"
label var over_dollars    "Tracker over-statement (USD)"
label var statutory_duty  "Implied tracker duty (USD)"
label var actual_duty     "Census actual duty (USD)"
label var con_val_mo      "Imports (USD)"
label var share_pct       "Share of total over-\$ (%)"

order group pref_channel n_entries over_dollars share_pct ///
      statutory_duty actual_duty con_val_mo

di as text _n "  === Over-statement by channel ==="
list group pref_channel n_entries over_dollars share_pct, clean noobs

export delimited using "$tables/tracker_over_by_channel.csv", replace
di as text "       wrote -> tracker_over_by_channel.csv"


* ======================================================================
* D. TOP CELLS  (BUG-LIKELY only, with top-3 rate_prov enrichment)
* ======================================================================

di as text _n "  [D] Top BUG-LIKELY cells with rate_prov enrichment..."

* Cell totals over BUG-LIKELY entries only
use `over_entries', clear
keep if buglike == 1
preserve
    collapse (sum) over_dollars con_val_mo cal_dut_mo statutory_duty, ///
        by(hs10 cty_code partner_group ym revision rate_usmca_monthly)
    tempfile cells
    save `cells'
restore

* Top-3 (rate_prov, pref_channel) within each BUG-LIKELY cell, ranked by over-$
bysort hs10 cty_code ym: egen double cell_total = total(over_dollars)
gsort hs10 cty_code ym -over_dollars
by hs10 cty_code ym: gen rank = _n
keep if rank <= 3
gen double rp_share = 100 * over_dollars / cell_total

keep hs10 cty_code ym rank rate_prov pref_channel rp_share
reshape wide rate_prov pref_channel rp_share, i(hs10 cty_code ym) j(rank)

foreach k of numlist 1 2 3 {
    rename rate_prov`k'    rp_top`k'
    rename pref_channel`k' rp_top`k'_chan
    rename rp_share`k'     rp_top`k'_pct
}
foreach v in rp_top1 rp_top2 rp_top3 rp_top1_chan rp_top2_chan rp_top3_chan {
    capture confirm string variable `v'
    if _rc != 0 gen str20 `v' = ""
    replace `v' = "" if missing(`v')
}
tempfile rp_wide
save `rp_wide'

* Combine with cell totals, rank, apply diagnostic top-N + $-floor cutoffs.
* Thresholds in globals.do: $diagnostic_top_n_cells, $diagnostic_cell_floor.
use `cells', clear
merge 1:1 hs10 cty_code ym using `rp_wide', keep(match master) nogenerate

gsort -over_dollars
gen long rank_global = _n
keep if rank_global <= $diagnostic_top_n_cells | over_dollars > $diagnostic_cell_floor

format con_val_mo cal_dut_mo over_dollars statutory_duty %20.0fc
format rate_usmca_monthly %5.4f
format rp_top1_pct rp_top2_pct rp_top3_pct %5.2f

label var rank_global         "Rank by over-\$"
label var hs10                "HS10 product"
label var cty_code            "Census country code"
label var partner_group       "Partner group"
label var ym                  "Month"
label var revision            "Active HTS revision"
label var rate_usmca_monthly  "Tracker rate (decimal)"
label var con_val_mo          "Imports (USD)"
label var cal_dut_mo          "Census duty (USD)"
label var statutory_duty      "Implied tracker duty (USD)"
label var over_dollars        "Over-statement (USD)"
label var rp_top1             "Top rate_prov by over-\$"
label var rp_top1_chan        "Top rate_prov channel"
label var rp_top1_pct         "Top rate_prov share of cell over-\$ (%)"
label var rp_top2             "2nd rate_prov"
label var rp_top2_chan        "2nd rate_prov channel"
label var rp_top2_pct         "2nd rate_prov share (%)"
label var rp_top3             "3rd rate_prov"
label var rp_top3_chan        "3rd rate_prov channel"
label var rp_top3_pct         "3rd rate_prov share (%)"

order rank_global hs10 cty_code partner_group ym revision ///
      rate_usmca_monthly con_val_mo cal_dut_mo statutory_duty over_dollars ///
      rp_top1 rp_top1_chan rp_top1_pct rp_top2 rp_top2_chan rp_top2_pct ///
      rp_top3 rp_top3_chan rp_top3_pct

di as text _n "  === Top ${diagnostic_top_n_print} BUG-LIKELY cells by over-\$ ==="
list rank_global hs10 cty_code ym over_dollars rate_usmca_monthly ///
     rp_top1 rp_top1_chan if _n <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_over_top_cells.csv", replace
di as text "       wrote `=_N' rows -> tracker_over_top_cells.csv"


* ======================================================================
* E. BY rate_prov  (BUG-LIKELY only)  -- single most actionable file
* ======================================================================

di as text _n "  [E] Aggregating by rate_prov (BUG-LIKELY only)..."

use `over_entries', clear
keep if buglike == 1
replace rate_prov = "<empty>" if missing(rate_prov) | trim(rate_prov) == ""

collapse (sum) over_dollars con_val_mo cal_dut_mo ///
         (count) n_cell_rows = over_dollars, by(rate_prov pref_channel)

egen double total_dut = total(over_dollars)
gen double share_pct = 100 * over_dollars / total_dut
drop total_dut
gsort -over_dollars

format over_dollars con_val_mo cal_dut_mo %20.0fc
format share_pct %6.2f
format n_cell_rows %9.0fc

label var rate_prov     "HTS rate provision (importer-declared)"
label var pref_channel  "Channel"
label var over_dollars  "Tracker over-statement (USD)"
label var con_val_mo    "Imports in this rate_prov (USD)"
label var cal_dut_mo    "Census duty in this rate_prov (USD)"
label var n_cell_rows   "Cell-rows in this rate_prov"
label var share_pct     "Share of BUG-LIKELY over-\$ (%)"

di as text _n "  === Top ${diagnostic_top_n_print} rate_prov by BUG-LIKELY over-\$ ==="
list rate_prov pref_channel n_cell_rows over_dollars share_pct ///
    if _n <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_over_by_rate_prov.csv", replace
di as text "       wrote `=_N' rate_prov rows -> tracker_over_by_rate_prov.csv"


* ======================================================================
* F. BY HS2 CHAPTER  (BUG-LIKELY only)
* ======================================================================

di as text _n "  [F] Aggregating by HS2 chapter (BUG-LIKELY only)..."

use `over_entries', clear
keep if buglike == 1
gen str2 hs2 = substr(hs10, 1, 2)
destring hs2, gen(hs2_num) force

collapse (sum) over_dollars con_val_mo cal_dut_mo ///
         (count) n_cells = over_dollars, by(hs2 hs2_num)

egen double total_dut = total(over_dollars)
gen double share_pct = 100 * over_dollars / total_dut
drop total_dut
gsort -over_dollars

label values hs2_num hs2_lbl
format over_dollars con_val_mo cal_dut_mo %20.0fc
format share_pct %6.2f
format n_cells %9.0fc

label var hs2          "HS2 chapter"
label var hs2_num      "HS2 chapter (numeric, labeled)"
label var n_cells      "BUG-LIKELY cells in chapter"
label var over_dollars "Tracker over-statement (USD)"
label var con_val_mo   "Imports (USD)"
label var cal_dut_mo   "Census duty (USD)"
label var share_pct    "Share of BUG-LIKELY over-\$ (%)"

di as text _n "  === Top ${diagnostic_top_n_print} HS2 chapters by BUG-LIKELY over-\$ ==="
list hs2_num n_cells over_dollars share_pct if _n <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_over_by_hs2.csv", replace
di as text "       wrote `=_N' chapters -> tracker_over_by_hs2.csv"


* ======================================================================
* G. BY PARTNER GROUP  (BUG-LIKELY only)
* ======================================================================

di as text _n "  [G] Aggregating by partner group (BUG-LIKELY only)..."

use `over_entries', clear
keep if buglike == 1
collapse (sum) over_dollars con_val_mo cal_dut_mo ///
         (count) n_cells = over_dollars, by(partner_group)

egen double total_dut = total(over_dollars)
gen double share_pct = 100 * over_dollars / total_dut
drop total_dut
gsort -over_dollars

format over_dollars con_val_mo cal_dut_mo %20.0fc
format share_pct %6.2f
format n_cells %9.0fc

label var partner_group "Partner group"
label var n_cells       "BUG-LIKELY cells"
label var over_dollars  "Tracker over-statement (USD)"
label var share_pct     "Share of BUG-LIKELY over-\$ (%)"

di as text _n "  === Over-statement by partner group ==="
list partner_group n_cells over_dollars share_pct, clean noobs

export delimited using "$tables/tracker_over_by_country.csv", replace
di as text "       wrote `=_N' partner groups -> tracker_over_by_country.csv"


* ======================================================================
* G2. PER-COUNTRY DETAIL  (top 50 globally, BUG-LIKELY only)
* ======================================================================

di as text _n "  [G2] Per-country detail (BUG-LIKELY only)..."

use `over_entries', clear
keep if buglike == 1
collapse (sum) over_dollars con_val_mo cal_dut_mo ///
         (count) n_cells = over_dollars, by(cty_code partner_group)

* cty_lookup.dta is built once in 01_etr_clean.do Section B2b.
merge m:1 cty_code using "$working/cty_lookup.dta", keep(match master) nogenerate

egen double total_dut = total(over_dollars)
gen double share_pct = 100 * over_dollars / total_dut
drop total_dut

gsort -over_dollars
gen long rank_global = _n
* Threshold: $diagnostic_top_n_countries in globals.do.
keep if rank_global <= $diagnostic_top_n_countries

format over_dollars con_val_mo cal_dut_mo %20.0fc
format share_pct %6.2f
format n_cells %9.0fc

label var cty_code      "Census country code"
label var country_name  "Country name"
label var partner_group "Partner group"
label var n_cells       "BUG-LIKELY cells"
label var over_dollars  "Tracker over-statement (USD)"
label var share_pct     "Share of BUG-LIKELY over-\$ (%)"
label var rank_global   "Rank by over-\$"

order rank_global country_name cty_code partner_group n_cells ///
      over_dollars con_val_mo cal_dut_mo share_pct

di as text _n "  === Top ${diagnostic_top_n_print} countries by BUG-LIKELY over-\$ ==="
list rank_global country_name partner_group n_cells over_dollars share_pct ///
    if rank_global <= $diagnostic_top_n_print, clean noobs

export delimited using "$tables/tracker_over_by_country_detail.csv", replace
di as text "       wrote `=_N' rows -> tracker_over_by_country_detail.csv"


* ======================================================================
* H. FIRST-OVER REVISION  (BUG-LIKELY only; regression localization)
* ======================================================================
*
* For each (HS10, cty), find the earliest month it became over-stating in
* a BUG-LIKELY channel and the active HTS revision at that month. Counting
* first-overs by revision reveals whether new tracker over-statements are
* tied to specific revisions.

di as text _n "  [H] First-over revision pattern..."

use `over_entries', clear
keep if buglike == 1

* Collapse to cell grain so first-month is well-defined
collapse (sum) over_dollars cal_dut_mo, by(hs10 cty_code ym revision)
sort hs10 cty_code ym
by hs10 cty_code: gen byte first_over = (_n == 1)

preserve
    keep if first_over == 1
    collapse (count) n_first_over   = first_over ///
             (sum)   first_over_dut = over_dollars, ///
        by(revision)
    egen double total_first_dut = total(first_over_dut)
    gen double share_pct = 100 * first_over_dut / total_first_dut
    drop total_first_dut
    gsort -first_over_dut

    format first_over_dut %20.0fc
    format n_first_over %9.0fc
    format share_pct %6.2f

    label var revision        "HTS revision"
    label var n_first_over    "(hs10 x cty) cells first over-stating in this revision"
    label var first_over_dut  "First-month over-\$ in cells first over-stating here (USD)"
    label var share_pct       "Share of total first-over \$ (%)"

    di as text _n "  === First-over revisions ==="
    list revision n_first_over first_over_dut share_pct if _n <= $diagnostic_top_n_print, clean noobs

    export delimited using "$tables/tracker_over_by_revision.csv", replace
    di as text "       wrote `=_N' revisions -> tracker_over_by_revision.csv"
restore


di as text _n "  05b_tracker_over_diagnostic complete." _n
