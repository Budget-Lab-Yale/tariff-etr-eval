* ==============================================================================
* 00_etr_eval.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Master orchestration script for the tariff-etr-eval project.
*          Compares actual (collected) vs. statutory (scheduled) effective
*          tariff rates during the 2025-2026 tariff escalation.
*
* Prerequisites:
*   1. Install required Stata packages (see below)
*   2. Run R/00_pull_raw_data.R to populate data/raw/
*
* Usage:
*   cd "C:/Users/ji252/Documents/GitHub/tariff-etr-eval"
*   do 00_etr_eval.do
* ==============================================================================

* ==============================================================================
* Required Stata packages (uncomment to install)
* ==============================================================================

* ssc install ftools, replace
* ssc install reghdfe, replace
* ssc install gtools, replace
* ssc install estout, replace
* ssc install coefplot, replace
* ssc install plotplainblind, replace
* ssc install heatplot, replace        // for 03 Section D7 product x partner heatmap
* ssc install palettes, replace        // heatplot dep
* ssc install colrspace, replace       // heatplot dep

* ==============================================================================
* Preliminaries
* ==============================================================================

clear all
version 17.0
set more off
* maxvar bumped above the default 5000 -- merged_analysis.dta carries ~30 cols
* and downstream reshapes (e.g. 03 Section D2's pg_short reshape) push past
* default in the working set. 10000 is comfortable; raise further only if
* a future reshape adds many columns.
set maxvar 10000
set seed 8675309

timer clear
timer on 1

* ==============================================================================
* Paths
* ==============================================================================

* Auto-detect project root from current working directory
global dir "`c(pwd)'/"
global dir : subinstr global dir "\" "/" , all

* Verify we're in the right place
mata: st_local("dir_ok", strofreal(fileexists(st_global("dir") + "00_etr_eval.do")))
if `dir_ok' == 0 {
    di as error "ERROR: 00_etr_eval.do not found in current directory."
    di as error "       cd to the project root before running."
    error 601
}

* ==============================================================================
* Load globals and programs
* ==============================================================================

do "${dir}code/utils/globals.do"
do "${dir}code/utils/programs.do"

* Create output directories if needed
capture mkdir "${working}"
capture mkdir "${results}"
capture mkdir "${figures}"
capture mkdir "${tables}"
capture mkdir "${logs}"

* ==============================================================================
* Log
* ==============================================================================

capture log close
* Build today's date string YYYY-MM-DD from c(current_date), which is always
* "DD MMM YYYY" regardless of locale. Explicit year/month/day construction
* avoids the "%tdCY-NN-DD" picture-format Stata bug that produced doubled
* output on some builds.
local _d = date(c(current_date), "DMY")
local today = string(year(`_d'), "%04.0f") + "-" + ///
              string(month(`_d'), "%02.0f") + "-" + ///
              string(day(`_d'), "%02.0f")
log using "${logs}etr_eval_`today'.log", replace text

di as text _n "=============================================="
di as text "  Tariff ETR Evaluation Pipeline"
di as text "  Started: `c(current_date)' `c(current_time)'"
di as text "  Project: ${dir}"
di as text "==============================================" _n

* ==============================================================================
* Step 0: R data pulls (~30-60 min default; off by default)
* Flags forwarded from globals: $pull_refresh_tracker, $pull_with_census
* ==============================================================================

if $run_pull {
    di as text "=== Step 0: R data pulls ===" _n
    local r_flags ""
    if $pull_refresh_tracker local r_flags "`r_flags' --refresh-tracker"
    if $pull_with_census     local r_flags "`r_flags' --with-census"
    di as text "  Rscript flags: `r_flags'"
    shell Rscript "${code}R/00_pull_raw_data.R" `r_flags'
}
else {
    di as text "=== Step 0: SKIPPED (run_pull = 0) ===" _n
}

* ==============================================================================
* Step 1: Import, clean, and merge
* ==============================================================================

if $run_clean {
    di as text "=== Step 1: Clean and merge ===" _n
    do "${code}01_etr_clean.do"
}
else {
    di as text "=== Step 1: SKIPPED (run_clean = 0) ===" _n
}

* ==============================================================================
* Step 2: Counterfactual ladder (canonical S0/S1/S2/S3 + T)
* ==============================================================================

if $run_ladder {
    di as text "=== Step 2: Counterfactual ladder ===" _n
    do "${code}02_counterfactual_ladder.do"
}
else {
    di as text "=== Step 2: SKIPPED (run_ladder = 0) ===" _n
}

* ==============================================================================
* Step 3: Six-tier decomposition + figures (consumes ladder + adds S4)
*         03   = framework decomposition + figs 1-6 + diagnostic tables
*         03b  = paper §4.1 baseline figure + §4.5 daily overlay + supplementary
*                monthly summary table (TBL judgment, separate methodology)
* ==============================================================================

if $run_analysis {
    di as text "=== Step 3: Analysis and figures ===" _n
    do "${code}03_etr_analysis.do"
    di as text "=== Step 3b: Baseline figures (TBL judgment) ===" _n
    do "${code}03b_baseline_figures.do"
}
else {
    di as text "=== Step 3: SKIPPED (run_analysis = 0) ===" _n
}

* ==============================================================================
* Step 4: FTA / preference decomposition (requires IMDB detail)
* ==============================================================================

if $run_fta {
    di as text "=== Step 4: FTA decomposition ===" _n
    do "${code}04_fta_decomposition.do"
}
else {
    di as text "=== Step 4: SKIPPED (run_fta = 0) ===" _n
}

* ==============================================================================
* Step 5: Max-district cross-check (requires IMDB detail)
* ==============================================================================

if $run_crosscheck {
    di as text "=== Step 5: Max-district crosscheck ===" _n
    do "${code}05_max_district_crosscheck.do"
}
else {
    di as text "=== Step 5: SKIPPED (run_crosscheck = 0) ===" _n
}

* ==============================================================================
* Step 6: Baseline ETR diagnostic (2024 wts, tracker vs reconstruction USMCA)
* ==============================================================================

if $run_baseline {
    di as text "=== Step 6: Baseline ETR diagnostic ===" _n
    do "${code}06_baseline_etr_diagnostic.do"
}
else {
    di as text "=== Step 6: SKIPPED (run_baseline = 0) ===" _n
}

* ==============================================================================
* Done
* ==============================================================================

timer off 1
quietly timer list

di as text _n "=============================================="
di as text "  Pipeline complete"
di as text "  Finished: `c(current_date)' `c(current_time)'"
di as text "  Elapsed: " round(r(t1), 0.1) " seconds"
di as text "==============================================" _n

di as text "Results:"
local figs : dir "${figures}" files "*.png"
foreach f of local figs {
    di as text "  figures/`f'"
}
local tabs : dir "${tables}" files "*.csv"
foreach f of local tabs {
    di as text "  tables/`f'"
}

log close
