* ==============================================================================
* globals.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Centralized global macros for the tariff-etr-eval project.
*          Defines paths, graph settings, analysis parameters, and color
*          palettes. Sourced by 00_etr_eval.do at startup.
* ==============================================================================

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
set scheme plotplainblind
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

* Partner groups (for decomposition loops)
global partner_groups `" "China" "Canada" "Mexico" "EU" "Japan" "S. Korea" "UK" "ROW" "'

* Individual partner country codes (Census)
global cty_china  "5700"
global cty_canada "1220"
global cty_mexico "2010"
global cty_japan  "5880"
global cty_skorea "5800"
global cty_uk     "4120"

* EU27 member states (Census country codes). Stored as comma-quoted
* batches of <=9 so they can be passed to inlist(). Used by
* assign_partner_group and any script that needs to classify EU members.
global eu_codes_1 `""4280", "4220", "4230", "4240", "4253", "4254", "4270", "4350", "4360""'
global eu_codes_2 `""4380", "4390", "4550", "4560", "4570", "4590", "4610", "4690", "4700""'
global eu_codes_3 `""4720", "4740", "4810", "4760", "4770", "4780", "4840", "4850", "4870""'

* --- Policy event dates (for figure reference lines) ---
global event_fentanyl     = td(04feb2025)
global event_232_autos    = td(12mar2025)
global event_liberation   = td(02apr2025)
global event_phase1_pause = td(09apr2025)
global event_phase2       = td(01jul2025)
global event_phase2_recip = td(07aug2025)
global event_scotus_s122  = td(24feb2026)

* Policy event labels
global event_label_1 "Fentanyl"
global event_label_2 "232 Autos"
global event_label_3 "Liberation Day"
global event_label_4 "Phase 1 Pause"
global event_label_5 "Phase 2"
global event_label_6 "Phase 2 Recip."
global event_label_7 "SCOTUS / S.122"

* --- Run-mode flags (toggle pipeline steps) ---
global run_pull       0     // Step 0: R data pulls (hours-long, off by default)
global run_clean      1     // Step 1: import, clean, merge
global run_analysis   1     // Step 2: four-tier decomposition and figures
global run_fta        1     // Step 3: FTA/preference decomposition (needs imdb_detail.csv)
global run_crosscheck 1     // Step 4: max-district tracker validation (needs imdb_detail.csv)
global run_ladder     1     // Step 5: counterfactual waterfall
global run_baseline   1     // Step 6: baseline ETR diagnostic (2024 wts, tracker USMCA)

* --- Confirmation ---
di as text "  globals.do loaded: $dir"
