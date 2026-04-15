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
#   3. tariff-rate-tracker  -- snapshot rates (RDS -> CSV), daily ETRs,
#                              revision dates, import weights
#   4. tariff-impact-tracker -- Treasury revenue (actual ETR)
#
# Usage:
#   Rscript R/00_pull_raw_data.R
#
# Output (all in data/raw/):
#   census_hs2_country_monthly.csv      -- HS2 x country x month
#   imdb_hs10_country_monthly.csv       -- HS10 x country x month
#   snapshot_rates/snapshot_{rev}.csv   -- statutory rates per revision
#   import_weights_2024.csv             -- 2024 annual import weights
#   daily_overall.csv                   -- daily statutory ETR
#   daily_by_country.csv                -- daily ETR by country
#   revision_dates.csv                  -- revision effective dates
#   tariff_revenue.csv                  -- actual monthly ETR
# ==============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(here)
library(stringi)

here::i_am("code/R/00_pull_raw_data.R")

# --- Paths ---
RAW_DIR     <- here("data", "raw")
IMDB_DIR    <- here("data", "imdb")
IMDB_RAW    <- file.path(IMDB_DIR, "raw")
SNAP_DIR    <- file.path(RAW_DIR, "snapshot_rates")
TRACKER_DIR <- file.path(dirname(here()), "tariff-rate-tracker")
IMPACTS_DIR <- file.path(dirname(here()), "tariff-impact-tracker")

dir.create(RAW_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(IMDB_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(IMDB_RAW, showWarnings = FALSE, recursive = TRUE)
dir.create(SNAP_DIR, showWarnings = FALSE, recursive = TRUE)

cat("=======================================================\n")
cat("  Raw Data Assembly for tariff-etr-eval\n")
cat("  Started:", format(Sys.time()), "\n")
cat("=======================================================\n\n")


# ======================================================================
# 1. CENSUS API: HS2 x country x month
# ======================================================================

cat("--- 1. Census API (HS2 x country x month) ---\n\n")

CENSUS_API_BASE <- "https://api.census.gov/data/timeseries/intltrade/imports/hs"

# Coverage: 2024 baseline + 2025 escalation + 2026 as available
YEAR_MONTHS_CENSUS <- c(
  paste0("2024-", sprintf("%02d", 1:12)),
  paste0("2025-", sprintf("%02d", 1:12)),
  paste0("2026-", sprintf("%02d", 1:12))
)
HS2_CHAPTERS <- sprintf("%02d", setdiff(1:99, 77))

#' Pull one HS2 chapter x month from Census API.
pull_chapter_month <- function(hs2, year_month, max_retries = 3) {
  url <- paste0(
    CENSUS_API_BASE,
    "?get=CON_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,CTY_CODE",
    "&I_COMMODITY=", hs2,
    "&time=", year_month,
    "&COMM_LVL=HS2"
  )

  for (attempt in seq_len(max_retries)) {
    resp <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)

    if (!is.null(resp) && status_code(resp) == 200) {
      txt <- content(resp, as = "text", encoding = "UTF-8")
      if (nchar(txt) < 10 || grepl("error", txt, ignore.case = TRUE)) return(NULL)

      parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
      if (is.null(parsed) || nrow(parsed) < 2) return(NULL)

      # First row is header
      header <- parsed[1, ]
      df <- as.data.frame(parsed[-1, , drop = FALSE], stringsAsFactors = FALSE)
      cty_idx <- which(header == "CTY_CODE")[1]
      con_idx <- which(header == "CON_VAL_MO")[1]
      cal_idx <- which(header == "CAL_DUT_MO")[1]
      dut_idx <- which(header == "DUT_VAL_MO")[1]
      if (is.na(cty_idx)) return(NULL)

      return(tibble(
        hs2        = hs2,
        cty_code   = df[[cty_idx]],
        con_val_mo = as.numeric(df[[con_idx]]),
        cal_dut_mo = if (!is.na(cal_idx)) as.numeric(df[[cal_idx]]) else NA_real_,
        dut_val_mo = if (!is.na(dut_idx)) as.numeric(df[[dut_idx]]) else NA_real_,
        year_month = year_month
      ) %>%
        filter(grepl("^[0-9]+$", cty_code), as.integer(cty_code) >= 1000))
    } else if (attempt < max_retries) {
      Sys.sleep(0.5 * attempt)
    }
  }
  NULL
}

# Pull loop
all_results <- list()
total_queries <- length(HS2_CHAPTERS) * length(YEAR_MONTHS_CENSUS)
idx <- 0; empty <- 0

for (ym in YEAR_MONTHS_CENSUS) {
  for (ch in HS2_CHAPTERS) {
    idx <- idx + 1
    if (idx %% 200 == 0 || idx == 1)
      cat(sprintf("  [%d/%d] %s ch%s\n", idx, total_queries, ym, ch))

    result <- pull_chapter_month(ch, ym)
    if (!is.null(result) && nrow(result) > 0) {
      all_results[[length(all_results) + 1]] <- result
    } else {
      empty <- empty + 1
    }
    Sys.sleep(0.1)
  }
}

census_hs2 <- bind_rows(all_results) %>%
  mutate(
    year  = as.integer(substr(year_month, 1, 4)),
    month = as.integer(substr(year_month, 6, 7)),
    date  = as.Date(paste0(year_month, "-01")),
    effective_rate = cal_dut_mo / con_val_mo * 100
  ) %>%
  arrange(year_month, hs2, cty_code)

write_csv(census_hs2, file.path(RAW_DIR, "census_hs2_country_monthly.csv"))
cat(sprintf("  Saved: %d rows (%d empty queries)\n\n", nrow(census_hs2), empty))


# ======================================================================
# 2. CENSUS IMDB: HS10 x country x month
# ======================================================================

cat("--- 2. Census IMDB Bulk Files (HS10 x country x month) ---\n\n")

IMDB_URL_TEMPLATE <- "https://www.census.gov/trade/downloads/%s/Merch/im_m/IMDB%s.ZIP"

# Date range for IMDB
imdb_months <- seq(as.Date("2024-01-01"), Sys.Date(), by = "month")
YEAR_MONTHS_IMDB <- format(imdb_months, "%Y-%m")

# Fixed-width positions (from Census IMDB layout)
imdb_fwf <- fwf_positions(
  start     = c( 1, 11, 23, 27,  74, 104),
  end       = c(10, 14, 26, 28,  88, 118),
  col_names = c("commodity", "cty_code", "year", "month", "con_val_mo", "cal_dut_mo")
)

#' Download one IMDB ZIP. Returns path or NULL.
download_imdb_zip <- function(year_month) {
  yyyy <- substr(year_month, 1, 4)
  yymm <- paste0(substr(year_month, 3, 4), substr(year_month, 6, 7))
  url  <- sprintf(IMDB_URL_TEMPLATE, yyyy, yymm)
  zip_path <- file.path(IMDB_RAW, paste0("IMDB", yymm, ".ZIP"))

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

#' Parse one ZIP to HS10 x country aggregates.
parse_imdb_zip <- function(zip_path) {
  zip_contents <- unzip(zip_path, list = TRUE)$Name
  detl_file <- grep("IMP_DETL\\.TXT$", zip_contents, value = TRUE, ignore.case = TRUE)
  if (length(detl_file) == 0) return(NULL)

  tmp_dir <- tempfile("imdb_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  unzip(zip_path, files = detl_file[1], exdir = tmp_dir)
  detl_path <- file.path(tmp_dir, detl_file[1])

  # Read fixed-width with latin1 encoding (tolerates non-UTF-8 bytes)
  df <- tryCatch(
    read_fwf(detl_path, col_positions = imdb_fwf,
             col_types = cols(.default = col_character()),
             locale = locale(encoding = "latin1"), progress = FALSE),
    error = function(e) {
      # Fallback: sanitize non-ASCII bytes then re-read
      raw <- readBin(detl_path, what = "raw", n = file.size(detl_path))
      raw[raw > as.raw(0x7F)] <- as.raw(0x3F)
      clean <- file.path(tmp_dir, "CLEAN.TXT")
      writeBin(raw, clean)
      read_fwf(clean, col_positions = imdb_fwf,
               col_types = cols(.default = col_character()), progress = FALSE)
    }
  )

  # Aggregate to HS10 x country x month
  df %>%
    mutate(
      commodity  = stri_pad_left(trimws(commodity), 10, "0"),
      cty_code   = trimws(cty_code),
      year       = as.integer(trimws(year)),
      month      = as.integer(trimws(month)),
      con_val_mo = as.numeric(trimws(con_val_mo)),
      cal_dut_mo = as.numeric(trimws(cal_dut_mo))
    ) %>%
    filter(grepl("^[0-9]+$", commodity), !is.na(year),
           coalesce(con_val_mo, 0) != 0) %>%
    group_by(commodity, cty_code, year, month) %>%
    summarize(con_val_mo = sum(con_val_mo, na.rm = TRUE),
              cal_dut_mo = sum(cal_dut_mo, na.rm = TRUE),
              .groups = "drop") %>%
    rename(hs10 = commodity) %>%
    mutate(year_month = sprintf("%04d-%02d", year, month))
}

# Download + parse loop
all_imdb <- list()
for (ym in YEAR_MONTHS_IMDB) {
  cat(sprintf("  %s ... ", ym))

  zip_path <- download_imdb_zip(ym)
  if (is.null(zip_path)) { cat("not available\n"); next }

  parsed <- tryCatch(parse_imdb_zip(zip_path), error = function(e) {
    cat(sprintf("ERROR: %s\n", conditionMessage(e))); NULL
  })

  if (is.null(parsed) || nrow(parsed) == 0) { cat("empty\n"); next }

  cat(sprintf("%s pairs, $%.0fB\n",
              format(nrow(parsed), big.mark = ","),
              sum(parsed$con_val_mo, na.rm = TRUE) / 1e9))
  all_imdb[[ym]] <- parsed
  rm(parsed); gc(verbose = FALSE)
}

imdb_combined <- bind_rows(all_imdb)
write_csv(
  imdb_combined %>% select(hs10, cty_code, year_month, con_val_mo, cal_dut_mo),
  file.path(RAW_DIR, "imdb_hs10_country_monthly.csv")
)
cat(sprintf("  Saved: %s rows, %d months\n\n",
            format(nrow(imdb_combined), big.mark = ","),
            n_distinct(imdb_combined$year_month)))


# ======================================================================
# 3. TARIFF-RATE-TRACKER: snapshots, daily ETRs, weights, revision dates
# ======================================================================

cat("--- 3. Tariff-Rate-Tracker Exports ---\n\n")

if (!dir.exists(TRACKER_DIR)) stop("tariff-rate-tracker not found at: ", TRACKER_DIR)

# --- 3a. Snapshot rate CSVs (RDS -> CSV) ---

ts_dir <- file.path(TRACKER_DIR, "data", "timeseries")
snap_files <- list.files(ts_dir, pattern = "^snapshot_.*\\.rds$", full.names = TRUE)
cat(sprintf("  Exporting %d snapshot RDS files...\n", length(snap_files)))

# Columns to export from each snapshot
SNAP_COLS <- c("hts10", "country", "total_rate",
               "statutory_rate_232", "statutory_rate_ieepa_recip",
               "statutory_rate_ieepa_fent", "statutory_rate_301",
               "statutory_rate_s122", "statutory_rate_section_201",
               "statutory_base_rate", "metal_share",
               "steel_share", "aluminum_share", "copper_share",
               "usmca_eligible", "rate_232")

for (f in snap_files) {
  rev_name <- gsub("^snapshot_|\\.rds$", "", basename(f))
  out_csv <- file.path(SNAP_DIR, paste0("snapshot_", rev_name, ".csv"))

  snap <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(snap) || nrow(snap) == 0) next

  snap %>%
    select(all_of(intersect(SNAP_COLS, colnames(snap)))) %>%
    write_csv(out_csv)
}
cat(sprintf("    -> %d snapshot CSVs written\n", length(snap_files)))

# --- 3b. 2024 import weights (RDS -> CSV) ---

cat("  Exporting 2024 import weights...\n")
local_paths <- yaml::read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)

if (file.exists(iw_path)) {
  readRDS(iw_path) %>%
    group_by(hs10, cty_code) %>%
    summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
    filter(imports > 0) %>%
    write_csv(file.path(RAW_DIR, "import_weights_2024.csv"))
  cat("    -> import_weights_2024.csv written\n")
} else {
  cat("    WARNING: import weights RDS not found at:", iw_path, "\n")
}

# --- 3c. Daily ETR CSVs (copy from tracker output) ---

cat("  Copying daily ETR files...\n")
tracker_copies <- c(
  "output/daily/daily_overall.csv"    = "daily_overall.csv",
  "output/daily/daily_by_country.csv" = "daily_by_country.csv",
  "config/revision_dates.csv"         = "revision_dates.csv"
)

for (src_rel in names(tracker_copies)) {
  src <- file.path(TRACKER_DIR, src_rel)
  dst <- file.path(RAW_DIR, tracker_copies[[src_rel]])
  if (file.exists(src)) {
    file.copy(src, dst, overwrite = TRUE)
    cat(sprintf("    -> %s\n", tracker_copies[[src_rel]]))
  } else {
    cat(sprintf("    WARNING: %s not found\n", src_rel))
  }
}


# ======================================================================
# 4. TARIFF-IMPACT-TRACKER: Treasury revenue
# ======================================================================

cat("\n--- 4. Tariff-Impact-Tracker (Revenue) ---\n\n")

if (!dir.exists(IMPACTS_DIR)) stop("tariff-impact-tracker not found at: ", IMPACTS_DIR)

rev_src <- file.path(IMPACTS_DIR, "output", "tariff_revenue.csv")
if (file.exists(rev_src)) {
  file.copy(rev_src, file.path(RAW_DIR, "tariff_revenue.csv"), overwrite = TRUE)
  cat("  -> tariff_revenue.csv copied\n")
} else {
  cat("  WARNING: tariff_revenue.csv not found\n")
}


# ======================================================================
# SUMMARY
# ======================================================================

cat("\n=======================================================\n")
cat("  Raw data assembly complete\n")
cat("  Finished:", format(Sys.time()), "\n")
cat("  Output:", RAW_DIR, "\n")
cat("=======================================================\n")

raw_files <- list.files(RAW_DIR, recursive = TRUE)
cat(sprintf("  %d files in data/raw/\n", length(raw_files)))
