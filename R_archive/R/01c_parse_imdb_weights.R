# ==============================================================================
# 01c_parse_imdb_weights.R
#
# Parse IMDB raw ZIPs into HS10 × country monthly import weights.
# Aggregates con_val_mo across districts/preferences for each product-country
# pair — gives us a COMPLETE monthly weight table with full import coverage.
#
# Output: data/imdb/imdb_hs10_country_monthly.csv
#   Columns: hs10, cty_code, year_month, con_val_mo, cal_dut_mo
#
# This replaces the sparse Census API HS10 pull for use in the counterfactual
# ladder and behavioral decomposition.
# ==============================================================================

library(readr)
library(dplyr)
library(here)
library(stringi)

here::i_am("R/01c_parse_imdb_weights.R")

IMDB_DIR <- here("data", "imdb")
RAW_DIR <- file.path(IMDB_DIR, "raw")
OUTPUT_FILE <- file.path(IMDB_DIR, "imdb_hs10_country_monthly.csv")

# Fixed-width spec — use EXACT positions from 01b_download_imdb.R
# Only read the fields we need (commodity, country, year, month, values)
imdb_col_positions <- fwf_positions(
  start = c( 1, 11, 23, 27,  74, 104),
  end   = c(10, 14, 26, 28,  88, 118),
  col_names = c(
    "commodity",    # HTS10 (pos 1-10)
    "cty_code",     # Census country code (pos 11-14)
    "year",         # Statistical year (pos 23-26, 4 chars)
    "month",        # Statistical month (pos 27-28, 2 chars)
    "con_val_mo",   # Consumption value, monthly (pos 74-88)
    "cal_dut_mo"    # Calculated duty, monthly (pos 104-118)
  )
)

parse_one_zip <- function(zip_path) {
  zip_contents <- unzip(zip_path, list = TRUE)$Name
  detl_file <- grep("IMP_DETL\\.TXT$", zip_contents, value = TRUE, ignore.case = TRUE)
  if (length(detl_file) == 0) return(NULL)

  tmp_dir <- tempfile("imdb_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  unzip(zip_path, files = detl_file[1], exdir = tmp_dir)
  detl_path <- file.path(tmp_dir, detl_file[1])

  fsize_mb <- file.size(detl_path) / 1e6

  # For large files (>100MB), skip the full-file binary sanitization that causes
  # OOM. Instead, read_fwf with locale that tolerates encoding issues.
  # The non-UTF-8 bytes are rare and only appear in description fields we skip.
  df <- tryCatch(
    read_fwf(detl_path, col_positions = imdb_col_positions,
             col_types = cols(.default = col_character()),
             locale = locale(encoding = "latin1"),
             progress = FALSE),
    error = function(e) {
      # Fallback: chunk-based binary sanitization for stubborn files
      cat(sprintf("[latin1 failed: %s, trying binary clean] ", conditionMessage(e)))
      CHUNK <- 100e6  # 100MB chunks
      fsize <- file.size(detl_path)
      con <- file(detl_path, "rb")
      clean_path <- file.path(tmp_dir, "CLEAN.TXT")
      out <- file(clean_path, "wb")
      remaining <- fsize
      while (remaining > 0) {
        n <- min(CHUNK, remaining)
        chunk <- readBin(con, what = "raw", n = n)
        chunk[chunk > as.raw(0x7F)] <- as.raw(0x3F)
        writeBin(chunk, out)
        remaining <- remaining - n
      }
      close(con); close(out)
      read_fwf(clean_path, col_positions = imdb_col_positions,
               col_types = cols(.default = col_character()), progress = FALSE)
    }
  )

  df %>%
    mutate(
      commodity = stri_pad_left(trimws(commodity), 10, "0"),
      cty_code = trimws(cty_code),
      year = suppressWarnings(as.integer(trimws(year))),
      month = suppressWarnings(as.integer(trimws(month))),
      con_val_mo = suppressWarnings(as.numeric(trimws(con_val_mo))),
      cal_dut_mo = suppressWarnings(as.numeric(trimws(cal_dut_mo)))
    ) %>%
    filter(grepl("^[0-9]+$", commodity),
           !is.na(year), !is.na(month),
           coalesce(con_val_mo, 0) != 0) %>%
    group_by(commodity, cty_code, year, month) %>%
    summarize(
      con_val_mo = sum(con_val_mo, na.rm = TRUE),
      cal_dut_mo = sum(cal_dut_mo, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    rename(hs10 = commodity) %>%
    mutate(year_month = sprintf("%04d-%02d", year, month))
}

# --- Find ZIPs to parse ---
zips <- list.files(RAW_DIR, pattern = "^IMDB25[0-9]{2}\\.ZIP$", full.names = TRUE)
zips <- sort(zips)
cat(sprintf("=== Parse IMDB ZIPs to HS10 × country weights ===\n"))
cat(sprintf("Found %d 2025 ZIPs to parse\n\n", length(zips)))

all_months <- list()

for (zp in zips) {
  fname <- basename(zp)
  cat(sprintf("  Parsing %s (%.0f MB) ... ", fname, file.size(zp) / 1e6))

  parsed <- tryCatch(parse_one_zip(zp), error = function(e) {
    cat(sprintf("ERROR: %s\n", conditionMessage(e))); NULL
  })

  if (is.null(parsed) || nrow(parsed) == 0) {
    cat("empty\n"); next
  }

  cat(sprintf("%s pairs, $%.0fB\n",
              format(nrow(parsed), big.mark = ","),
              sum(parsed$con_val_mo, na.rm = TRUE) / 1e9))
  all_months[[fname]] <- parsed

  rm(parsed); gc(verbose = FALSE)
}

# Combine and write
combined <- bind_rows(all_months)
cat(sprintf("\nTotal: %s rows, %d months\n",
            format(nrow(combined), big.mark = ","),
            n_distinct(combined$year_month)))

write_csv(combined %>% select(hs10, cty_code, year_month, con_val_mo, cal_dut_mo),
          OUTPUT_FILE)
cat(sprintf("Wrote: %s\n", OUTPUT_FILE))

# Summary by month
combined %>%
  group_by(year_month) %>%
  summarize(pairs = n(), imports_B = sum(con_val_mo) / 1e9, .groups = "drop") %>%
  arrange(year_month) %>%
  { for (i in seq_len(nrow(.)))
      cat(sprintf("  %s: %s pairs, $%.0fB\n",
                  .$year_month[i],
                  format(.$pairs[i], big.mark = ","),
                  .$imports_B[i]))
  }

cat("\n=== Done ===\n")
