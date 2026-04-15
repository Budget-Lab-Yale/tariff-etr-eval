# ==============================================================================
# 00_etr_eval.R -- Orchestrator for tariff-etr-eval
#
# Compares actual (collected) vs. statutory (scheduled) effective tariff rates
# for the 2025-2026 tariff escalation period.
#
# Dependencies:
#   - tariff-rate-tracker: rate_timeseries.rds, daily ETR CSVs
#   - tariff-impact-tracker: tariff_revenue.csv (actual ETR from Haver)
#
# Author: John Iselin
# ==============================================================================

library(here)
here::i_am("run_all.R")

cat("=== Tariff ETR Evaluation Pipeline ===\n")
cat("Started:", format(Sys.time()), "\n\n")

# --- Step 0: Validate sibling repo data ---
cat("Step 0: Checking data dependencies...\n")

tracker_dir <- file.path(dirname(here()), "tariff-rate-tracker")
impacts_dir <- file.path(dirname(here()), "tariff-impact-tracker")

required_files <- c(
  file.path(tracker_dir, "data", "timeseries", "rate_timeseries.rds"),
  file.path(tracker_dir, "output", "daily", "daily_overall.csv"),
  file.path(tracker_dir, "output", "daily", "daily_by_authority.csv"),
  file.path(impacts_dir, "output", "tariff_revenue.csv")
)

missing <- required_files[!file.exists(required_files)]
if (length(missing) > 0) {
  cat("WARNING: Missing data files:\n")
  cat(paste(" -", missing, collapse = "\n"), "\n")
  cat("Some figures may be unavailable.\n\n")
} else {
  cat("  All required data files found.\n\n")
}

# --- Step 1a: Pull Census trade data via API (if needed, lightweight) ---
census_file <- here("data", "census_hs2_country_monthly.csv")
if (!file.exists(census_file)) {
  cat("Step 1a: Pulling Census trade data from API...\n")
  tryCatch({
    source(here("R", "01_pull_census_trade.R"))
    cat("  Census data pull complete.\n\n")
  }, error = function(e) {
    cat("  ERROR pulling Census data:", conditionMessage(e), "\n\n")
  })
} else {
  cat("Step 1a: Census HS2 trade data already exists, skipping API pull.\n")
  cat("  (Delete", census_file, "to force re-pull)\n\n")
}

# --- Step 1b: Download & parse IMDB bulk files (primary data source) ---
imdb_combined <- here("data", "imdb", "imdb_combined.rds")
if (!file.exists(imdb_combined)) {
  cat("Step 1b: Downloading IMDB bulk files from Census...\n")
  cat("  (This downloads ~250MB of data and may take several minutes)\n")
  tryCatch({
    source(here("R", "01b_download_imdb.R"))
    cat("  IMDB download and parse complete.\n\n")
  }, error = function(e) {
    cat("  ERROR with IMDB download:", conditionMessage(e), "\n")
    cat("  FTA decomposition and district cross-check will be unavailable.\n\n")
  })
} else {
  cat("Step 1b: IMDB data already exists, skipping download.\n")
  cat("  (Delete", imdb_combined, "to force re-download)\n\n")
}

# --- Step 2a: FTA utilization decomposition (requires IMDB) ---
if (file.exists(imdb_combined)) {
  cat("Step 2a: Running FTA utilization decomposition...\n")
  tryCatch({
    source(here("R", "02b_fta_decomposition.R"))
    cat("  FTA decomposition complete.\n\n")
  }, error = function(e) {
    cat("  ERROR in FTA decomposition:", conditionMessage(e), "\n\n")
  })
} else {
  cat("Step 2a: Skipping FTA decomposition (no IMDB data).\n\n")
}

# --- Step 2b: Max-across-districts cross-check (requires IMDB) ---
if (file.exists(imdb_combined)) {
  cat("Step 2b: Running max-district statutory rate cross-check...\n")
  tryCatch({
    source(here("R", "02c_max_district_crosscheck.R"))
    cat("  Max-district cross-check complete.\n\n")
  }, error = function(e) {
    cat("  ERROR in max-district cross-check:", conditionMessage(e), "\n\n")
  })
} else {
  cat("Step 2b: Skipping max-district cross-check (no IMDB data).\n\n")
}

# --- Step 3: Render report ---
cat("Step 3: Rendering ETR evaluation report...\n")

output_dir <- here("output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

tryCatch({
  rmarkdown::render(
    here("R", "etr_eval_report.Rmd"),
    output_format = "html_document",
    output_dir = output_dir,
    quiet = TRUE
  )
  cat("  HTML report generated.\n")
}, error = function(e) {
  cat("  ERROR rendering HTML:", conditionMessage(e), "\n")
})

tryCatch({
  rmarkdown::render(
    here("R", "etr_eval_report.Rmd"),
    output_format = "word_document",
    output_dir = output_dir,
    quiet = TRUE
  )
  cat("  Word report generated.\n")
}, error = function(e) {
  cat("  ERROR rendering Word:", conditionMessage(e), "\n")
})

# --- Step 4: Render v2 report (monthly decomposition) ---
cat("\nStep 4: Rendering ETR evaluation report v2...\n")

tryCatch({
  rmarkdown::render(
    here("R", "etr_eval_report_v2.Rmd"),
    output_format = "html_document",
    output_dir = output_dir,
    quiet = TRUE
  )
  cat("  v2 HTML report generated.\n")
}, error = function(e) {
  cat("  ERROR rendering v2 HTML:", conditionMessage(e), "\n")
})

tryCatch({
  rmarkdown::render(
    here("R", "etr_eval_report_v2.Rmd"),
    output_format = "word_document",
    output_dir = output_dir,
    quiet = TRUE
  )
  cat("  v2 Word report generated.\n")
}, error = function(e) {
  cat("  ERROR rendering v2 Word:", conditionMessage(e), "\n")
})

# --- Summary ---
cat("\n=== Pipeline complete ===\n")
cat("Finished:", format(Sys.time()), "\n")
cat("Output directory:", output_dir, "\n")

output_files <- list.files(output_dir, full.names = FALSE)
if (length(output_files) > 0) {
  cat("Files:\n")
  cat(paste(" -", output_files, collapse = "\n"), "\n")
}
