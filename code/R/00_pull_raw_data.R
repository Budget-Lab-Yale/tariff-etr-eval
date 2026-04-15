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
#   imdb_detail.csv                     -- HS10 x country x district x pref x month
#   imdb_hs10_country_monthly.csv       -- HS10 x country x month (aggregated)
#   census_hs10_fallback.csv            -- HS10 x country x month (API, gap months)
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
library(yaml)

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
CENSUS_HS2_CACHE <- file.path(RAW_DIR, "census_hs2_country_monthly.csv")

# Census releases data ~2 months after the reference month.
# Cap at 2 months before today to avoid timeouts on unreleased data.
latest_census_month <- seq(Sys.Date(), by = "-2 months", length.out = 2)[2]
YEAR_MONTHS_CENSUS <- format(
  seq(as.Date("2024-01-01"), latest_census_month, by = "month"), "%Y-%m"
)
HS2_CHAPTERS <- sprintf("%02d", setdiff(1:99, 77))

# Incremental pull: only query months not already cached.
# Historical months (2024, early 2025) won't change; skip them on re-runs.
cached_months <- character(0)
if (file.exists(CENSUS_HS2_CACHE)) {
  cached_data <- read_csv(CENSUS_HS2_CACHE, col_types = cols(.default = col_character()))
  cached_months <- unique(cached_data$year_month)
  # Always re-pull the last 2 cached months (may have been revised)
  cached_months <- setdiff(cached_months, tail(sort(cached_months), 2))
  cat(sprintf("  Cache: %d months frozen, re-pulling last 2\n", length(cached_months)))
}
months_to_pull <- setdiff(YEAR_MONTHS_CENSUS, cached_months)
cat(sprintf("  Months to pull: %d (of %d total)\n",
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
      cat(sprintf("  [%d/%d] %s ch%s (%.1fs/q, ~%.0fm left)\n",
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

# Combine new data with cache
new_data <- bind_rows(new_chunks)
if (file.exists(CENSUS_HS2_CACHE) && length(cached_months) > 0) {
  old_data <- read_csv(CENSUS_HS2_CACHE, show_col_types = FALSE) |>
    filter(year_month %in% cached_months)
  census_hs2 <- bind_rows(old_data, new_data)
  rm(old_data)
} else {
  census_hs2 <- new_data
}
rm(new_data, new_chunks)

census_hs2 <- census_hs2 |>
  mutate(
    year  = as.integer(substr(year_month, 1, 4)),
    month = as.integer(substr(year_month, 6, 7)),
    date  = as.Date(paste0(year_month, "-01")),
    effective_rate = ifelse(con_val_mo > 0, cal_dut_mo / con_val_mo * 100, NA_real_)
  ) |>
  arrange(year_month, hs2, cty_code)

write_csv(census_hs2, file.path(RAW_DIR, "census_hs2_country_monthly.csv"))
cat(sprintf("  Saved: %d rows (%d empty queries)\n\n", nrow(census_hs2), n_empty))


# ======================================================================
# 2. CENSUS IMDB: HS10 x country x month (rich detail + aggregated)
# ======================================================================

cat("--- 2. Census IMDB Bulk Files (HS10 x country x month) ---\n\n")

IMDB_URL_TEMPLATE <- "https://www.census.gov/trade/downloads/%s/Merch/im_m/IMDB%s.ZIP"

# Date range for IMDB
imdb_months <- seq(as.Date("2024-01-01"), Sys.Date(), by = "month")
YEAR_MONTHS_IMDB <- format(imdb_months, "%Y-%m")

# Rich fixed-width spec: includes preference code, district, rate provision
# (needed for FTA decomposition, max-district crosscheck)
imdb_fwf_rich <- fwf_positions(
  start     = c( 1, 11, 15, 17, 21, 23, 27,  74,  89, 104),
  end       = c(10, 14, 16, 18, 22, 26, 28,  88, 103, 118),
  col_names = c("commodity", "cty_code", "cty_subco", "dist_entry",
                "rate_prov", "year", "month",
                "con_val_mo", "dut_val_mo", "cal_dut_mo")
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
      cal_dut_mo = as.numeric(trimws(cal_dut_mo))
    ) |>
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
  cat(sprintf("  %s ... ", ym))

  zip_path <- download_imdb_zip(ym)
  if (is.null(zip_path)) { cat("not available\n"); next }

  month_data <- tryCatch(parse_imdb_detail(zip_path), error = function(e) {
    cat(sprintf("ERROR: %s\n", conditionMessage(e))); NULL
  })

  if (is.null(month_data) || nrow(month_data) == 0) { cat("empty\n"); next }

  cat(sprintf("%s rows, $%.0fB\n",
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
                         year_month, con_val_mo, dut_val_mo, cal_dut_mo),
  file.path(RAW_DIR, "imdb_detail.csv")
)
cat(sprintf("  Detail: %s rows, %d months\n",
            format(nrow(imdb_detail), big.mark = ","),
            n_distinct(imdb_detail$year_month)))

# --- Output 2: Aggregated to HS10 x country x month (for main pipeline) ---
imdb_agg <- imdb_detail |>
  summarise(con_val_mo = sum(con_val_mo, na.rm = TRUE),
            cal_dut_mo = sum(cal_dut_mo, na.rm = TRUE),
            .by = c(hs10, cty_code, year_month))
write_csv(imdb_agg, file.path(RAW_DIR, "imdb_hs10_country_monthly.csv"))
cat(sprintf("  Aggregated: %s rows\n", format(nrow(imdb_agg), big.mark = ",")))
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
  cat(sprintf("\n--- 2b. Census API HS10 fallback (%d months) ---\n\n",
              length(imdb_gap_months)))

  # Countries with meaningful trade volume (from HS2 pull)
  top_countries <- census_hs2 |>
    filter(year >= 2025) |>
    summarise(total = sum(con_val_mo, na.rm = TRUE), .by = cty_code) |>
    filter(total > 1e8) |>
    pull(cty_code)
  cat(sprintf("  Querying %d countries x %d months at HS10\n",
              length(top_countries), length(imdb_gap_months)))

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

  hs10_queries <- expand.grid(cty = top_countries, ym = imdb_gap_months,
                               stringsAsFactors = FALSE)
  n_queries <- nrow(hs10_queries)
  hs10_chunks <- vector("list", n_queries)

  for (i in seq_len(n_queries)) {
    if (i %% 50 == 0 || i == 1)
      cat(sprintf("  [%d/%d] %s cty=%s\n", i, n_queries,
                  hs10_queries$ym[i], hs10_queries$cty[i]))
    hs10_chunks[[i]] <- pull_hs10_country_month(
      hs10_queries$cty[i], hs10_queries$ym[i])
    Sys.sleep(0.15)
  }

  hs10_fallback <- bind_rows(hs10_chunks)
  if (nrow(hs10_fallback) > 0) {
    write_csv(hs10_fallback, file.path(RAW_DIR, "census_hs10_fallback.csv"))
    cat(sprintf("  Saved fallback: %s rows, %d months\n\n",
                format(nrow(hs10_fallback), big.mark = ","),
                n_distinct(hs10_fallback$year_month)))
  } else {
    cat("  No fallback data needed (IMDB covers all months)\n\n")
  }
} else {
  cat("\n--- 2b. Census API HS10 fallback: SKIPPED (IMDB complete) ---\n\n")
}


# ======================================================================
# 3. TARIFF-RATE-TRACKER: snapshots, daily ETRs, weights, revision dates
# ======================================================================

cat("--- 3. Tariff-Rate-Tracker Exports ---\n\n")

if (!dir.exists(TRACKER_DIR)) {
  stop("tariff-rate-tracker not found at: ", TRACKER_DIR,
       "\n  Expected sibling directory alongside this repo.", call. = FALSE)
}

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
  if (is.null(snap) || nrow(snap) == 0) { rm(snap); next }

  snap |>
    select(all_of(intersect(SNAP_COLS, colnames(snap)))) |>
    write_csv(out_csv)
  rm(snap)
}
gc(verbose = FALSE)
cat(sprintf("    -> %d snapshot CSVs written\n", length(snap_files)))

# --- 3b. 2024 import weights (RDS -> CSV) ---

cat("  Exporting 2024 import weights...\n")
local_paths <- read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)

if (file.exists(iw_path)) {
  readRDS(iw_path) |>
    summarise(imports = sum(imports, na.rm = TRUE),
              .by = c(hs10, cty_code)) |>
    filter(imports > 0) |>
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

if (!dir.exists(IMPACTS_DIR)) {
  stop("tariff-impact-tracker not found at: ", IMPACTS_DIR,
       "\n  Expected sibling directory alongside this repo.", call. = FALSE)
}

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
