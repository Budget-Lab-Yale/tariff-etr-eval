# ==============================================================================
# 01_pull_census_trade.R
#
# Pull monthly import data from Census Bureau International Trade API
# at HS2 (chapter) x country level, including calculated duties.
#
# Columns pulled:
#   CON_VAL_MO  - Consumption value of imports (monthly, USD)
#   CAL_DUT_MO  - Calculated duty (monthly, USD) -- estimated statutory duty amount
#   DUT_VAL_MO  - Dutiable value (monthly, USD) -- value of imports subject to duty
#   I_COMMODITY - HS chapter code (2-digit)
#   CTY_CODE    - Census country code
#
# IMPORTANT: CAL_DUT_MO is the Census estimate of statutory duty. It does NOT
# reflect actual duties collected. See Census definition:
# "Estimates of calculated duty do not necessarily reflect amounts of duty paid."
# DUT_VAL_MO is the dutiable VALUE (not the duty itself).
#
# Coverage: 2024 (baseline) + 2025 (tariff escalation) + 2026 (as available)
# Output:  data/census_hs2_country_monthly.csv
#
# Note: The Census API limits results per query. We loop over HS2 chapters
# and months to stay within limits (~100 country rows per chapter-month).
#
# Census country codes: https://www.census.gov/library/reference/code-lists/country.html
# API docs: https://api.census.gov/data/timeseries/intltrade/imports/hs.html
# ==============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(here)

here::i_am("R/01_pull_census_trade.R")

# --- Configuration ---
CENSUS_API_BASE <- "https://api.census.gov/data/timeseries/intltrade/imports/hs"
OUTPUT_FILE <- here("data", "census_hs2_country_monthly.csv")

# HS2 chapters (01-99, excluding 77 which is reserved)
HS2_CHAPTERS <- sprintf("%02d", setdiff(1:99, 77))

# Year-month combinations to pull
YEAR_MONTHS <- c(
  # 2024 baseline (full year)
  paste0("2024-", sprintf("%02d", 1:12)),
  # 2025 tariff escalation (full year)
  paste0("2025-", sprintf("%02d", 1:12)),
  # 2026 (as available — API returns empty if not yet published)
  paste0("2026-", sprintf("%02d", 1:12))
)

# --- Census country code lookup (major partners) ---
CENSUS_COUNTRIES <- tribble(
  ~cty_code, ~country_name, ~partner_group,
  "5700",    "China",          "China",
  "1220",    "Canada",         "Canada",
  "2010",    "Mexico",         "Mexico",
  "5880",    "Japan",          "Japan",
  "5800",    "South Korea",    "S. Korea",
  "4120",    "United Kingdom", "UK"
  # EU and ROW assigned by exclusion in downstream analysis
)

# --- API query function ---
#' Pull one HS2 chapter x month from Census API
#' Returns a tibble with columns: hs2, cty_code, con_val_mo, dut_val_mo, year_month
#' Filters out aggregate rows (CTY_CODE starting with "0" = world/region totals)
pull_chapter_month <- function(hs2, year_month, max_retries = 3) {
  url <- paste0(
    CENSUS_API_BASE,
    "?get=CON_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,CTY_CODE",
    "&I_COMMODITY=", hs2,
    "&time=", year_month,
    "&COMM_LVL=HS2"
  )

  for (attempt in seq_len(max_retries)) {
    resp <- tryCatch({
      GET(url, timeout(30))
    }, error = function(e) {
      NULL
    })

    if (!is.null(resp) && status_code(resp) == 200) {
      txt <- content(resp, as = "text", encoding = "UTF-8")
      if (nchar(txt) < 10 || grepl("error", txt, ignore.case = TRUE)) {
        return(NULL)  # No data for this month (e.g., future 2026 months)
      }

      parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
      if (is.null(parsed) || nrow(parsed) < 2) return(NULL)

      # First row is header, rest is data
      df <- as.data.frame(parsed[-1, , drop = FALSE], stringsAsFactors = FALSE)
      # Column mapping — find each field by header name
      header <- parsed[1, ]
      cty_idx <- which(header == "CTY_CODE")[1]
      con_idx <- which(header == "CON_VAL_MO")[1]
      cal_idx <- which(header == "CAL_DUT_MO")[1]
      dut_idx <- which(header == "DUT_VAL_MO")[1]

      if (is.na(cty_idx)) {
        return(NULL)
      }

      result <- tibble(
        hs2 = hs2,
        cty_code = df[[cty_idx]],
        con_val_mo = as.numeric(df[[con_idx]]),
        cal_dut_mo = if (!is.na(cal_idx)) as.numeric(df[[cal_idx]]) else NA_real_,
        dut_val_mo = if (!is.na(dut_idx)) as.numeric(df[[dut_idx]]) else NA_real_,
        year_month = year_month
      ) %>%
        # Filter out aggregate rows (world totals "-", region subtotals "00XX")
        # Keep only individual countries (4-digit numeric codes >= 1000)
        filter(grepl("^[0-9]+$", cty_code), as.integer(cty_code) >= 1000)

      return(result)

    } else if (attempt < max_retries) {
      Sys.sleep(0.5 * attempt)  # Brief backoff
    }
  }

  NULL
}

# --- Main pull loop ---
cat("=== Census Trade Data Pull ===\n")
cat("Pulling HS2 x country x month from Census API\n")
cat("Chapters:", length(HS2_CHAPTERS), "\n")
cat("Months:", length(YEAR_MONTHS), "\n\n")

# Check for existing data to allow incremental updates
existing <- NULL
if (file.exists(OUTPUT_FILE)) {
  existing <- read_csv(OUTPUT_FILE, show_col_types = FALSE)
  existing_combos <- paste(existing$hs2, existing$year_month)
  cat("Found existing data:", nrow(existing), "rows,",
      n_distinct(existing$year_month), "months\n")
}

all_results <- list()
idx <- 0
total_queries <- length(HS2_CHAPTERS) * length(YEAR_MONTHS)
skipped <- 0
empty <- 0

for (ym in YEAR_MONTHS) {
  for (ch in HS2_CHAPTERS) {
    idx <- idx + 1

    # Skip if already have this combo
    if (!is.null(existing) && paste(ch, ym) %in% existing_combos) {
      skipped <- skipped + 1
      next
    }

    if (idx %% 100 == 0 || idx == 1) {
      cat(sprintf("  [%d/%d] %s ch%s ...\n", idx, total_queries, ym, ch))
    }

    result <- pull_chapter_month(ch, ym)

    if (!is.null(result) && nrow(result) > 0) {
      all_results[[length(all_results) + 1]] <- result
    } else {
      empty <- empty + 1
    }

    # Rate limit: Census API is generous but be polite
    Sys.sleep(0.1)
  }
}

cat(sprintf("\nDone: %d queries, %d skipped (existing), %d empty\n",
            idx, skipped, empty))

# Combine and save
if (length(all_results) > 0) {
  new_data <- bind_rows(all_results)
  cat("New rows pulled:", nrow(new_data), "\n")

  if (!is.null(existing)) {
    combined <- bind_rows(existing, new_data) %>%
      distinct(hs2, cty_code, year_month, .keep_all = TRUE)
  } else {
    combined <- new_data
  }
} else if (!is.null(existing)) {
  combined <- existing
  cat("No new data pulled; keeping existing.\n")
} else {
  stop("No data pulled and no existing file.")
}

# Parse year/month for convenience
combined <- combined %>%
  mutate(
    year = as.integer(substr(year_month, 1, 4)),
    month = as.integer(substr(year_month, 6, 7)),
    date = as.Date(paste0(year_month, "-01")),
    calc_etr = cal_dut_mo / con_val_mo * 100,  # Census calculated duty ETR
    dutiable_share = dut_val_mo / con_val_mo * 100  # Share of imports that are dutiable
  ) %>%
  arrange(year_month, hs2, cty_code)

write_csv(combined, OUTPUT_FILE)
cat("Saved:", nrow(combined), "rows to", OUTPUT_FILE, "\n")

# --- Summary statistics ---
cat("\n=== Summary ===\n")
combined %>%
  group_by(year) %>%
  summarize(
    months = n_distinct(year_month),
    countries = n_distinct(cty_code),
    total_imports_B = sum(con_val_mo, na.rm = TRUE) / 1e9,
    total_duties_B = sum(dut_val_mo, na.rm = TRUE) / 1e9,
    avg_etr = total_duties_B / total_imports_B * 100,
    .groups = "drop"
  ) %>%
  print()
