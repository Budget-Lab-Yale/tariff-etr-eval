* ==============================================================================
* globals.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Centralized global macros for the tariff-etr-eval project.
*          Defines paths, graph settings, analysis parameters, and color
*          palettes. Sourced by 00_etr_eval.do at startup.
* ==============================================================================

version 17.0

* --- Project paths ---
* $dir is set by the orchestrator before this file runs.
global code     "${dir}code/"
global data     "${dir}data/"
global raw      "${dir}data/raw/"
global working  "${dir}data/working/"
global results  "${dir}results/"
global figures  "${dir}results/figures/"
global tables   "${dir}results/tables/"
global logs     "${dir}logs/"

* --- Overleaf integration (optional) ---
* Set $overleaf = 1 and define paths to enable dual export.
* Leave $overleaf = 0 to skip Overleaf export entirely.
global overleaf 0
* global ol_fig "C:/Users/ji252/Dropbox/Apps/Overleaf/TariffETR/figures/"
* global ol_tab "C:/Users/ji252/Dropbox/Apps/Overleaf/TariffETR/tables/"

* --- Graph settings ---
* `set scheme` is per-session; safe to leave on. `graph set window fontface`
* writes to Stata's persistent global preferences and survives across sessions.
* That's an intentional choice for this project (consistent paper output) but
* worth knowing if you run unrelated Stata work in the same install.
capture set scheme plotplainblind
if _rc != 0 {
    di as error "WARNING: plotplainblind scheme not installed (run: ssc install plotplainblind)"
}
graph set window fontface "Times New Roman"

* --- Color globals (RGB for Stata graph commands) ---
global color_actual    "200 16 46"       // Red
global color_statutory "0 85 164"        // Navy
global color_gap       "40 167 69"       // Green
global color_gray      "108 117 125"     // Gray

* Partner group colors (colorblind-friendly)
global color_china     "200 16 46"
global color_canada    "0 85 164"
global color_mexico    "40 167 69"
global color_eu        "255 193 7"
global color_japan     "155 89 182"
global color_skorea    "230 126 34"
global color_uk        "26 188 156"
global color_row       "149 165 166"

* --- Analysis parameters ---
* Analysis window (Stata monthly dates)
global start_ym = ym(2025, 1)
global end_ym   = ym(2026, 2)

* --- Cross-check thresholds (used by 05_max_district_crosscheck.do) ---
* rate_extreme_cutoff: drop entry-level rates above this proportion. Following
*   Gopinath-Neiman, 2.0 (200%) catches data-entry errors and AVE failures
*   while keeping legitimate compound-tariff observations. China and Russia
*   are exempted because their entry rates can legitimately exceed the cutoff.
* match_tol_pp / match_tol_loose_pp: tolerance bands for "tracker matches
*   max-observed district rate" in percentage points (strict = 2pp, loose = 5pp).
* divergence_pp_cutoff / divergence_value_cutoff: thresholds for flagging
*   "large divergences" worth manual review (>5pp gap and >$100M in 2024 imports).
global rate_extreme_cutoff      2.0
global match_tol_pp             2
global match_tol_loose_pp       5
global divergence_pp_cutoff     5
global divergence_value_cutoff  1e8

* --- Tracker diagnostic thresholds (used by 05a/05b) ---
* These shape the operator-handoff CSVs delivered to the tracker maintainer.
* Tunable to balance signal-to-noise against deliverable size.
*   diagnostic_top_n_cells      keep top-N cells by $ in tracker_*_top_cells.csv
*   diagnostic_cell_floor       OR keep cells with $ duty above this floor
*   diagnostic_top_n_countries  keep top-N countries in *_by_country_detail.csv
*   diagnostic_top_n_print      number of rows printed in log (sanity check)
global diagnostic_top_n_cells      200
global diagnostic_cell_floor       1e6
global diagnostic_top_n_countries  50
global diagnostic_top_n_print      25

* --- Tracker-over channel partition (used by 05b) ---
* Buckets pref_channel codes into legitimate-preference vs likely-bug vs noise
* groups for the tracker over-statement diagnostic. Format mirrors $eu_codes_*:
* comma-separated quoted strings so each global drops directly into inlist().
* Update in lockstep with classify_pref_channel in programs.do if a new
* channel is added.
global over_legit_channels    `""usmca", "korus", "other_fta", "gsp_agoa""'
global over_buglike_channels  `""duty_free", "mfn_dutiable", "ch99_dutiable""'
global over_noise_channels    `""ftz_bonded", "other""'

* Partner groups (for decomposition loops)
global partner_groups `" "China" "Canada" "Mexico" "EU" "Japan" "S. Korea" "UK" "ROW" "'

* Individual partner country codes (Census)
global cty_china  "5700"
global cty_canada "1220"
global cty_mexico "2010"
global cty_japan  "5880"
global cty_skorea "5800"
global cty_uk     "4120"
global cty_russia "4621"   // legacy IRS code retained in Census tables

* EU27 member states (Census country codes). Stored as comma-quoted
* batches of <=9 so they can be passed to inlist(). Stata's string inlist()
* limit is 10 args (1 var + 9 strings); any 10th comparison value triggers
* "too many string values" with no row info. If you add a country, append a
* new $eu_codes_4 batch rather than padding an existing one. Used by
* assign_partner_group and any script that needs to classify EU members.
global eu_codes_1 `""4280", "4220", "4230", "4240", "4253", "4254", "4270", "4350", "4360""'
global eu_codes_2 `""4380", "4390", "4550", "4560", "4570", "4590", "4610", "4690", "4700""'
global eu_codes_3 `""4720", "4740", "4810", "4760", "4770", "4780", "4840", "4850", "4870""'

* --- Policy event dates (for figure reference lines) ---
* Date and label arrays are paired by index: $event_label_N matches the Nth
* event below. If you reorder these, reorder the labels too.
global event_fentanyl     = td(04feb2025)
global event_232_autos    = td(12mar2025)
global event_liberation   = td(02apr2025)
global event_phase1_pause = td(09apr2025)
global event_phase2       = td(01jul2025)
global event_phase2_recip = td(07aug2025)
global event_scotus_s122  = td(24feb2026)

* Policy event labels (index-paired with the dates above)
global event_label_1 "Fentanyl"
global event_label_2 "232 Autos"
global event_label_3 "Liberation Day"
global event_label_4 "Phase 1 Pause"
global event_label_5 "Phase 2"
global event_label_6 "Phase 2 Recip."
global event_label_7 "SCOTUS / S.122"

* --- Run-mode flags (toggle pipeline steps) ---
global run_pull       0     // Step 0: R data pulls (~30-60 min; off by default)
global run_clean      1     // Step 1: import, clean, merge
global run_ladder     1     // Step 2: counterfactual ladder (S0-S3 + T)
global run_analysis   1     // Step 3: six-tier decomposition and figures (consumes ladder)
global run_fta        1     // Step 4: FTA/preference decomposition (needs imdb_detail.csv)
global run_crosscheck 1     // Step 5: max-district tracker validation (needs imdb_detail.csv)
global run_baseline   1     // Step 6: baseline ETR diagnostic

* --- Step 0 R-flag passthrough (only relevant when run_pull = 1) ---
* Each global maps to a CLI flag forwarded to code/R/00_pull_raw_data.R.
global pull_refresh_tracker 1     // 1 = --refresh-tracker (rebuild tracker first; ~hours, requires DATAWEB_API_TOKEN in tracker .env)
global pull_with_census     0     // 1 = --with-census (also pull Census HS2 API; hours, output unused by Stata)

* --- Confirmation ---
di as text "  globals.do loaded: $dir"
