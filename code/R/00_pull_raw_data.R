# ==============================================================================
# 00_pull_raw_data.R
#
# Single R script that assembles all raw data for the Stata pipeline.
# Pulls from external APIs and sibling repos, exports everything as CSVs
# into data/raw/. Always overwrites existing files.
#
# Data sources:
#   1. Census Bureau API    -- HS2 x country monthly trade data
#   2. Census IMDB bulk     -- HS10 x country monthly (via fixed-width ZIPs)
#   3. tariff-rate-tracker  -- snapshot rates, daily ETRs, revision dates,
#                              import weights. Snapshots + daily ETRs come
#                              from the shared tracker publish (parquet +
#                              manifest) when available; everything else
#                              (and all of section 3 otherwise) comes from
#                              a sibling checkout. See "Tracker data source"
#                              below.
#   4. tariff-impact-tracker -- Treasury revenue (actual ETR)
#
# Usage:
#   Rscript code/R/00_pull_raw_data.R                 # IMDB + tracker + impacts
#   Rscript code/R/00_pull_raw_data.R --with-census    # add Census HS2 API
#                                                       # (hours-long; output is
#                                                       # NOT consumed by Stata,
#                                                       # only by 2b fallback)
#   Rscript code/R/00_pull_raw_data.R --skip-imdb      # skip IMDB bulk
#   Rscript code/R/00_pull_raw_data.R --only-imdb      # IMDB bulk only (no
#                                                       # sibling repos/tokens;
#                                                       # rebuilds the two IMDB
#                                                       # CSVs from cached ZIPs)
#   Rscript code/R/00_pull_raw_data.R --only-tracker    # sections 3a-3e only
#   Rscript code/R/00_pull_raw_data.R --only-counterfactual  # sections 3d-3e only
#   Rscript code/R/00_pull_raw_data.R --refresh-tracker # rebuild tracker data
#                                                       # (snapshots, daily ETR,
#                                                       # USMCA shares, scenarios)
#                                                       # before the export steps;
#                                                       # ~60-90 min, requires
#                                                       # DATAWEB_API_TOKEN env var.
#                                                       # Composes with other flags.
#                                                       # Requires sibling checkout.
#   Rscript code/R/00_pull_raw_data.R --tracker-data=PATH  # read snapshots +
#                                                       # daily ETRs from a
#                                                       # specific tracker publish
#                                                       # (e.g. a pinned vintage
#                                                       # instead of latest)
#   Rscript code/R/00_pull_raw_data.R --no-shared-tracker  # force the sibling-
#                                                       # checkout path even if
#                                                       # the shared publish exists
#
# Output (all in data/raw/):
#   census_hs2_country_monthly.csv      -- HS2 x country x month
#   imdb_detail.csv                     -- HS10 x country x district x pref x month
#   imdb_hs10_country_monthly.csv       -- HS10 x country x month (aggregated)
#   census_hs10_fallback.csv            -- HS10 x country x month (API, gap months)
#   snapshot_rates/snapshot_{rev}.csv   -- statutory rates per revision (production)
#   snapshot_rates/<scenario>/snapshot_{rev}.csv -- per-USMCA-scenario rates
#       (scenarios: usmca_none, usmca_2024, usmca_monthly, usmca_h2avg)
#   import_weights_2024.csv             -- 2024 annual import weights
#   daily_overall.csv                   -- daily statutory ETR
#   daily_by_country.csv                -- daily ETR by country
#   revision_dates.csv                  -- revision effective dates
#   tariff_revenue.csv                  -- actual monthly ETR
#   usmca_shares/usmca_product_shares_*.csv -- USMCA utilization shares (diagnostic)
#   counterfactual_usmca_none.csv       -- HS10 x country x month (0% USMCA)
#   counterfactual_usmca2024.csv        -- HS10 x country x month (USMCA 2024 baseline; S0)
#   counterfactual_usmca_monthly.csv    -- HS10 x country x month (monthly USMCA empirical)
#   counterfactual_h2avg.csv            -- HS10 x country x month (Post-July 2025 USMCA; S1/S2)
#   imdb_other_pref_shares_monthly.csv  -- HS10 x country x month preference shares
#   counterfactual_other_pref_delta_monthly.csv -- HS10 x country x month
#                                          rate-reduction delta from S2 to S3
#                                          (delta_base, delta_recip)
# ==============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(here)
library(stringi)
library(yaml)

here::i_am("code/R/00_pull_raw_data.R")

# --- Paths ---
RAW_DIR     <- here("data", "raw")
IMDB_DIR    <- here("data", "imdb")
IMDB_RAW    <- file.path(IMDB_DIR, "raw")
SNAP_DIR    <- file.path(RAW_DIR, "snapshot_rates")
TRACKER_DIR <- file.path(dirname(here()), "tariff-rate-tracker")
IMPACTS_DIR <- file.path(dirname(here()), "tariff-impact-tracker")

# Default location of the shared tracker publish, read from the gitignored
# config/local_paths.yaml (key: tracker_data_dir) -- see
# config/local_paths.yaml.example. Kept out of the repo so no internal
# server paths are committed. A dated vintage directory sits next to
# `latest`; pin one for reproducibility via --tracker-data= or the
# TRACKER_DATA_DIR env var.
LOCAL_PATHS_FILE <- here("config", "local_paths.yaml")
SHARED_TRACKER_DEFAULT <- NULL
if (file.exists(LOCAL_PATHS_FILE)) {
  lp <- read_yaml(LOCAL_PATHS_FILE)
  if (!is.null(lp$tracker_data_dir) && nzchar(lp$tracker_data_dir)) {
    SHARED_TRACKER_DEFAULT <- lp$tracker_data_dir
  }
}

dir.create(RAW_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(IMDB_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(IMDB_RAW, showWarnings = FALSE, recursive = TRUE)
dir.create(SNAP_DIR, showWarnings = FALSE, recursive = TRUE)

# --- Logging ---
# Writes to both console and a log file in logs/ for monitoring.
# Uses write(append=TRUE) instead of a file connection — Windows file
# connections don't flush reliably when R is backgrounded.
# Check progress with: tail -f logs/pull_raw_data.log
LOG_DIR <- here("logs")
dir.create(LOG_DIR, showWarnings = FALSE, recursive = TRUE)
LOG_FILE <- file.path(LOG_DIR,
                       paste0("pull_raw_data_",
                              format(Sys.Date(), "%Y-%m-%d"), ".log"))

# Truncate log at start of run (each day's log is its own file)
writeLines("", LOG_FILE)

log_msg <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  write(msg, LOG_FILE, append = TRUE)
}

# --- Helpers ---

# Classify IMDB entries into 9 preference / rate-provision channels. Mirrors
# the Stata `classify_pref_channel` program in `code/utils/programs.do`. Used
# by section 3f (non-USMCA preference share aggregation). Channels:
#   usmca, korus, other_fta, gsp_agoa     -- preference codes (cty_subco)
#   duty_free, ch99_dutiable, mfn_dutiable, ftz_bonded   -- rate-provision codes
#   other                                                 -- residual
# Order matters: preference codes take precedence over rate-provision codes.
classify_pref_channel <- function(cty_subco, rate_prov, cty_code) {
  CTY_CANADA <- "1220"
  CTY_MEXICO <- "2010"

  cty_subco <- ifelse(is.na(cty_subco), "", cty_subco)
  rate_prov <- ifelse(is.na(rate_prov), "", rate_prov)

  pref_channel <- character(length(cty_subco))

  # (a) USMCA: CA/MX with S/S+ preference codes
  pref_channel[cty_subco %in% c("S", "S+", "CA", "MX") &
               cty_code %in% c(CTY_CANADA, CTY_MEXICO)] <- "usmca"

  # (b) KORUS
  idx <- pref_channel == "" & cty_subco == "KR"
  pref_channel[idx] <- "korus"

  # (c) Other bilateral FTAs
  idx <- pref_channel == "" & cty_subco %in%
    c("AU", "IL", "SG", "CL", "CO", "PE", "PA", "JO",
      "MA", "OM", "BH", "P", "P+", "R", "JP", "NP")
  pref_channel[idx] <- "other_fta"

  # (d) GSP / AGOA
  idx <- pref_channel == "" & cty_subco %in%
    c("A", "A+", "A*", "D", "E", "E*", "J", "J+", "J*", "W", "Z", "N")
  pref_channel[idx] <- "gsp_agoa"

  # (e) Duty-free (rate_prov-based, only if no preference assigned)
  idx <- pref_channel == "" & rate_prov %in% c("10", "18", "19")
  pref_channel[idx] <- "duty_free"

  # (f) Ch99 dutiable
  idx <- pref_channel == "" & rate_prov %in% c("69", "79")
  pref_channel[idx] <- "ch99_dutiable"

  # (g) MFN dutiable
  idx <- pref_channel == "" & rate_prov %in% c("61", "62", "64", "70")
  pref_channel[idx] <- "mfn_dutiable"

  # (h) FTZ / bonded
  idx <- pref_channel == "" & rate_prov == "00"
  pref_channel[idx] <- "ftz_bonded"

  # (i) Residual
  pref_channel[pref_channel == ""] <- "other"

  pref_channel
}

# --- Run-mode flags ---
# Control which sections run. RUN_CENSUS is OFF by default (its output is no
# longer consumed by the Stata pipeline; the Section 2b HS10 fallback uses
# the cached CSV when present). All other sections are ON by default.
cli_args <- commandArgs(trailingOnly = TRUE)
RUN_CENSUS          <- FALSE  # opt-in via --with-census; HS2 API output is
                              # only consumed internally by Section 2b fallback
RUN_IMDB            <- TRUE
RUN_TRACKER         <- TRUE
RUN_COUNTERFACTUAL  <- TRUE
RUN_IMPACTS         <- TRUE
RUN_REFRESH_TRACKER <- FALSE  # opt-in: rebuilds tracker outputs in-place

if ("--with-census" %in% cli_args) {
  RUN_CENSUS <- TRUE
}
if ("--skip-imdb" %in% cli_args) {
  RUN_IMDB <- FALSE
}
if ("--only-tracker" %in% cli_args) {
  RUN_CENSUS <- FALSE; RUN_IMDB <- FALSE; RUN_IMPACTS <- FALSE
}
if ("--only-counterfactual" %in% cli_args) {
  RUN_CENSUS <- FALSE; RUN_IMDB <- FALSE; RUN_TRACKER <- FALSE; RUN_IMPACTS <- FALSE
  RUN_COUNTERFACTUAL <- TRUE
}
if ("--only-imdb" %in% cli_args) {
  # IMDB bulk parse only (no sibling repos / API tokens needed). Used to
  # regenerate the augmented imdb_detail.csv / imdb_hs10_country_monthly.csv
  # with quantity + shipping-weight columns from cached ZIPs.
  RUN_CENSUS <- FALSE; RUN_IMDB <- TRUE; RUN_TRACKER <- FALSE
  RUN_COUNTERFACTUAL <- FALSE; RUN_IMPACTS <- FALSE
}
if ("--refresh-tracker" %in% cli_args) {
  RUN_REFRESH_TRACKER <- TRUE
}

# --- Tracker data source (shared publish vs sibling checkout) ---
# Sections 3a (top-level snapshots) and 3c (daily ETRs, revision dates) read
# the published tracker data (parquet + manifest.json) instead of converting
# RDS from a sibling checkout when a publish is available. Resolution order:
#   1. --tracker-data=PATH    (CLI; pin a vintage)
#   2. --no-shared-tracker    (force sibling checkout)
#   3. TRACKER_DATA_DIR       (env var)
#   4. tracker_data_dir from config/local_paths.yaml, if it exists
#   5. sibling checkout only  (original behavior)
# Sections 3b/3d/3e (import weights, USMCA shares, scenario snapshots) are
# not yet in the publish and still need the sibling checkout -- see
# docs/shared_publish_extensions.md for the requested additions.
TRACKER_DATA_DIR <- NULL
td_flag <- grep("^--tracker-data=", cli_args, value = TRUE)
if (length(td_flag) > 0) {
  TRACKER_DATA_DIR <- sub("^--tracker-data=", "", td_flag[1])
  if (!dir.exists(TRACKER_DATA_DIR)) {
    stop("--tracker-data path not found: ", TRACKER_DATA_DIR, call. = FALSE)
  }
} else if (!("--no-shared-tracker" %in% cli_args)) {
  env_dir <- Sys.getenv("TRACKER_DATA_DIR")
  if (nzchar(env_dir)) {
    if (!dir.exists(env_dir)) {
      stop("TRACKER_DATA_DIR not found: ", env_dir, call. = FALSE)
    }
    TRACKER_DATA_DIR <- env_dir
  } else if (!is.null(SHARED_TRACKER_DEFAULT) &&
             dir.exists(SHARED_TRACKER_DEFAULT)) {
    TRACKER_DATA_DIR <- SHARED_TRACKER_DEFAULT
  }
}
USE_SHARED_TRACKER <- !is.null(TRACKER_DATA_DIR)

if (USE_SHARED_TRACKER && !requireNamespace("arrow", quietly = TRUE)) {
  stop("Package 'arrow' is required to read the shared tracker publish.",
       "\n  install.packages(\"arrow\"), or rerun with --no-shared-tracker",
       " to use the sibling checkout.", call. = FALSE)
}

log_msg("=======================================================")
log_msg("  Raw Data Assembly for tariff-etr-eval")
log_msg("  Started: ", format(Sys.time()))
log_msg("  Sections: census=", RUN_CENSUS, " imdb=", RUN_IMDB,
        " tracker=", RUN_TRACKER, " counterfactual=", RUN_COUNTERFACTUAL,
        " impacts=", RUN_IMPACTS, " refresh-tracker=", RUN_REFRESH_TRACKER)
log_msg("=======================================================")

# Log tracker-source provenance up front so every run records which data it
# consumed (the shared publish carries vintage + git commit in its manifest).
if (USE_SHARED_TRACKER) {
  log_msg("  Tracker data: shared publish at ", TRACKER_DATA_DIR)
  manifest_path <- file.path(TRACKER_DATA_DIR, "manifest.json")
  if (file.exists(manifest_path)) {
    mf <- jsonlite::fromJSON(manifest_path)
    mf_commit <- if (is.null(mf$git$commit)) "?" else substr(mf$git$commit, 1, 9)
    log_msg("    vintage=", mf$vintage, " commit=", mf_commit,
            " schema=", mf$schema_version, " rate_unit=", mf$rate_unit)
    if (!identical(mf$rate_unit, "fraction")) {
      log_msg("    WARNING: publish rate_unit is '", mf$rate_unit,
              "' -- the Stata pipeline assumes fractional rates")
    }
  } else {
    log_msg("    WARNING: manifest.json not found in publish")
  }
} else {
  log_msg("  Tracker data: sibling checkout at ", TRACKER_DIR)
}


# ======================================================================
# 0. REFRESH TRACKER (optional, opt-in via --refresh-tracker)
# ======================================================================
#
# Shells out to the sibling tariff-rate-tracker repo and rebuilds:
#   - config/revision_dates.csv (appends new USITC releases — manual review
#     of policy_effective_date may still be required)
#   - data/hts_archives/*.json  (downloads any missing HTS revisions)
#   - resources/usmca_product_shares_{2025,2026}*.csv (DataWeb pulls)
#   - data/timeseries/snapshot_*.rds (top-level production)
#   - output/daily/daily_overall.csv, daily_by_country.csv
#   - data/timeseries/{usmca_none,usmca_2024,usmca_monthly,usmca_h2avg}/
#       snapshot_*.rds (per-scenario, depends on top-level)
#
# Runs first so the export steps in sections 3a-3e pick up fresh files.
# Long-running (~60-90 min) and gated on DATAWEB_API_TOKEN. Aborts the
# whole script on the first failed step.

if (RUN_REFRESH_TRACKER) {
  log_msg("--- 0. Refresh tariff-rate-tracker outputs ---")

  if (!dir.exists(TRACKER_DIR)) {
    stop("tariff-rate-tracker not found at: ", TRACKER_DIR,
         "\n  Expected sibling directory alongside this repo.", call. = FALSE)
  }

  if (!nzchar(Sys.getenv("DATAWEB_API_TOKEN"))) {
    log_msg("  WARNING: DATAWEB_API_TOKEN not set -- USMCA DataWeb pulls",
            " will likely fail (free token from dataweb.usitc.gov)")
  }

  # Resolve the Rscript binary explicitly so we use the same R that's running
  # this script (avoids picking up a different R from PATH).
  rscript_bin <- file.path(R.home("bin"),
                            if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

  # Ordered refresh sequence. Each step is (label, script-relative-to-tracker, args...).
  # Order matters: revision dates and HTS JSON feed the build; DataWeb shares
  # feed the build; build_usmca_scenarios.R reads top-level snapshots.
  refresh_steps <- list(
    list(label = "01 scrape revision dates",
         args  = c("src/01_scrape_revision_dates.R")),
    list(label = "02 download HTS JSON",
         args  = c("src/02_download_hts.R")),
    list(label = "USMCA DataWeb shares (2025, monthly)",
         args  = c("src/download_usmca_dataweb.R", "--year", "2025", "--monthly")),
    list(label = "USMCA DataWeb shares (2026, monthly)",
         args  = c("src/download_usmca_dataweb.R", "--year", "2026", "--monthly")),
    list(label = "00 build_timeseries --full (snapshots + daily ETR)",
         args  = c("src/00_build_timeseries.R", "--full")),
    list(label = "build_usmca_scenarios (per-scenario subdirs)",
         args  = c("src/build_usmca_scenarios.R"))
  )

  old_wd <- getwd()
  setwd(TRACKER_DIR)
  on.exit(setwd(old_wd), add = TRUE)

  for (step in refresh_steps) {
    log_msg(sprintf("  >> %s", step$label))
    t0 <- Sys.time()
    status <- system2(rscript_bin, args = step$args)
    dt_min <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    if (!is.numeric(status) || status != 0) {
      stop(sprintf("Tracker refresh step failed: %s (exit %s)",
                   step$label, as.character(status)),
           call. = FALSE)
    }
    log_msg(sprintf("     done (%.1f min)", dt_min))
  }

  setwd(old_wd)
  log_msg("--- 0. Tracker refresh complete ---")
}


# ======================================================================
# 1. CENSUS API: HS2 x country x month
# ======================================================================

# Census API constants — hoisted out of the RUN_CENSUS conditional so that
# Section 2b (HS10 fallback) can reference YEAR_MONTHS_CENSUS and
# CENSUS_API_BASE even when Section 1 is skipped.
CENSUS_API_BASE <- "https://api.census.gov/data/timeseries/intltrade/imports/hs"

# Census releases data ~2 months after the reference month.
# Cap at 2 months before today to avoid timeouts on unreleased data.
latest_census_month <- seq(Sys.Date(), by = "-2 months", length.out = 2)[2]
YEAR_MONTHS_CENSUS <- format(
  seq(as.Date("2024-01-01"), latest_census_month, by = "month"), "%Y-%m"
)
HS2_CHAPTERS <- sprintf("%02d", setdiff(1:99, 77))


if (!RUN_CENSUS) {
  log_msg("--- 1. Census API: SKIPPED ---")
} else {

log_msg("--- 1. Census API (HS2 x country x month) ---")

# Pull all months. Caching disabled — R 4.5.2 segfaults on read.csv of
# the cached file (likely an R/compiler bug; file is valid ASCII CSV).
# Full pull of 26 months takes ~45 min; acceptable for a daily-run script.
months_to_pull <- YEAR_MONTHS_CENSUS
log_msg(sprintf("  Months to pull: %d (of %d total)",
                length(months_to_pull), length(YEAR_MONTHS_CENSUS)))

# Reusable HTTP handle — keeps TCP+TLS connection alive across requests.
# Eliminates ~1-2s handshake overhead per query.
census_handle <- handle("https://api.census.gov")

key_param <- if (nzchar(Sys.getenv("CENSUS_API_KEY"))) {
  paste0("&key=", Sys.getenv("CENSUS_API_KEY"))
} else {
  ""
}

#' Pull one HS2 chapter x month from Census API (with connection reuse).
pull_chapter_month <- function(hs2, year_month, max_retries = 2) {
  path <- paste0(
    "/data/timeseries/intltrade/imports/hs",
    "?get=CON_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,CTY_CODE",
    "&I_COMMODITY=", hs2,
    "&time=", year_month,
    "&COMM_LVL=HS2",
    key_param
  )

  for (attempt in seq_len(max_retries)) {
    resp <- tryCatch(
      GET(paste0("https://api.census.gov", path),
          handle = census_handle, timeout(15)),
      error = function(e) NULL
    )

    if (!is.null(resp) && status_code(resp) == 200) {
      txt <- content(resp, as = "text", encoding = "UTF-8")
      if (nchar(txt) < 10 || grepl("error", txt, ignore.case = TRUE)) return(NULL)

      parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
      if (is.null(parsed) || nrow(parsed) < 2) return(NULL)

      header <- parsed[1, ]
      row_data <- as.data.frame(parsed[-1, , drop = FALSE], stringsAsFactors = FALSE)
      cty_idx <- which(header == "CTY_CODE")[1]
      con_idx <- which(header == "CON_VAL_MO")[1]
      cal_idx <- which(header == "CAL_DUT_MO")[1]
      dut_idx <- which(header == "DUT_VAL_MO")[1]
      if (is.na(cty_idx)) return(NULL)

      return(tibble(
        hs2        = hs2,
        cty_code   = row_data[[cty_idx]],
        con_val_mo = as.numeric(row_data[[con_idx]]),
        cal_dut_mo = if (!is.na(cal_idx)) as.numeric(row_data[[cal_idx]]) else NA_real_,
        dut_val_mo = if (!is.na(dut_idx)) as.numeric(row_data[[dut_idx]]) else NA_real_,
        year_month = year_month
      ) |>
        filter(grepl("^\\d{4,5}$", cty_code)))
    } else if (attempt < max_retries) {
      wait <- if (!is.null(resp) && status_code(resp) == 429) 5 * attempt else 1
      Sys.sleep(wait)
    }
  }
  NULL
}

# Pull loop — only months not in cache
total_queries <- length(HS2_CHAPTERS) * length(months_to_pull)
new_chunks <- vector("list", total_queries)
idx <- 0; n_empty <- 0
t_start <- Sys.time()

for (ym in months_to_pull) {
  for (ch in HS2_CHAPTERS) {
    idx <- idx + 1
    if (idx %% 100 == 0 || idx == 1) {
      elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
      rate <- if (idx > 1) elapsed / (idx - 1) else NA
      eta <- if (!is.na(rate)) round((total_queries - idx) * rate / 60, 1) else NA
      log_msg(sprintf("  [%d/%d] %s ch%s (%.1fs/q, ~%.0fm left)",
                      idx, total_queries, ym, ch, rate, eta))
    }

    chunk <- pull_chapter_month(ch, ym)
    if (!is.null(chunk) && nrow(chunk) > 0) {
      new_chunks[[idx]] <- chunk
    } else {
      n_empty <- n_empty + 1
    }
    Sys.sleep(0.05)
  }
}

# Combine results (no cache — R 4.5.2 segfaults reading the cached CSV)
log_msg("  Combining query results...")
census_hs2 <- bind_rows(new_chunks)
rm(new_chunks); gc(verbose = FALSE)
log_msg(sprintf("  Total: %d rows from API", nrow(census_hs2)))

census_hs2 <- census_hs2 |>
  mutate(
    con_val_mo = as.numeric(con_val_mo),
    cal_dut_mo = as.numeric(cal_dut_mo),
    dut_val_mo = as.numeric(dut_val_mo),
    year  = as.integer(substr(year_month, 1, 4)),
    month = as.integer(substr(year_month, 6, 7)),
    date  = as.Date(paste0(year_month, "-01")),
    effective_rate = ifelse(con_val_mo > 0, cal_dut_mo / con_val_mo * 100, NA_real_)
  ) |>
  arrange(year_month, hs2, cty_code)

write_csv(census_hs2, file.path(RAW_DIR, "census_hs2_country_monthly.csv"))
log_msg(sprintf("  Saved: %d rows (%d empty queries)", nrow(census_hs2), n_empty))


} # end RUN_CENSUS


# ======================================================================
# 2. CENSUS IMDB: HS10 x country x month (rich detail + aggregated)
# ======================================================================

if (!RUN_IMDB) {
  log_msg("--- 2. Census IMDB: SKIPPED ---")
} else {

log_msg("--- 2. Census IMDB Bulk Files (HS10 x country x month) ---")

IMDB_URL_TEMPLATE <- "https://www.census.gov/trade/downloads/%s/Merch/im_m/IMDB%s.ZIP"

# Date range for IMDB
imdb_months <- seq(as.Date("2024-01-01"), Sys.Date(), by = "month")
YEAR_MONTHS_IMDB <- format(imdb_months, "%Y-%m")

# Rich fixed-width spec: includes preference code, district, rate provision
# (needed for FTA decomposition, max-district crosscheck) plus consumption
# quantity (qy1/qy2) and shipping weight by mode (air/vessel/containerized),
# for the value-misreporting decomposition (09_value_misreporting.R).
# NOTE on weight: Census reports weight ONLY for air + vessel modes; LAND
# shipments (truck/rail) carry zero weight, so ves+air systematically
# undercounts Canada/Mexico. cnt_wgt is a SUBSET of ves_wgt (not additive).
imdb_fwf_rich <- fwf_positions(
  start     = c( 1, 11, 15, 17, 21, 23, 27,  74,  89, 104,  44,  59, 239, 284, 329),
  end       = c(10, 14, 16, 18, 22, 26, 28,  88, 103, 118,  58,  73, 253, 298, 343),
  col_names = c("commodity", "cty_code", "cty_subco", "dist_entry",
                "rate_prov", "year", "month",
                "con_val_mo", "dut_val_mo", "cal_dut_mo",
                "con_qy1_mo", "con_qy2_mo", "air_wgt_mo", "ves_wgt_mo", "cnt_wgt_mo")
)

#' Download one IMDB ZIP. Returns path or NULL. Skips if already cached.
download_imdb_zip <- function(year_month) {
  yyyy <- substr(year_month, 1, 4)
  yymm <- paste0(substr(year_month, 3, 4), substr(year_month, 6, 7))
  url  <- sprintf(IMDB_URL_TEMPLATE, yyyy, yymm)
  zip_path <- file.path(IMDB_RAW, paste0("IMDB", yymm, ".ZIP"))

  if (file.exists(zip_path) && file.size(zip_path) > 1000) return(zip_path)

  for (attempt in 1:3) {
    ok <- tryCatch({
      download.file(url, zip_path, mode = "wb", quiet = TRUE)
      file.exists(zip_path) && file.size(zip_path) > 1000
    }, error = function(e) FALSE)
    if (ok) return(zip_path)
    Sys.sleep(2 * attempt)
  }
  if (file.exists(zip_path)) file.remove(zip_path)
  NULL
}

#' Read and sanitize the IMP_DETL fixed-width file from an IMDB ZIP.
read_imdb_detl <- function(zip_path) {
  zip_contents <- unzip(zip_path, list = TRUE)$Name
  detl_file <- grep("IMP_DETL\\.TXT$", zip_contents, value = TRUE, ignore.case = TRUE)
  if (length(detl_file) == 0) return(NULL)

  tmp_dir <- tempfile("imdb_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  unzip(zip_path, files = detl_file[1], exdir = tmp_dir)
  detl_path <- file.path(tmp_dir, detl_file[1])

  # Sanitize non-ASCII bytes then read — safe because all fields we use
  # (commodity, cty_code, values, code fields) are pure ASCII
  raw_bytes <- readBin(detl_path, what = "raw", n = file.size(detl_path))
  raw_bytes[raw_bytes > as.raw(0x7F)] <- as.raw(0x3F)
  clean <- file.path(tmp_dir, "CLEAN.TXT")
  writeBin(raw_bytes, clean)

  read_fwf(clean, col_positions = imdb_fwf_rich,
           col_types = cols(.default = col_character()), progress = FALSE)
}

#' Parse one IMDB ZIP into cleaned detail-level data.
#' Returns all rows with preference/district/rate-provision codes intact.
parse_imdb_detail <- function(zip_path) {
  raw_df <- read_imdb_detl(zip_path)
  if (is.null(raw_df)) return(NULL)

  raw_df |>
    mutate(
      commodity  = stri_pad_left(trimws(commodity), 10, "0"),
      cty_code   = trimws(cty_code),
      cty_subco  = trimws(cty_subco),
      dist_entry = trimws(dist_entry),
      rate_prov  = trimws(rate_prov),
      year       = as.integer(trimws(year)),
      month      = as.integer(trimws(month)),
      con_val_mo = as.numeric(trimws(con_val_mo)),
      dut_val_mo = as.numeric(trimws(dut_val_mo)),
      cal_dut_mo = as.numeric(trimws(cal_dut_mo)),
      con_qy1_mo = as.numeric(trimws(con_qy1_mo)),
      con_qy2_mo = as.numeric(trimws(con_qy2_mo)),
      air_wgt_mo = as.numeric(trimws(air_wgt_mo)),
      ves_wgt_mo = as.numeric(trimws(ves_wgt_mo)),
      cnt_wgt_mo = as.numeric(trimws(cnt_wgt_mo))
    ) |>
    # Keep quantity/weight-zero rows that still carry value: filter only on value.
    filter(grepl("^[0-9]+$", commodity), !is.na(year),
           coalesce(con_val_mo, 0) != 0) |>
    rename(hs10 = commodity) |>
    mutate(year_month = sprintf("%04d-%02d", year, month))
}

# Download + parse loop
imdb_detail_chunks <- vector("list", length(YEAR_MONTHS_IMDB))
names(imdb_detail_chunks) <- YEAR_MONTHS_IMDB
imdb_months_available <- character(0)

for (ym in YEAR_MONTHS_IMDB) {
  log_msg(sprintf("  %s ...", ym))

  zip_path <- download_imdb_zip(ym)
  if (is.null(zip_path)) { log_msg("    not available"); next }

  month_data <- tryCatch(parse_imdb_detail(zip_path), error = function(e) {
    log_msg(sprintf("    ERROR: %s", conditionMessage(e))); NULL
  })

  if (is.null(month_data) || nrow(month_data) == 0) { log_msg("    empty"); next }

  log_msg(sprintf("    %s rows, $%.0fB",
                  format(nrow(month_data), big.mark = ","),
                  sum(month_data$con_val_mo, na.rm = TRUE) / 1e9))
  imdb_detail_chunks[[ym]] <- month_data
  imdb_months_available <- c(imdb_months_available, ym)
  rm(month_data); gc(verbose = FALSE)
}

imdb_detail <- bind_rows(imdb_detail_chunks)
rm(imdb_detail_chunks); gc(verbose = FALSE)

# --- Output 1: Detail-level (for FTA decomposition, district crosscheck) ---
write_csv(
  imdb_detail |> select(hs10, cty_code, cty_subco, dist_entry, rate_prov,
                         year_month, con_val_mo, dut_val_mo, cal_dut_mo,
                         con_qy1_mo, con_qy2_mo, air_wgt_mo, ves_wgt_mo, cnt_wgt_mo),
  file.path(RAW_DIR, "imdb_detail.csv")
)
log_msg(sprintf("  Detail: %s rows, %d months",
                format(nrow(imdb_detail), big.mark = ","),
                n_distinct(imdb_detail$year_month)))

# --- Output 2: Aggregated to HS10 x country x month (for main pipeline) ---
# Quantities/weights are additive to this grain (the HTS unit-of-measure is
# fixed within an HS10). ship_wgt_mo = air + vessel (the only modes Census
# weighs); cnt_wgt is kept separately but NOT added (it is a subset of ves).
imdb_agg <- imdb_detail |>
  summarise(con_val_mo = sum(con_val_mo, na.rm = TRUE),
            cal_dut_mo = sum(cal_dut_mo, na.rm = TRUE),
            con_qy1_mo = sum(con_qy1_mo, na.rm = TRUE),
            con_qy2_mo = sum(con_qy2_mo, na.rm = TRUE),
            air_wgt_mo = sum(air_wgt_mo, na.rm = TRUE),
            ves_wgt_mo = sum(ves_wgt_mo, na.rm = TRUE),
            cnt_wgt_mo = sum(cnt_wgt_mo, na.rm = TRUE),
            .by = c(hs10, cty_code, year_month)) |>
  mutate(ship_wgt_mo = coalesce(air_wgt_mo, 0) + coalesce(ves_wgt_mo, 0))
write_csv(imdb_agg, file.path(RAW_DIR, "imdb_hs10_country_monthly.csv"))
log_msg(sprintf("  Aggregated: %s rows", format(nrow(imdb_agg), big.mark = ",")))
rm(imdb_detail, imdb_agg); gc(verbose = FALSE)


# ======================================================================
# 2b. CENSUS API HS10 FALLBACK (months not yet in IMDB)
# ======================================================================

# IMDB bulk files may lag Census API by a few weeks for recent months.
# Pull HS10 x country from API for any months in analysis window not covered.
imdb_gap_months <- setdiff(YEAR_MONTHS_CENSUS, imdb_months_available)
# Only try months with HS2 data (confirmed to exist at Census)
imdb_gap_months <- imdb_gap_months[imdb_gap_months >= "2025-01"]

if (length(imdb_gap_months) > 0) {
  log_msg(sprintf("--- 2b. Census API HS10 fallback (%d months) ---",
                  length(imdb_gap_months)))

  # Countries with meaningful trade volume — derive from the in-memory HS2
  # data if Section 1 ran, otherwise from the cached CSV. If neither is
  # available (default run with no prior --with-census), skip the fallback.
  hs2_csv <- file.path(RAW_DIR, "census_hs2_country_monthly.csv")
  hs2_for_top <- if (exists("census_hs2")) {
    census_hs2
  } else if (file.exists(hs2_csv)) {
    log_msg("  (loading cached census_hs2_country_monthly.csv for top-country filter)")
    read_csv(hs2_csv, show_col_types = FALSE)
  } else {
    NULL
  }

  if (is.null(hs2_for_top)) {
    log_msg("  WARNING: no HS2 data available (run with --with-census to enable",
            " the HS10 fallback). Skipping 2b.")
    top_countries <- character(0)
  } else {
    top_countries <- hs2_for_top |>
      filter(year >= 2025) |>
      summarise(total = sum(con_val_mo, na.rm = TRUE), .by = cty_code) |>
      filter(total > 1e8) |>
      pull(cty_code)
    log_msg(sprintf("  Querying %d countries x %d months at HS10",
                    length(top_countries), length(imdb_gap_months)))
  }

  pull_hs10_country_month <- function(cty, year_month, max_retries = 3) {
    key_param <- if (nzchar(Sys.getenv("CENSUS_API_KEY"))) {
      paste0("&key=", Sys.getenv("CENSUS_API_KEY"))
    } else {
      ""
    }
    url <- paste0(
      CENSUS_API_BASE,
      "?get=CON_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,I_COMMODITY",
      "&COMM_LVL=HS10",
      "&time=", year_month,
      "&CTY_CODE=", cty,
      key_param
    )

    for (attempt in seq_len(max_retries)) {
      resp <- tryCatch(GET(url, timeout(120)), error = function(e) NULL)
      if (!is.null(resp) && status_code(resp) == 200) {
        txt <- content(resp, as = "text", encoding = "UTF-8")
        if (nchar(txt) < 10 || grepl("error", txt, ignore.case = TRUE)) return(NULL)
        parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
        if (is.null(parsed) || nrow(parsed) < 2) return(NULL)

        header <- parsed[1, ]
        row_data <- as.data.frame(parsed[-1, , drop = FALSE], stringsAsFactors = FALSE)
        com_idx <- which(header == "I_COMMODITY")[1]
        con_idx <- which(header == "CON_VAL_MO")[1]
        cal_idx <- which(header == "CAL_DUT_MO")[1]
        dut_idx <- which(header == "DUT_VAL_MO")[1]
        if (is.na(com_idx)) return(NULL)

        return(tibble(
          hs10       = stri_pad_left(trimws(row_data[[com_idx]]), 10, "0"),
          cty_code   = cty,
          con_val_mo = as.numeric(row_data[[con_idx]]),
          cal_dut_mo = if (!is.na(cal_idx)) as.numeric(row_data[[cal_idx]]) else NA_real_,
          year_month = year_month
        ) |>
          filter(grepl("^\\d{10}$", hs10), coalesce(con_val_mo, 0) != 0))
      } else if (attempt < max_retries) {
        wait <- if (!is.null(resp) && status_code(resp) == 429) 5 * attempt else 0.5 * attempt
        Sys.sleep(wait)
      }
    }
    NULL
  }

  if (length(top_countries) == 0) {
    log_msg("  Skipping HS10 fallback queries (no top-country list).")
  } else {
    hs10_queries <- expand.grid(cty = top_countries, ym = imdb_gap_months,
                                 stringsAsFactors = FALSE)
    n_queries <- nrow(hs10_queries)
    hs10_chunks <- vector("list", n_queries)

    for (i in seq_len(n_queries)) {
      if (i %% 50 == 0 || i == 1)
        log_msg(sprintf("  [%d/%d] %s cty=%s", i, n_queries,
                        hs10_queries$ym[i], hs10_queries$cty[i]))
      hs10_chunks[[i]] <- pull_hs10_country_month(
        hs10_queries$cty[i], hs10_queries$ym[i])
      Sys.sleep(0.15)
    }

    hs10_fallback <- bind_rows(hs10_chunks)
    if (nrow(hs10_fallback) > 0) {
      write_csv(hs10_fallback, file.path(RAW_DIR, "census_hs10_fallback.csv"))
      log_msg(sprintf("  Saved fallback: %s rows, %d months",
                      format(nrow(hs10_fallback), big.mark = ","),
                      n_distinct(hs10_fallback$year_month)))
    } else {
      log_msg("  No fallback data needed (IMDB covers all months)")
    }
  }
} else {
  log_msg("--- 2b. Census API HS10 fallback: SKIPPED (IMDB complete) ---")
}

} # end RUN_IMDB


# ======================================================================
# 3. TARIFF-RATE-TRACKER: snapshots, daily ETRs, weights, revision dates
# ======================================================================

# The sibling checkout is required outright only when no shared publish is
# in play. With a publish, sections 3a/3c run from it and the sibling-only
# sections (3b/3d/3e) degrade to warnings below.
HAVE_SIBLING <- dir.exists(TRACKER_DIR)
if (!USE_SHARED_TRACKER && !HAVE_SIBLING) {
  stop("tariff-rate-tracker not found at: ", TRACKER_DIR,
       "\n  Expected sibling directory alongside this repo, or point",
       "\n  --tracker-data= / TRACKER_DATA_DIR at a shared tracker publish.",
       call. = FALSE)
}

if (!RUN_TRACKER) {
  log_msg("--- 3. Tariff-Rate-Tracker Exports: SKIPPED (3a-3c) ---")
} else {

log_msg("--- 3. Tariff-Rate-Tracker Exports ---")

# --- 3a. Snapshot rate CSVs (RDS -> CSV): top-level + per-scenario ---
#
# Top-level snapshots are the production (h2_average) rates. Per-scenario
# subdirs (usmca_none, usmca_2024, usmca_monthly, usmca_h2avg) contain the
# same schema built with different USMCA utilization assumptions. Written
# to data/raw/snapshot_rates/ (top-level) and data/raw/snapshot_rates/<scenario>/.

ts_dir <- file.path(TRACKER_DIR, "data", "timeseries")

# Columns to export from each snapshot
SNAP_COLS <- c("hts10", "country", "total_rate",
               "statutory_rate_232", "statutory_rate_ieepa_recip",
               "statutory_rate_ieepa_fent", "statutory_rate_301",
               "statutory_rate_s122", "statutory_rate_section_201",
               "statutory_rate_other", "statutory_base_rate",
               "metal_share", "steel_share", "aluminum_share",
               "copper_share", "usmca_eligible",
               "s232_usmca_eligible", "rate_232")

export_snapshots <- function(src_dir, dst_dir, label) {
  dir.create(dst_dir, showWarnings = FALSE, recursive = TRUE)
  files <- list.files(src_dir, pattern = "^snapshot_.*\\.rds$", full.names = TRUE)
  if (length(files) == 0) {
    log_msg(sprintf("    %s: no snapshots found in %s", label, src_dir))
    return(0L)
  }
  for (f in files) {
    rev_name <- gsub("^snapshot_|\\.rds$", "", basename(f))
    out_csv <- file.path(dst_dir, paste0("snapshot_", rev_name, ".csv"))
    snap <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(snap) || nrow(snap) == 0) { rm(snap); next }
    snap |>
      select(all_of(intersect(SNAP_COLS, colnames(snap)))) |>
      write_csv(out_csv)
    rm(snap)
  }
  gc(verbose = FALSE)
  length(files)
}

# Shared-publish variant: each actual/snapshots/valid_from=*/rates.parquet
# holds exactly one revision (carried in its `revision` column; verified
# unique across the 2026-06-06 vintage). Writes the same snapshot_<rev>.csv
# files as the RDS path and returns a revision -> effective-date map (from
# `valid_from`) that 3c uses to derive revision_dates.csv. Stale top-level
# CSVs are cleared first: a prior sibling-mode run may have written
# revisions the publish has since re-dated or dropped, and leftovers would
# corrupt the month-revision merge in Stata.
export_snapshots_shared <- function(snap_root, dst_dir) {
  parquets <- list.files(snap_root, pattern = "^rates\\.parquet$",
                         recursive = TRUE, full.names = TRUE)
  if (length(parquets) == 0) {
    stop("No rates.parquet files found under: ", snap_root,
         "\n  Bad or incomplete publish? Rerun with --no-shared-tracker to",
         " use the sibling checkout.", call. = FALSE)
  }
  dir.create(dst_dir, showWarnings = FALSE, recursive = TRUE)
  stale <- list.files(dst_dir, pattern = "^snapshot_.*\\.csv$",
                      full.names = TRUE)
  if (length(stale) > 0) {
    unlink(stale)
    log_msg(sprintf("    Cleared %d stale top-level snapshot CSVs",
                    length(stale)))
  }

  rev_map <- vector("list", length(parquets))
  for (i in seq_along(parquets)) {
    snap <- arrow::read_parquet(
      parquets[i],
      col_select = dplyr::any_of(c(SNAP_COLS, "revision", "valid_from")))
    rev <- unique(snap$revision)
    if (length(rev) != 1) {
      log_msg(sprintf("    WARNING: %s carries %d revisions -- skipping",
                      parquets[i], length(rev)))
      rm(snap); next
    }
    rev_map[[i]] <- data.frame(revision       = rev,
                               effective_date = format(min(snap$valid_from),
                                                        "%Y-%m-%d"),
                               stringsAsFactors = FALSE)
    snap |>
      select(all_of(intersect(SNAP_COLS, colnames(snap)))) |>
      write_csv(file.path(dst_dir, paste0("snapshot_", rev, ".csv")))
    rm(snap)
    gc(verbose = FALSE)
  }
  bind_rows(rev_map)
}

SHARED_REV_MAP <- NULL
if (USE_SHARED_TRACKER) {
  log_msg("  Exporting top-level snapshots from shared publish (parquet)...")
  SHARED_REV_MAP <- export_snapshots_shared(
    file.path(TRACKER_DATA_DIR, "actual", "snapshots"), SNAP_DIR)
  log_msg(sprintf("    -> %d top-level snapshot CSVs written",
                  nrow(SHARED_REV_MAP)))
} else {
  log_msg("  Exporting top-level snapshots (production, h2avg-equivalent)...")
  n_top <- export_snapshots(ts_dir, SNAP_DIR, "top-level")
  log_msg(sprintf("    -> %d top-level snapshot CSVs written", n_top))
}

# USMCA scenario snapshots are not in the shared publish (core-only builds);
# they always come from the sibling checkout when it is present.
SCENARIOS <- c("usmca_none", "usmca_2024", "usmca_monthly", "usmca_h2avg")
if (!HAVE_SIBLING) {
  log_msg("    WARNING: USMCA scenario snapshots are not in the shared")
  log_msg("    publish and no sibling checkout found -- skipping scenario")
  log_msg("    exports (see docs/shared_publish_extensions.md).")
} else {
  for (scn in SCENARIOS) {
    scn_src <- file.path(ts_dir, scn)
    if (!dir.exists(scn_src)) {
      log_msg(sprintf("    WARNING: scenario dir '%s' not found -- skipping",
                      scn))
      next
    }
    scn_dst <- file.path(SNAP_DIR, scn)
    log_msg(sprintf("  Exporting scenario: %s ...", scn))
    n_scn <- export_snapshots(scn_src, scn_dst, scn)
    log_msg(sprintf("    -> %d %s snapshot CSVs written", n_scn, scn))
  }
}

# --- 3b. 2024 import weights (RDS -> CSV) ---

log_msg("  Exporting 2024 import weights...")
existing_iw <- file.path(RAW_DIR, "import_weights_2024.csv")
LOCAL_IW_RDS <- here("data", "weights", "hs10_by_country_gtap_2024_con.rds")

# Resolve a weights RDS, in order: tracker local_paths.yaml ('import_weights'
# key, if present) -> tracker default weights location -> a previously
# self-built local copy (see the build fallback below).
iw_path <- NULL
if (HAVE_SIBLING) {
  lp_path <- file.path(TRACKER_DIR, "config", "local_paths.yaml")
  if (file.exists(lp_path)) {
    iw_rel <- read_yaml(lp_path)$import_weights
    if (!is.null(iw_rel) && length(iw_rel) > 0L && nzchar(iw_rel)) {
      cand <- normalizePath(file.path(TRACKER_DIR, iw_rel), mustWork = FALSE)
      if (file.exists(cand)) iw_path <- cand
    }
  }
  if (is.null(iw_path)) {
    cand <- file.path(TRACKER_DIR, "data", "weights",
                      "hs10_by_country_gtap_2024_con.rds")
    if (file.exists(cand)) iw_path <- cand
  }
}
if (is.null(iw_path) && file.exists(LOCAL_IW_RDS)) iw_path <- LOCAL_IW_RDS

# Self-build fallback: no prebuilt RDS anywhere (data/weights/ is gitignored
# in the tracker, so a fresh clone has none). Run the tracker's committed
# src/build_import_weights.R -- deterministic from public Census IMDB ZIPs,
# so the output matches the weights behind the tracker's own daily series
# (which the S1 = daily-ETR identity depends on). Reuses Section 2's ZIP
# cache via --raw-dir; any missing 2024 ZIPs are downloaded into it
# (--keep-zips so the cache survives). Output lands in this repo's
# data/weights/, never inside the tracker checkout.
if (is.null(iw_path) && HAVE_SIBLING) {
  build_script <- file.path(TRACKER_DIR, "src", "build_import_weights.R")
  if (file.exists(build_script)) {
    log_msg("    No weights RDS found -- building via the tracker's ",
            "build_import_weights.R")
    log_msg("    (downloads any missing 2024 IMDB ZIPs into data/imdb/; ",
            "~10-30 min)")
    dir.create(dirname(LOCAL_IW_RDS), showWarnings = FALSE, recursive = TRUE)
    rscript_bin <- file.path(R.home("bin"),
                             if (.Platform$OS.type == "windows") "Rscript.exe"
                             else "Rscript")
    old_wd <- getwd()
    setwd(TRACKER_DIR)  # script resolves its here() defaults from the tracker
    status <- tryCatch(
      system2(rscript_bin,
              args = c(shQuote(build_script),
                       "--year", "2024",
                       "--raw-dir", shQuote(IMDB_RAW),
                       "--crosswalk", shQuote(file.path(TRACKER_DIR,
                                                        "resources",
                                                        "hs10_gtap_crosswalk.csv")),
                       "--out", shQuote(LOCAL_IW_RDS),
                       "--keep-zips")),
      finally = setwd(old_wd))
    if (identical(status, 0L) && file.exists(LOCAL_IW_RDS)) {
      iw_path <- LOCAL_IW_RDS
      log_msg("    -> weights RDS built at data/weights/")
    } else {
      log_msg("    WARNING: weight build failed (exit status ", status, ")")
    }
  } else {
    log_msg("    WARNING: tracker checkout has no src/build_import_weights.R")
  }
}

if (!is.null(iw_path)) {
  readRDS(iw_path) |>
    summarise(imports = sum(imports, na.rm = TRUE),
              .by = c(hs10, cty_code)) |>
    filter(imports > 0) |>
    write_csv(existing_iw)
  log_msg("    -> import_weights_2024.csv written")
} else if (file.exists(existing_iw)) {
  # 2024 weights are fixed, so a previously exported CSV stays valid.
  log_msg("    NOTE: no weights RDS available; keeping existing ",
          "import_weights_2024.csv (2024 weights are fixed).")
} else {
  log_msg("    WARNING: no weights RDS and no existing import_weights_2024.csv.")
  log_msg("    Clone tariff-rate-tracker alongside this repo; this section will")
  log_msg("    then rebuild the weights from Census IMDB automatically.")
}

# --- 3c. Daily ETR CSVs (copy from tracker output) ---

log_msg("  Copying daily ETR files...")
if (USE_SHARED_TRACKER) {
  for (f in c("daily_overall.csv", "daily_by_country.csv")) {
    src <- file.path(TRACKER_DATA_DIR, "actual", "daily", f)
    if (file.exists(src)) {
      file.copy(src, file.path(RAW_DIR, f), overwrite = TRUE)
      log_msg(sprintf("    -> %s (shared publish)", f))
    } else {
      log_msg(sprintf("    WARNING: %s not found in shared publish", f))
    }
  }

  # Derive revision_dates.csv from the snapshot map built in 3a. The
  # publish's valid_from dating is authoritative for the rates being used:
  # it already carries the June 2026 re-dating, i.e. it equals the
  # coalesce(policy_effective_date, effective_date) that the sibling path
  # below computes. policy_event annotations come from the vendored lookup
  # in resources/ since the publish does not carry them.
  if (!is.null(SHARED_REV_MAP) && nrow(SHARED_REV_MAP) > 0) {
    pe_path <- here("resources", "revision_policy_events.csv")
    rd <- SHARED_REV_MAP
    if (file.exists(pe_path)) {
      pe <- read_csv(pe_path, col_types = cols(.default = col_character()),
                     progress = FALSE)
      rd <- left_join(rd, pe[, c("revision", "policy_event")],
                      by = "revision")
      n_unmatched <- sum(is.na(rd$policy_event) &
                         !(rd$revision %in% pe$revision))
      if (n_unmatched > 0) {
        log_msg(sprintf(paste0("    NOTE: %d publish revisions missing from ",
                               "resources/revision_policy_events.csv ",
                               "(policy_event left empty)"), n_unmatched))
      }
    } else {
      log_msg("    WARNING: resources/revision_policy_events.csv not found --")
      log_msg("    revision_dates.csv will have empty policy_event")
      rd$policy_event <- NA_character_
    }
    rd |>
      arrange(effective_date) |>
      write_csv(file.path(RAW_DIR, "revision_dates.csv"))
    log_msg(sprintf("    -> revision_dates.csv derived from publish (%d revisions)",
                    nrow(rd)))
  } else {
    log_msg("    WARNING: no snapshot map from 3a -- revision_dates.csv not written")
  }
} else {
  tracker_copies <- c(
    "output/daily/daily_overall.csv"    = "daily_overall.csv",
    "output/daily/daily_by_country.csv" = "daily_by_country.csv"
  )

  for (src_rel in names(tracker_copies)) {
    src <- file.path(TRACKER_DIR, src_rel)
    dst <- file.path(RAW_DIR, tracker_copies[[src_rel]])
    if (file.exists(src)) {
      file.copy(src, dst, overwrite = TRUE)
      log_msg(sprintf("    -> %s", tracker_copies[[src_rel]]))
    } else {
      log_msg(sprintf("    WARNING: %s not found", src_rel))
    }
  }

  # revision_dates.csv: swap policy_effective_date into effective_date at the
  # export boundary, mirroring the tracker's load_revision_dates(use_policy_dates
  # = TRUE) (June 2026 re-dating: effective_date = HTS publication date;
  # policy_effective_date = when the rates were actually in force). Downstream
  # consumers (Stata B3/D1, section 3e) then read corrected dates unchanged.
  # (In shared mode the derived dates above already equal this coalesce.)
  rd_src <- file.path(TRACKER_DIR, "config", "revision_dates.csv")
  if (file.exists(rd_src)) {
    rd <- read_csv(rd_src, col_types = cols(.default = col_character()))
    if ("policy_effective_date" %in% names(rd)) {
      n_swap <- sum(!is.na(rd$policy_effective_date) &
                    rd$policy_effective_date != rd$effective_date)
      rd <- rd |>
        mutate(effective_date = dplyr::coalesce(policy_effective_date,
                                                effective_date))
      log_msg(sprintf("    -> revision_dates.csv (policy dates swapped in for %d revisions)",
                      n_swap))
    } else {
      log_msg("    -> revision_dates.csv (no policy_effective_date column; copied as-is)")
    }
    write_csv(rd, file.path(RAW_DIR, "revision_dates.csv"))
  } else {
    log_msg("    WARNING: config/revision_dates.csv not found")
  }
}

} # end RUN_TRACKER


if (!RUN_COUNTERFACTUAL) {
  log_msg("--- 3d-3e. Counterfactual rate CSVs: SKIPPED ---")
} else {

# --- 3d. USMCA utilization shares (copy from tracker resources) ---

log_msg("  Copying USMCA utilization shares...")
if (!HAVE_SIBLING) {
  log_msg("    WARNING: USMCA share files are not in the shared publish and")
  log_msg("    no sibling checkout found -- skipping (see docs/shared_publish_extensions.md).")
} else {
  USMCA_DIR <- file.path(RAW_DIR, "usmca_shares")
  dir.create(USMCA_DIR, showWarnings = FALSE, recursive = TRUE)

  # 2024 annual shares (pre-tariff baseline)
  usmca_2024_src <- file.path(TRACKER_DIR, "resources", "usmca_product_shares_2024.csv")
  if (file.exists(usmca_2024_src)) {
    file.copy(usmca_2024_src, file.path(USMCA_DIR, basename(usmca_2024_src)), overwrite = TRUE)
    log_msg("    -> usmca_product_shares_2024.csv")
  } else {
    log_msg("    WARNING: usmca_product_shares_2024.csv not found in tracker")
  }

  # Monthly 2025 + available 2026 shares
  n_monthly <- 0L
  for (y in 2025:2026) {
    months_to_try <- if (y == 2025) 1:12 else 1:12
    for (m in months_to_try) {
      src <- file.path(TRACKER_DIR, "resources",
                       sprintf("usmca_product_shares_%d_%02d.csv", y, m))
      if (file.exists(src)) {
        file.copy(src, file.path(USMCA_DIR, basename(src)), overwrite = TRUE)
        n_monthly <- n_monthly + 1L
      }
    }
  }
  log_msg(sprintf("    -> %d monthly USMCA share files copied", n_monthly))

  # Carry forward latest available share file to fill gaps in analysis window.
  # Currently: Feb 2026 not yet available from DataWeb; carry forward Jan 2026.
  jan_2026 <- file.path(USMCA_DIR, "usmca_product_shares_2026_01.csv")
  feb_2026 <- file.path(USMCA_DIR, "usmca_product_shares_2026_02.csv")
  if (file.exists(jan_2026) && !file.exists(feb_2026)) {
    file.copy(jan_2026, feb_2026, overwrite = FALSE)
    log_msg("    NOTE: Carried forward Jan 2026 shares -> Feb 2026 (DataWeb not yet available)")
  }
} # end 3d sibling guard


# --- 3e. Counterfactual month-level rate CSVs (day-weighted scenarios) ---
#
# Produces HS10 x country x month total_rate panels for USMCA counterfactuals,
# for consumption by 02_counterfactual_ladder.do. Reads the tracker's per-
# scenario snapshots directly (built via src/build_usmca_scenarios.R — see
# data/timeseries/<scenario>/) and day-weights each scenario's per-revision
# rates to monthly using the same mrw logic as before.
#
# Previously this section reconstructed post-USMCA rates from statutory_rate_*
# components + share files; that logic now lives in the tracker and is
# replaced by a direct read of the scenario snapshots.
#
# Scenarios written:
#   counterfactual_usmca_none.csv      -- 0% utilization (upper bound)
#   counterfactual_usmca2024.csv       -- 2024 annual shares (pre-tariff baseline; S0)
#   counterfactual_usmca_monthly.csv   -- actual monthly 2025-2026 shares (explainer)
#   counterfactual_h2avg.csv           -- post-July 2025 average shares (tracker production
#                                         baseline; S1/S2 panel rate_h2avg). All four
#                                         use the same day-weighting machinery so the
#                                         scenarios are apples-to-apples comparable.

log_msg("  Building counterfactual rate CSVs (from scenario snapshots)...")

# Load revision dates for day-weighting. The 3c export already swaps
# policy_effective_date into effective_date; the coalesce here is an
# idempotent guard for --only-counterfactual runs against an older copy.
rev_dates <- read_csv(file.path(RAW_DIR, "revision_dates.csv"),
                       col_types = cols(.default = col_character()))
if ("policy_effective_date" %in% names(rev_dates)) {
  rev_dates <- rev_dates |>
    mutate(effective_date = dplyr::coalesce(policy_effective_date,
                                            effective_date))
}
rev_dates <- rev_dates |>
  mutate(effective_date = as.Date(effective_date)) |>
  filter(!is.na(effective_date)) |>
  arrange(effective_date) |>
  mutate(next_eff = lead(effective_date, default = as.Date("2099-12-31")))

# Analysis window (must match globals.do: $start_ym to $end_ym)
CF_START <- as.Date("2025-01-01")
CF_END   <- as.Date("2026-03-31")

# Build month x revision day-weights
month_starts <- seq.Date(CF_START, CF_END, by = "month")
mrw <- lapply(month_starts, function(m1) {
  m_end <- seq.Date(m1, by = "month", length.out = 2)[2] - 1L
  dim   <- as.integer(m_end - m1) + 1L
  ym    <- format(m1, "%Y-%m")

  hits <- rev_dates |>
    filter(effective_date <= m_end, next_eff > m1) |>
    mutate(
      o_start = pmax(effective_date, m1),
      o_end   = pmin(next_eff - 1L, m_end),
      days    = as.integer(o_end - o_start) + 1L,
      weight  = days / dim
    ) |>
    filter(days > 0)

  data.frame(year_month = ym, revision = hits$revision,
             days = hits$days, weight = hits$weight,
             stringsAsFactors = FALSE)
})
mrw <- bind_rows(mrw)
log_msg(sprintf("    %d month-revision pairs for day-weighting", nrow(mrw)))

scenario_outputs <- list(
  usmca_none    = "counterfactual_usmca_none.csv",
  usmca_2024    = "counterfactual_usmca2024.csv",
  usmca_monthly = "counterfactual_usmca_monthly.csv",
  usmca_h2avg   = "counterfactual_h2avg.csv"
)

# Census (hs10 x cty) universe, for expanding the tracker's 8-digit leaf HTS
# lines (kept since June 2026, padded to xxxxxxxx00) to the 10-digit stat
# suffixes Census actually reports. Without this the Stata exact-hs10 merges
# silently drop those lines (e.g. the Swiss watch headings).
imdb_agg_path <- file.path(RAW_DIR, "imdb_hs10_country_monthly.csv")
census_hs8_pairs <- if (file.exists(imdb_agg_path)) {
  read_csv(imdb_agg_path,
           col_types = cols(.default = col_character(),
                            con_val_mo = col_double(),
                            cal_dut_mo = col_double()),
           col_select = c("hs10", "cty_code"), progress = FALSE) |>
    distinct() |>
    mutate(hs8 = substr(hs10, 1, 8))
} else {
  log_msg("    NOTE: imdb_hs10_country_monthly.csv not found -- skipping 8-digit leaf expansion")
  NULL
}

build_counterfactual <- function(scenario, out_file) {
  scn_src <- file.path(TRACKER_DIR, "data", "timeseries", scenario)
  if (!dir.exists(scn_src)) {
    log_msg(sprintf("    WARNING: scenario dir %s not found -- skipping %s",
                    scn_src, scenario))
    return(invisible(NULL))
  }

  needed_revs <- unique(mrw$revision)
  parts <- list()

  for (rev in needed_revs) {
    f <- file.path(scn_src, paste0("snapshot_", rev, ".rds"))
    if (!file.exists(f)) {
      log_msg(sprintf("    WARNING: %s/snapshot_%s.rds missing", scenario, rev))
      next
    }
    snap <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(snap) || nrow(snap) == 0) next

    snap <- snap |> select(hts10, country, total_rate)

    rev_rows <- mrw[mrw$revision == rev, , drop = FALSE]
    for (j in seq_len(nrow(rev_rows))) {
      parts[[length(parts) + 1L]] <- snap |>
        mutate(year_month = rev_rows$year_month[j],
               wtd_rate   = total_rate * rev_rows$weight[j])
    }
    rm(snap); gc(verbose = FALSE)
  }

  if (length(parts) == 0) {
    log_msg(sprintf("    WARNING: no snapshots loaded for %s -- skipping write",
                    scenario))
    return(invisible(NULL))
  }

  result <- bind_rows(parts) |>
    summarise(total_rate = sum(wtd_rate),
              .by = c(hts10, country, year_month)) |>
    rename(cty_code = country)

  # Expand 8-digit leaf lines (...00) to the Census stat suffixes they cover,
  # so downstream exact-hs10 merges pick them up. Census codes that already
  # have their own exact row keep it (anti_join).
  if (!is.null(census_hs8_pairs)) {
    parents <- result |>
      filter(substr(hts10, 9, 10) == "00") |>
      mutate(hs8 = substr(hts10, 1, 8))
    expanded <- census_hs8_pairs |>
      inner_join(parents, by = c("hs8", "cty_code"),
                 relationship = "many-to-many") |>
      filter(hs10 != hts10) |>
      anti_join(result, by = c("hs10" = "hts10", "cty_code", "year_month")) |>
      transmute(hts10 = hs10, cty_code, year_month, total_rate)
    if (nrow(expanded) > 0) {
      result <- bind_rows(result, expanded)
      log_msg(sprintf("    + %s rows expanded from 8-digit leaf parents",
                      format(nrow(expanded), big.mark = ",")))
    }
    rm(parents, expanded)
  }

  write_csv(result, file.path(RAW_DIR, out_file))
  log_msg(sprintf("    -> %s: %d rows", out_file, nrow(result)))
  rm(parts, result); gc(verbose = FALSE)
  invisible(NULL)
}

# Scenario snapshots only exist in the sibling checkout (not published).
if (!HAVE_SIBLING) {
  log_msg("    WARNING: scenario snapshots require the sibling checkout --")
  log_msg("    skipping counterfactual rate builds (see docs/shared_publish_extensions.md).")
} else {
  for (scn in names(scenario_outputs)) {
    build_counterfactual(scn, scenario_outputs[[scn]])
  }
}


# --- 3f. Non-USMCA preference shares from IMDB ---
#
# Aggregates imdb_detail.csv to (hs10, cty_code, year_month) with per-channel
# share of cell imports. Output feeds section 3g. Uses classify_pref_channel
# (defined near top of file), mirroring Stata's classify_pref_channel.
#
# Output: imdb_other_pref_shares_monthly.csv with columns
#   hs10, cty_code, year_month, total_imports, share_usmca,
#   share_duty_free, share_korus, share_gsp_agoa, share_other_fta,
#   non_usmca_pref_share, total_share

log_msg("  Computing non-USMCA preference shares from IMDB detail...")

imdb_detail_path <- file.path(RAW_DIR, "imdb_detail.csv")
shares_built <- FALSE

if (!file.exists(imdb_detail_path)) {
  log_msg("    WARNING: imdb_detail.csv not found -- skipping 3f and 3g")
  log_msg("    (Run section 2 first to produce imdb_detail.csv)")
} else {
  # Read only the columns we need (drops dist_entry, dut_val_mo, cal_dut_mo).
  # Saves ~500 MB peak memory on the 19M-row file.
  imdb_detail <- read_csv(imdb_detail_path,
                           col_types = cols(.default = col_character(),
                                            con_val_mo = col_double()),
                           col_select = c("hs10", "cty_code", "cty_subco",
                                          "rate_prov", "year_month",
                                          "con_val_mo"),
                           progress = FALSE)
  log_msg(sprintf("    Loaded %d entry rows from imdb_detail.csv",
                  nrow(imdb_detail)))

  # Filter to analysis window FIRST (drops 2024 rows, freeing ~50% of memory),
  # then classify pref_channel. The IMDB detail CSV already carries year_month
  # as "YYYY-MM" and hs10 (not commodity).
  imdb_detail <- imdb_detail |>
    filter(year_month >= "2025-01" & year_month <= "2026-03")
  gc(verbose = FALSE)
  imdb_detail <- imdb_detail |>
    mutate(pref_channel = classify_pref_channel(cty_subco, rate_prov,
                                                cty_code))

  log_msg(sprintf("    %d entries in analysis window", nrow(imdb_detail)))

  # --- Split duty_free into Annex-II vs pure-MFN-zero (upgrade 1) ---------------
  # The duty_free channel (rate_prov 10/18/19) is composite. Products on the
  # tracker's IEEPA-exempt list (Annex II / ITA / Ch98 / Berman, claimed via
  # 9903.01.32) carve out the IEEPA *reciprocal* layer; pure MFN-zero duty_free
  # entries do NOT. Splitting here lets section 3g apply the reciprocal exemption
  # (delta_recip) only to the on-list (annex) share, removing the over-count
  # flagged in docs/six_tier_framework_plan.md sec. 6.7. The base exemption is
  # unaffected (both sub-channels still exempt the MFN base).
  exempt_file <- file.path(TRACKER_DIR, "resources", "ieepa_exempt_products.csv")
  if (file.exists(exempt_file)) {
    exempt_hs10 <- read_csv(exempt_file,
                            col_types = cols(hts10 = col_character()),
                            progress = FALSE)$hts10
    imdb_detail <- imdb_detail |>
      mutate(pref_channel = if_else(
        pref_channel == "duty_free",
        if_else(hs10 %in% exempt_hs10, "duty_free_annex", "duty_free_mfn"),
        pref_channel))
    log_msg(sprintf("    Split duty_free via %d IEEPA-exempt HTS10 codes",
                    length(exempt_hs10)))
  } else {
    # Fallback preserves prior behaviour (all duty_free exempts reciprocal).
    log_msg("    WARNING: ieepa_exempt_products.csv not found at ", exempt_file,
            "; treating all duty_free as Annex-II (prior behaviour).")
    imdb_detail <- imdb_detail |>
      mutate(pref_channel = if_else(pref_channel == "duty_free",
                                    "duty_free_annex", pref_channel))
  }

  # Cell totals (all channels, including non-preference)
  cell_totals <- imdb_detail |>
    summarise(total_imports = sum(con_val_mo, na.rm = TRUE),
              .by = c(hs10, cty_code, year_month))

  # Per-channel imports (one column per preference channel via repeated joins;
  # avoids tidyr dependency).
  pref_channels <- c("usmca", "duty_free_annex", "duty_free_mfn",
                     "korus", "gsp_agoa", "other_fta")
  imdb_shares <- cell_totals
  for (ch in pref_channels) {
    ch_imports <- imdb_detail |>
      filter(pref_channel == ch) |>
      summarise("imports_{ch}" := sum(con_val_mo, na.rm = TRUE),
                .by = c(hs10, cty_code, year_month))
    imdb_shares <- left_join(imdb_shares, ch_imports,
                              by = c("hs10", "cty_code", "year_month"))
  }

  # NA -> 0 for cells where a channel had no entries; compute shares
  imdb_shares <- imdb_shares |>
    mutate(across(starts_with("imports_"), ~ coalesce(., 0)),
           share_usmca      = if_else(total_imports > 0,
                                       imports_usmca / total_imports, 0),
           share_duty_free_annex = if_else(total_imports > 0,
                                       imports_duty_free_annex / total_imports, 0),
           share_duty_free_mfn   = if_else(total_imports > 0,
                                       imports_duty_free_mfn / total_imports, 0),
           # backward-compatible composite (annex + mfn = old duty_free)
           share_duty_free  = share_duty_free_annex + share_duty_free_mfn,
           share_korus      = if_else(total_imports > 0,
                                       imports_korus / total_imports, 0),
           share_gsp_agoa   = if_else(total_imports > 0,
                                       imports_gsp_agoa / total_imports, 0),
           share_other_fta  = if_else(total_imports > 0,
                                       imports_other_fta / total_imports, 0),
           non_usmca_pref_share = share_duty_free + share_korus +
                                   share_gsp_agoa + share_other_fta,
           total_share = share_usmca + non_usmca_pref_share) |>
    select(hs10, cty_code, year_month, total_imports,
           share_usmca, share_duty_free,
           share_duty_free_annex, share_duty_free_mfn, share_korus,
           share_gsp_agoa, share_other_fta,
           non_usmca_pref_share, total_share)

  # Sanity check: shares should sum to <= 1 by mutual exclusivity
  n_violations <- sum(imdb_shares$total_share > 1.0001, na.rm = TRUE)
  if (n_violations > 0) {
    max_share <- max(imdb_shares$total_share, na.rm = TRUE)
    log_msg(sprintf("    WARNING: %d cells have total preference share > 1 (max %.4f)",
                    n_violations, max_share))
  }

  write_csv(imdb_shares,
             file.path(RAW_DIR, "imdb_other_pref_shares_monthly.csv"))
  log_msg(sprintf("    -> imdb_other_pref_shares_monthly.csv: %d rows",
                  nrow(imdb_shares)))

  rm(imdb_detail, cell_totals); gc(verbose = FALSE)
  shares_built <- TRUE
}


# --- 3g. S2 -> S3 preference-delta file ---
#
# Writes the additional rate reduction from S2 (USMCA monthly) to S3 (USMCA +
# all-other preferences). Per cell:
#   delta_base  = (s_duty_free + s_korus + s_gsp + s_other_fta) * base_rate_pre
#   delta_recip = s_duty_free * rate_ieepa_recip_pre
#
# Pre-preference base and recip components come from top-level snapshots
# (statutory_base_rate, statutory_rate_ieepa_recip), day-weighted to monthly.
#
# Schema is a delta (not a full counterfactual rate): only cells with positive
# non-USMCA preference share are written. Stata 05 merges this onto S2 and
# computes S3 = rate_usmca_monthly - delta_base - delta_recip (S3 = S2 for
# cells absent from this file). This avoids materializing a 66M-row full
# counterfactual that would mostly duplicate S2.
#
# See docs/six_tier_framework_plan.md §6.6 for derivation.
#
# Output: counterfactual_other_pref_delta_monthly.csv with columns
#   hs10, cty_code, year_month, delta_base, delta_recip

log_msg("  Building S2 -> S3 preference-delta file...")

shares_path <- file.path(RAW_DIR, "imdb_other_pref_shares_monthly.csv")

if (!shares_built && !file.exists(shares_path)) {
  log_msg("    SKIPPED: 3f did not produce shares file")
} else {
  shares <- read_csv(shares_path,
                      col_types = cols(.default = col_character(),
                                       total_imports = col_double(),
                                       share_usmca = col_double(),
                                       share_duty_free = col_double(),
                                       share_duty_free_annex = col_double(),
                                       share_duty_free_mfn = col_double(),
                                       share_korus = col_double(),
                                       share_gsp_agoa = col_double(),
                                       share_other_fta = col_double(),
                                       non_usmca_pref_share = col_double(),
                                       total_share = col_double()),
                      progress = FALSE) |>
    filter(non_usmca_pref_share > 0) |>
    select(hs10, cty_code, year_month, share_duty_free,
           share_duty_free_annex, share_korus,
           share_gsp_agoa, share_other_fta, non_usmca_pref_share)
  log_msg(sprintf("    Share-cells with positive non-USMCA pref: %d rows",
                  nrow(shares)))

  # Components: per-ym, semi-join snapshot rows to share-cells before
  # accumulating. Bounds memory at ~one snapshot's worth + the share-cell
  # subset (~150K rows / ym).
  log_msg("    Day-weighting pre-preference base + recip (per-ym streaming)...")

  ym_strs <- sort(unique(shares$year_month))
  delta_parts <- list()

  for (ym in ym_strs) {
    ym_share_keys <- shares |>
      filter(year_month == ym) |>
      select(hs10, cty_code) |>
      distinct()

    ym_revs <- mrw[mrw$year_month == ym, , drop = FALSE]
    if (nrow(ym_revs) == 0L) {
      log_msg(sprintf("    WARNING: %s has no contributing revisions", ym))
      next
    }

    ym_contribs <- list()
    for (j in seq_len(nrow(ym_revs))) {
      rev    <- ym_revs$revision[j]
      weight <- ym_revs$weight[j]
      f <- file.path(SNAP_DIR, paste0("snapshot_", rev, ".csv"))
      if (!file.exists(f)) {
        log_msg(sprintf("    WARNING: %s not found", f))
        next
      }
      snap <- read_csv(f,
                        col_types = cols(.default = col_character(),
                                         statutory_base_rate = col_double(),
                                         statutory_rate_ieepa_recip = col_double()),
                        col_select = c("hts10", "country",
                                       "statutory_base_rate",
                                       "statutory_rate_ieepa_recip"),
                        progress = FALSE) |>
        rename(hs10 = hts10, cty_code = country)

      ym_contribs[[j]] <- snap |>
        semi_join(ym_share_keys, by = c("hs10", "cty_code")) |>
        transmute(hs10, cty_code,
                  wtd_base  = statutory_base_rate * weight,
                  wtd_recip = statutory_rate_ieepa_recip * weight)
      rm(snap); gc(verbose = FALSE)
    }

    if (length(ym_contribs) > 0L) {
      delta_parts[[ym]] <- bind_rows(ym_contribs) |>
        summarise(base_rate  = sum(wtd_base, na.rm = TRUE),
                  recip_rate = sum(wtd_recip, na.rm = TRUE),
                  .by = c(hs10, cty_code)) |>
        mutate(year_month = ym)
    }
    rm(ym_contribs); gc(verbose = FALSE)
    log_msg(sprintf("    %s: %d component rows",
                    ym, if (is.null(delta_parts[[ym]])) 0L else nrow(delta_parts[[ym]])))
  }

  components <- bind_rows(delta_parts)
  rm(delta_parts); gc(verbose = FALSE)
  log_msg(sprintf("    Total component rows: %d", nrow(components)))

  # Join shares + components, compute deltas, write.
  result <- shares |>
    left_join(components,
              by = c("hs10", "cty_code", "year_month")) |>
    mutate(base_rate   = coalesce(base_rate, 0),
           recip_rate  = coalesce(recip_rate, 0),
           other_pref_total = share_duty_free + share_korus +
                              share_gsp_agoa + share_other_fta,
           delta_base  = other_pref_total * base_rate,
           # Upgrade 1: reciprocal exemption only on the Annex-II share (not
           # pure MFN-zero duty_free), per applicability matrix sec. 6.3/6.7.
           delta_recip = share_duty_free_annex * recip_rate) |>
    filter(delta_base + delta_recip > 0) |>
    select(hs10, cty_code, year_month, delta_base, delta_recip)

  write_csv(result,
             file.path(RAW_DIR, "counterfactual_other_pref_delta_monthly.csv"))
  log_msg(sprintf("    -> counterfactual_other_pref_delta_monthly.csv: %d rows",
                  nrow(result)))
  log_msg(sprintf("       Total delta_base:  %.2f sum",
                  sum(result$delta_base, na.rm = TRUE)))
  log_msg(sprintf("       Total delta_recip: %.2f sum",
                  sum(result$delta_recip, na.rm = TRUE)))

  rm(shares, components, result); gc(verbose = FALSE)
}

} # end RUN_COUNTERFACTUAL


# ======================================================================
# 4. TARIFF-IMPACT-TRACKER: Treasury revenue
# ======================================================================

if (!RUN_IMPACTS) {
  log_msg("--- 4. Tariff-Impact-Tracker: SKIPPED ---")
} else {

log_msg("--- 4. Tariff-Impact-Tracker (Revenue) ---")

if (!dir.exists(IMPACTS_DIR)) {
  stop("tariff-impact-tracker not found at: ", IMPACTS_DIR,
       "\n  Expected sibling directory alongside this repo.", call. = FALSE)
}

rev_src <- file.path(IMPACTS_DIR, "output", "tariff_revenue.csv")
if (file.exists(rev_src)) {
  file.copy(rev_src, file.path(RAW_DIR, "tariff_revenue.csv"), overwrite = TRUE)
  log_msg("  -> tariff_revenue.csv copied")
} else {
  log_msg("  WARNING: tariff_revenue.csv not found")
}

} # end RUN_IMPACTS


# ======================================================================
# SUMMARY
# ======================================================================

log_msg("=======================================================")
log_msg("  Raw data assembly complete")
log_msg("  Finished: ", format(Sys.time()))
log_msg("  Output: ", RAW_DIR)
log_msg("=======================================================")

raw_files <- list.files(RAW_DIR, recursive = TRUE)
log_msg(sprintf("  %d files in data/raw/", length(raw_files)))
