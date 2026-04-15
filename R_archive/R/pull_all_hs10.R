# ==============================================================================
# pull_all_hs10.R
#
# Pull HTS10 x country monthly data for ALL countries with 2025 trade.
# Extends the initial 15-country pull to full coverage.
# Uses existing cache to skip already-pulled country-months.
# ==============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(here)

here::i_am("run_all.R")

CENSUS_API_BASE <- "https://api.census.gov/data/timeseries/intltrade/imports/hs"
CACHE_FILE <- here("data", "census_hs10_country_monthly_2025_v2.csv")
TEST_MONTHS <- c(sprintf("2025-%02d", 1:12), "2026-01")

# --- Get all countries with 2025 trade from HS2 data ---
census <- read_csv(here("data", "census_hs2_country_monthly.csv"), show_col_types = FALSE)
all_ctys <- census %>%
  filter(year == 2025) %>%
  distinct(cty_code) %>%
  pull(cty_code) %>%
  as.character()

cat(sprintf("Countries with 2025 HS2 trade: %d\n", length(all_ctys)))

# --- Load existing cache ---
if (file.exists(CACHE_FILE)) {
  cached <- read_csv(CACHE_FILE, show_col_types = FALSE)
  existing_combos <- paste(cached$cty_code, cached$year_month)
  cached_ctys <- unique(as.character(cached$cty_code))
  cat(sprintf("Cached: %d rows, %d countries\n", nrow(cached), length(cached_ctys)))

  # Coverage check
  imports_2025 <- census %>%
    filter(year == 2025) %>%
    group_by(cty_code) %>%
    summarize(total = sum(con_val_mo, na.rm = TRUE), .groups = "drop")
  total_imp <- sum(imports_2025$total)
  cached_imp <- sum(imports_2025$total[imports_2025$cty_code %in% cached_ctys])
  cat(sprintf("Current import coverage: %.1f%%\n", cached_imp / total_imp * 100))
} else {
  cached <- NULL
  existing_combos <- character(0)
  cached_ctys <- character(0)
}

# Pull all countries (v2 includes duty fields missing from v1 cache)
remaining_ctys <- setdiff(all_ctys, cached_ctys)
cat(sprintf("Remaining countries: %d\n", length(remaining_ctys)))

# --- Build query list ---
queries <- expand.grid(cty = remaining_ctys, ym = TEST_MONTHS, stringsAsFactors = FALSE)
cat(sprintf("Total queries: %d (est. %.0f min)\n",
            nrow(queries), nrow(queries) * 0.3 / 60))

# --- API pull function ---
pull_hs10_country_month <- function(cty_code, year_month, max_retries = 3) {
  url <- paste0(
    CENSUS_API_BASE,
    "?get=CON_VAL_MO,GEN_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,I_COMMODITY",
    "&COMM_LVL=HS10",
    "&time=", year_month,
    "&CTY_CODE=", cty_code
  )

  for (attempt in seq_len(max_retries)) {
    resp <- tryCatch(GET(url, timeout(120)), error = function(e) {
      cat(sprintf("  HTTP error CTY=%s %s: %s\n", cty_code, year_month, conditionMessage(e)))
      NULL
    })

    if (!is.null(resp) && status_code(resp) == 200) {
      txt <- content(resp, as = "text", encoding = "UTF-8")
      if (nchar(txt) < 10 || grepl("error", txt, ignore.case = TRUE)) return(NULL)

      parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
      if (is.null(parsed) || nrow(parsed) < 2) return(NULL)

      header <- parsed[1, ]
      df <- as.data.frame(parsed[-1, , drop = FALSE], stringsAsFactors = FALSE)

      comm_idx <- which(header == "I_COMMODITY")[1]
      con_idx <- which(header == "CON_VAL_MO")[1]
      gen_idx <- which(header == "GEN_VAL_MO")[1]
      cal_idx <- which(header == "CAL_DUT_MO")[1]
      dut_idx <- which(header == "DUT_VAL_MO")[1]
      if (is.na(comm_idx)) return(NULL)

      tibble(
        hs10 = df[[comm_idx]],
        cty_code = cty_code,
        con_val = if (!is.na(con_idx)) as.numeric(df[[con_idx]]) else NA_real_,
        gen_val = if (!is.na(gen_idx)) as.numeric(df[[gen_idx]]) else NA_real_,
        cal_dut = if (!is.na(cal_idx)) as.numeric(df[[cal_idx]]) else NA_real_,
        dut_val = if (!is.na(dut_idx)) as.numeric(df[[dut_idx]]) else NA_real_,
        year_month = year_month
      ) %>%
        filter(coalesce(con_val, gen_val, 0) > 0, nchar(hs10) == 10)

    } else if (!is.null(resp) && status_code(resp) == 204) {
      return(NULL)
    } else if (attempt < max_retries) {
      Sys.sleep(1 * attempt)
    }
  }
  NULL
}

# --- Pull in batches, saving periodically ---
BATCH_SIZE <- 200
new_results <- list()
n_pulled <- 0

for (i in seq_len(nrow(queries))) {
  cty <- queries$cty[i]
  ym <- queries$ym[i]

  if (i %% 50 == 1 || i == 1) {
    cat(sprintf("  [%d/%d] CTY=%s, %s\n", i, nrow(queries), cty, ym))
  }

  result <- tryCatch(
    pull_hs10_country_month(cty, ym),
    error = function(e) {
      cat(sprintf("  ERROR CTY=%s %s: %s\n", cty, ym, conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(result) && nrow(result) > 0) {
    new_results[[length(new_results) + 1]] <- result
    n_pulled <- n_pulled + nrow(result)
  }
  if (i %% 13 == 0) cat(".")

  Sys.sleep(0.15)

  # Save after each country (every 13 queries) to avoid data loss
  if (i %% 13 == 0 && length(new_results) > 0) {
    batch <- bind_rows(new_results)
    if (!is.null(cached)) {
      cached <- bind_rows(cached, batch) %>%
        distinct(hs10, cty_code, year_month, .keep_all = TRUE)
    } else {
      cached <- batch
    }
    write_csv(cached, CACHE_FILE)
    cat(sprintf("  Saved: %d total rows, %d countries\n",
                nrow(cached), n_distinct(cached$cty_code)))
    new_results <- list()
    gc()  # Free memory between countries
  }
}

# Final save
if (length(new_results) > 0) {
  batch <- bind_rows(new_results)
  if (!is.null(cached)) {
    cached <- bind_rows(cached, batch) %>%
      distinct(hs10, cty_code, year_month, .keep_all = TRUE)
  } else {
    cached <- batch
  }
  write_csv(cached, CACHE_FILE)
}

cat(sprintf("\nDone. Total rows: %d, Countries: %d, Months: %d\n",
            nrow(cached), n_distinct(cached$cty_code), n_distinct(cached$year_month)))
cat(sprintf("New rows pulled: %d\n", n_pulled))

# Final coverage
imports_2025 <- census %>%
  filter(year == 2025) %>%
  group_by(cty_code) %>%
  summarize(total = sum(con_val_mo, na.rm = TRUE), .groups = "drop")
total_imp <- sum(imports_2025$total)
cached_imp <- sum(imports_2025$total[imports_2025$cty_code %in% unique(as.character(cached$cty_code))])
cat(sprintf("Final import coverage: %.1f%%\n", cached_imp / total_imp * 100))
