# ==============================================================================
# 01b_download_imdb.R
#
# Download and parse Census IMDB (International Merchandise Trade Database)
# monthly import detail files. These bulk files contain HTS10 x country x
# district x rate-provision level data, including:
#   - CTY_SUBCO: preference program code (USMCA, KORUS, GSP, etc.)
#   - DIST_ENTRY: customs district of entry
#   - RATE_PROV: rate provision (free, dutiable MFN, dutiable ch99, etc.)
#   - CAL_DUT_MO: calculated (assessed) duty
#   - CON_VAL_MO: consumption value
#
# This is far richer than the Census API, which exposes only aggregate values.
# The IMDB files are the same source used by Gopinath & Neiman (2026).
#
# URL pattern: https://www.census.gov/trade/downloads/{YYYY}/Merch/im_m/IMDB{YYMM}.ZIP
# Each ZIP contains IMP_DETL.TXT (fixed-width, 688 chars/record, 52 fields).
#
# Output:
#   data/imdb/imdb_{YYYY}_{MM}.rds  -- per-month parsed detail (key fields only)
#   data/imdb/imdb_combined.rds     -- combined panel
#
# Usage:
#   Rscript R/01b_download_imdb.R              # download all configured months
#   Rscript R/01b_download_imdb.R --force      # re-download even if cached
#   Rscript R/01b_download_imdb.R --start 2025-01 --end 2025-06
#
# Author: John Iselin
# ==============================================================================

library(readr)
library(dplyr)
library(here)

here::i_am("R/01b_download_imdb.R")

# --- Configuration ---
IMDB_URL_TEMPLATE <- "https://www.census.gov/trade/downloads/%s/Merch/im_m/IMDB%s.ZIP"
IMDB_DIR <- here("data", "imdb")
DOWNLOAD_DIR <- file.path(IMDB_DIR, "raw")

# Default date range: 2024 baseline + 2025 escalation + 2026 as available
DEFAULT_START <- "2024-01"
DEFAULT_END <- format(Sys.Date(), "%Y-%m")

# --- Parse CLI args ---
args <- commandArgs(trailingOnly = TRUE)
force_redownload <- "--force" %in% args

start_ym <- DEFAULT_START
end_ym <- DEFAULT_END
if ("--start" %in% args) {
  start_ym <- args[which(args == "--start") + 1]
}
if ("--end" %in% args) {
  end_ym <- args[which(args == "--end") + 1]
}

# Build month sequence
start_date <- as.Date(paste0(start_ym, "-01"))
end_date <- as.Date(paste0(end_ym, "-01"))
month_seq <- seq(start_date, end_date, by = "month")
YEAR_MONTHS <- format(month_seq, "%Y-%m")

cat("=== IMDB Bulk Download & Parse ===\n")
cat(sprintf("Date range: %s to %s (%d months)\n", start_ym, end_ym, length(YEAR_MONTHS)))
cat(sprintf("Force re-download: %s\n\n", force_redownload))

# --- Create directories ---
if (!dir.exists(IMDB_DIR)) dir.create(IMDB_DIR, recursive = TRUE)
if (!dir.exists(DOWNLOAD_DIR)) dir.create(DOWNLOAD_DIR, recursive = TRUE)

# ==============================================================================
# FIXED-WIDTH SPEC (from Census IMDB layout / Gopinath-Neiman replication)
# ==============================================================================

# We only read the fields we need. Full record is 688 chars, 52 fields.
# Positions are 1-indexed, inclusive on both ends.
imdb_col_positions <- fwf_positions(
  start = c( 1, 11, 15, 17, 21, 23, 27,  74,  89, 104, 149, 179),
  end   = c(10, 14, 16, 18, 22, 26, 28,  88, 103, 118, 163, 193),
  col_names = c(
    "commodity",    # HTS10 (10 chars)
    "cty_code",     # Census country code (4 chars)
    "cty_subco",    # Sub-country/preference code (2 chars)
    "dist_entry",   # District of entry (2 chars)
    "rate_prov",    # Rate provision (2 chars)
    "year",         # Statistical year (4 chars)
    "month",        # Statistical month (2 chars)
    "con_val_mo",   # Consumption value, monthly (15 chars)
    "dut_val_mo",   # Dutiable value, monthly (15 chars)
    "cal_dut_mo",   # Calculated duty, monthly (15 chars)
    "gen_qy1_mo",   # General quantity 1, monthly (15 chars)
    "gen_val_mo"    # General value, monthly (15 chars)
  )
)

# ==============================================================================
# DOWNLOAD + PARSE FUNCTIONS
# ==============================================================================

#' Build IMDB download URL for a given year-month
build_imdb_url <- function(year_month) {
  yyyy <- substr(year_month, 1, 4)
  yy <- substr(year_month, 3, 4)
  mm <- substr(year_month, 6, 7)
  sprintf(IMDB_URL_TEMPLATE, yyyy, paste0(yy, mm))
}

#' Download one IMDB ZIP file. Returns path to ZIP or NULL on failure.
download_imdb_zip <- function(year_month, max_retries = 3) {
  url <- build_imdb_url(year_month)
  yymm <- paste0(substr(year_month, 3, 4), substr(year_month, 6, 7))
  zip_path <- file.path(DOWNLOAD_DIR, paste0("IMDB", yymm, ".ZIP"))

  if (file.exists(zip_path) && !force_redownload) {
    return(zip_path)
  }

  for (attempt in seq_len(max_retries)) {
    result <- tryCatch({
      download.file(url, zip_path, mode = "wb", quiet = TRUE)
      if (file.exists(zip_path) && file.size(zip_path) > 1000) {
        return(zip_path)
      }
      NULL
    }, error = function(e) {
      if (attempt < max_retries) Sys.sleep(2 * attempt)
      NULL
    })
    if (!is.null(result)) return(result)
  }

  # File not available (future month, etc.)
  if (file.exists(zip_path)) file.remove(zip_path)
  NULL
}

#' Parse IMP_DETL.TXT from a ZIP file. Returns a tibble with key fields.
parse_imdb_zip <- function(zip_path, year_month) {
  # List files in ZIP to find IMP_DETL
  zip_contents <- unzip(zip_path, list = TRUE)$Name
  detl_file <- grep("IMP_DETL", zip_contents, value = TRUE, ignore.case = TRUE)

  if (length(detl_file) == 0) {
    warning("No IMP_DETL file found in ", zip_path)
    return(NULL)
  }

  # Extract to temp directory
  tmp_dir <- tempfile("imdb_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  unzip(zip_path, files = detl_file[1], exdir = tmp_dir)
  detl_path <- file.path(tmp_dir, detl_file[1])

  # Read fixed-width. IMDB files are raw ASCII with occasional non-UTF-8 bytes
  # (e.g., in commodity descriptions that bleed into adjacent fields).
  # Sanitize the file to clean UTF-8 before read_fwf touches it.
  raw_bytes <- readBin(detl_path, what = "raw", n = file.size(detl_path))
  # Replace any byte > 0x7F with '?' (ASCII substitute)
  raw_bytes[raw_bytes > as.raw(0x7F)] <- as.raw(0x3F)
  clean_path <- file.path(tmp_dir, "IMP_DETL_CLEAN.TXT")
  writeBin(raw_bytes, clean_path)

  # Parse fixed-width from sanitized file
  df <- read_fwf(
    clean_path,
    col_positions = imdb_col_positions,
    col_types = cols(.default = col_character()),
    progress = FALSE
  )

  # Clean and type-convert
  df <- df %>%
    mutate(
      # Pad commodity to 10 chars (leading zeros) — use stringr-style padding
      # to avoid sprintf locale issues with non-ASCII remnants
      commodity = trimws(commodity),
      commodity = stringi::stri_pad_left(commodity, 10, "0"),
      cty_code = trimws(cty_code),
      cty_subco = trimws(cty_subco),
      dist_entry = trimws(dist_entry),
      rate_prov = trimws(rate_prov),
      year = as.integer(trimws(year)),
      month = as.integer(trimws(month)),
      con_val_mo = as.numeric(trimws(con_val_mo)),
      dut_val_mo = as.numeric(trimws(dut_val_mo)),
      cal_dut_mo = as.numeric(trimws(cal_dut_mo)),
      gen_qy1_mo = as.numeric(trimws(gen_qy1_mo)),
      gen_val_mo = as.numeric(trimws(gen_val_mo)),
      year_month = year_month
    ) %>%
    # Drop rows with non-numeric commodity codes (header lines, garbage)
    filter(grepl("^[0-9]+$", commodity)) %>%
    # Drop rows with zero or missing value (statistical noise / corrections)
    filter(coalesce(con_val_mo, 0) != 0 | coalesce(gen_val_mo, 0) != 0)

  df
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

results_log <- list()

for (ym in YEAR_MONTHS) {
  rds_path <- file.path(IMDB_DIR, sprintf("imdb_%s_%s.rds",
                                           substr(ym, 1, 4), substr(ym, 6, 7)))

  # Skip if already parsed (unless forcing)
  if (file.exists(rds_path) && !force_redownload) {
    cat(sprintf("  [cached] %s (%s)\n", ym, basename(rds_path)))
    results_log[[ym]] <- list(status = "cached", rds = rds_path)
    next
  }

  # Download
  cat(sprintf("  Downloading %s ... ", ym))
  zip_path <- download_imdb_zip(ym)

  if (is.null(zip_path)) {
    cat("not available\n")
    results_log[[ym]] <- list(status = "unavailable")
    next
  }
  cat(sprintf("%.1f MB ... ", file.size(zip_path) / 1e6))

  # Parse
  parsed <- tryCatch(
    parse_imdb_zip(zip_path, ym),
    error = function(e) {
      cat(sprintf("PARSE ERROR: %s\n", conditionMessage(e)))
      NULL
    }
  )

  if (is.null(parsed) || nrow(parsed) == 0) {
    cat("empty\n")
    results_log[[ym]] <- list(status = "empty")
    next
  }

  # Save per-month RDS

saveRDS(parsed, rds_path)
  cat(sprintf("%s rows, %s countries, %s products\n",
              format(nrow(parsed), big.mark = ","),
              n_distinct(parsed$cty_code),
              n_distinct(parsed$commodity)))

  results_log[[ym]] <- list(
    status = "ok",
    rows = nrow(parsed),
    countries = n_distinct(parsed$cty_code),
    products = n_distinct(parsed$commodity),
    rds = rds_path
  )

  # Clean up to control memory
  rm(parsed)
  gc(verbose = FALSE)
}

# ==============================================================================
# COMBINE INTO PANEL
# ==============================================================================

cat("\n=== Combining monthly files ===\n")

rds_files <- list.files(IMDB_DIR, pattern = "^imdb_\\d{4}_\\d{2}\\.rds$", full.names = TRUE)
rds_files <- sort(rds_files)

if (length(rds_files) == 0) {
  stop("No parsed IMDB files found.")
}

cat(sprintf("  Found %d monthly files\n", length(rds_files)))

# Read and bind (chunked to manage memory)
combined <- bind_rows(lapply(rds_files, readRDS))

cat(sprintf("  Combined: %s rows, %d months, %d countries, %d products\n",
            format(nrow(combined), big.mark = ","),
            n_distinct(combined$year_month),
            n_distinct(combined$cty_code),
            n_distinct(combined$commodity)))

# Save combined
combined_path <- file.path(IMDB_DIR, "imdb_combined.rds")
saveRDS(combined, combined_path)
cat(sprintf("  Saved to %s (%.0f MB)\n", combined_path,
            file.size(combined_path) / 1e6))

# ==============================================================================
# SUMMARY STATISTICS
# ==============================================================================

cat("\n=== Summary by Year-Month ===\n")
combined %>%
  group_by(year_month) %>%
  summarize(
    rows = n(),
    countries = n_distinct(cty_code),
    products = n_distinct(commodity),
    imports_B = sum(con_val_mo, na.rm = TRUE) / 1e9,
    duties_B = sum(cal_dut_mo, na.rm = TRUE) / 1e9,
    etr_pct = sum(cal_dut_mo, na.rm = TRUE) / sum(con_val_mo, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  mutate(
    imports_B = sprintf("$%.1fB", imports_B),
    duties_B = sprintf("$%.1fB", duties_B),
    etr_pct = sprintf("%.2f%%", etr_pct)
  ) %>%
  print(n = 40)

# Preference code distribution (2025)
cat("\n=== Preference Code (CTY_SUBCO) Distribution, 2025 ===\n")
combined %>%
  filter(year == 2025) %>%
  mutate(
    pref_label = case_when(
      cty_subco == "0"  ~ "No preference",
      cty_subco == "S"  ~ "USMCA (S)",
      cty_subco == "S+" ~ "USMCA (S+)",
      cty_subco == "CA" ~ "NAFTA-CA (legacy)",
      cty_subco == "MX" ~ "NAFTA-MX (legacy)",
      cty_subco == "KR" ~ "KORUS",
      cty_subco == "AU" ~ "AUSFTA",
      cty_subco == "JP" ~ "Japan",
      cty_subco == "A"  ~ "GSP",
      cty_subco == "A+" ~ "GSP (LDC)",
      cty_subco == "IL" ~ "Israel FTA",
      cty_subco == "SG" ~ "Singapore FTA",
      cty_subco == "CL" ~ "Chile FTA",
      cty_subco == "CO" ~ "Colombia TPA",
      cty_subco == "P"  ~ "CAFTA-DR",
      cty_subco == "PE" ~ "Peru TPA",
      cty_subco == "PA" ~ "Panama TPA",
      cty_subco == "D"  ~ "AGOA",
      TRUE ~ paste0("Other (", cty_subco, ")")
    )
  ) %>%
  group_by(pref_label) %>%
  summarize(
    entries = n(),
    imports_B = sum(con_val_mo, na.rm = TRUE) / 1e9,
    duties_B = sum(cal_dut_mo, na.rm = TRUE) / 1e9,
    .groups = "drop"
  ) %>%
  arrange(desc(imports_B)) %>%
  mutate(
    share = imports_B / sum(imports_B) * 100,
    etr = duties_B / imports_B * 100,
    imports_B = sprintf("$%.1fB", imports_B),
    share = sprintf("%.1f%%", share),
    etr = sprintf("%.2f%%", etr)
  ) %>%
  print(n = 30)

# Rate provision distribution (2025)
cat("\n=== Rate Provision Distribution, 2025 ===\n")
combined %>%
  filter(year == 2025) %>%
  mutate(
    rp_label = case_when(
      rate_prov == "00" ~ "FTZ/bonded warehouse",
      rate_prov == "10" ~ "Free (HTS ch01-98)",
      rate_prov == "18" ~ "Free (GSP/proclamation)",
      rate_prov == "19" ~ "Free (ch99 provision)",
      rate_prov == "61" ~ "Dutiable (MFN general)",
      rate_prov == "62" ~ "Dutiable (Column 2)",
      rate_prov == "64" ~ "Dutiable (special/FTA rate)",
      rate_prov == "69" ~ "Dutiable (ch99, duty reported)",
      rate_prov == "70" ~ "Dutiable (special, no duty calc)",
      rate_prov == "79" ~ "Dutiable (ch99, no duty calc)",
      TRUE ~ paste0("Other (", rate_prov, ")")
    )
  ) %>%
  group_by(rp_label) %>%
  summarize(
    entries = n(),
    imports_B = sum(con_val_mo, na.rm = TRUE) / 1e9,
    duties_B = sum(cal_dut_mo, na.rm = TRUE) / 1e9,
    .groups = "drop"
  ) %>%
  arrange(desc(imports_B)) %>%
  mutate(
    share = imports_B / sum(imports_B) * 100,
    imports_B = sprintf("$%.1fB", imports_B),
    share = sprintf("%.1f%%", share),
    duties_B = sprintf("$%.1fB", duties_B)
  ) %>%
  print(n = 20)

cat("\nDone.\n")
