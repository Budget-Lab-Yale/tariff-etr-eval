# ==============================================================================
# test_within_cell_substitution.R
#
# Test the within-HS2-x-country substitution assumption by comparing:
#   (a) ETR using actual 2025 HTS10 x country monthly imports (true granular)
#   (b) ETR using synthetic weights (HS2 x country monthly, within-cell fixed)
#
# The difference = within-cell product substitution effect, currently absorbed
# into the residual in the decomposition framework.
#
# Data source: Census International Trade API at COMM_LVL=HS10
# Available through January 2026 (as of March 2026).
# ==============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(tidyr)
library(readr)
library(here)

here::i_am("run_all.R")
source(here("R", "utils.R"))

# --- Configuration ---
CENSUS_API_BASE <- "https://api.census.gov/data/timeseries/intltrade/imports/hs"

# Key countries (Census codes) — covers ~75% of US imports
KEY_COUNTRIES <- c(
  "5700",  # China
  "1220",  # Canada
  "2010",  # Mexico
  "5880",  # Japan
  "5800",  # S. Korea
  "4120",  # UK
  "5830",  # Taiwan
  "5520",  # Vietnam
  "5350",  # India
  # Major EU
  "4280",  # Germany
  "4220",  # France
  "4690",  # Italy
  "4610",  # Ireland
  "4760",  # Netherlands
  "4380",  # Belgium
  "4840",  # Spain
  # Other large
  "5590",  # Thailand
  "5550",  # Malaysia
  "5570",  # Indonesia
  "5510",  # Singapore
  "2390",  # Brazil
  "5880",  # Japan (already listed)
  "5520"   # Vietnam (already listed)
)
KEY_COUNTRIES <- unique(KEY_COUNTRIES)

# 2025 months to test
TEST_MONTHS <- sprintf("2025-%02d", 1:12)
# Also Jan 2026 if available
TEST_MONTHS <- c(TEST_MONTHS, "2026-01")

# --- Census API pull: all HS10 products for one country-month ---
pull_hs10_country_month <- function(cty_code, year_month, max_retries = 3) {
  url <- paste0(
    CENSUS_API_BASE,
    "?get=GEN_VAL_MO,I_COMMODITY",
    "&COMM_LVL=HS10",
    "&time=", year_month,
    "&CTY_CODE=", cty_code
  )

  for (attempt in seq_len(max_retries)) {
    resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)

    if (!is.null(resp) && status_code(resp) == 200) {
      txt <- content(resp, as = "text", encoding = "UTF-8")
      if (nchar(txt) < 10 || grepl("error", txt, ignore.case = TRUE)) return(NULL)

      parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
      if (is.null(parsed) || nrow(parsed) < 2) return(NULL)

      header <- parsed[1, ]
      df <- as.data.frame(parsed[-1, , drop = FALSE], stringsAsFactors = FALSE)

      comm_idx <- which(header == "I_COMMODITY")[1]
      val_idx <- which(header == "GEN_VAL_MO")[1]

      if (is.na(comm_idx) || is.na(val_idx)) return(NULL)

      result <- tibble(
        hs10 = df[[comm_idx]],
        cty_code = cty_code,
        gen_val = as.numeric(df[[val_idx]]),
        year_month = year_month
      ) %>%
        filter(!is.na(gen_val), gen_val > 0, nchar(hs10) == 10)

      return(result)

    } else if (!is.null(resp) && status_code(resp) == 204) {
      return(NULL)  # No data
    } else if (attempt < max_retries) {
      Sys.sleep(1 * attempt)
    }
  }
  NULL
}

# --- Cache file ---
cache_file <- here("data", "census_hs10_country_monthly_2025.csv")

if (file.exists(cache_file)) {
  cat("Loading cached HTS10 x country monthly data...\n")
  hs10_monthly <- read_csv(cache_file, show_col_types = FALSE)
  existing_combos <- paste(hs10_monthly$cty_code, hs10_monthly$year_month)
} else {
  hs10_monthly <- NULL
  existing_combos <- character(0)
}

# --- Pull missing data ---
queries <- expand.grid(cty = KEY_COUNTRIES, ym = TEST_MONTHS, stringsAsFactors = FALSE)
queries$combo <- paste(queries$cty, queries$ym)
queries_todo <- queries %>% filter(!combo %in% existing_combos)

if (nrow(queries_todo) > 0) {
  cat(sprintf("Pulling %d country x month combos from Census API (HS10)...\n",
              nrow(queries_todo)))
  new_results <- list()

  for (i in seq_len(nrow(queries_todo))) {
    cty <- queries_todo$cty[i]
    ym <- queries_todo$ym[i]

    if (i %% 10 == 1) {
      cat(sprintf("  [%d/%d] CTY=%s, %s\n", i, nrow(queries_todo), cty, ym))
    }

    result <- pull_hs10_country_month(cty, ym)
    if (!is.null(result) && nrow(result) > 0) {
      new_results[[length(new_results) + 1]] <- result
    }

    Sys.sleep(0.15)  # Rate limit
  }

  if (length(new_results) > 0) {
    new_data <- bind_rows(new_results)
    cat(sprintf("  Pulled %d new rows\n", nrow(new_data)))

    if (!is.null(hs10_monthly)) {
      hs10_monthly <- bind_rows(hs10_monthly, new_data) %>%
        distinct(hs10, cty_code, year_month, .keep_all = TRUE)
    } else {
      hs10_monthly <- new_data
    }

    write_csv(hs10_monthly, cache_file)
    cat(sprintf("  Saved to %s\n", cache_file))
  } else {
    cat("  No new data returned from API\n")
  }
} else {
  cat("All queries already cached.\n")
}

if (is.null(hs10_monthly) || nrow(hs10_monthly) == 0) {
  stop("No HTS10 x country monthly data available.")
}

# --- Parse dates ---
hs10_monthly <- hs10_monthly %>%
  mutate(
    year = as.integer(substr(year_month, 1, 4)),
    month = as.integer(substr(year_month, 6, 7)),
    date = as.Date(paste0(year_month, "-01"))
  )

cat(sprintf("\nHTS10 monthly data: %d rows, %d countries, %d months\n",
            nrow(hs10_monthly),
            n_distinct(hs10_monthly$cty_code),
            n_distinct(hs10_monthly$year_month)))

# --- Load statutory rates and 2024 weights ---
cat("Loading rate timeseries and 2024 import weights...\n")
ts <- load_timeseries()

local_paths <- yaml::read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)
imports_2024 <- readRDS(iw_path) %>%
  group_by(hs10, cty_code) %>%
  summarize(imports_2024 = sum(imports, na.rm = TRUE), .groups = "drop") %>%
  filter(imports_2024 > 0) %>%
  mutate(cty_code = as.character(cty_code))

# --- Run the within-cell substitution test ---
cat("\n=== Within-Cell Substitution Test ===\n\n")

available_months <- hs10_monthly %>%
  filter(year == 2025) %>%
  distinct(month) %>%
  arrange(month) %>%
  pull(month)

results <- list()

for (m in available_months) {
  query_date <- as.Date(sprintf("2025-%02d-01", m))
  month_label <- format(query_date, "%b %Y")

  # Statutory snapshot
  snapshot <- ts %>%
    filter(valid_from <= query_date, valid_until >= query_date) %>%
    rename(hs10 = hts10, cty_code = country) %>%
    select(hs10, cty_code, total_rate)

  # Actual monthly HS10 imports (from Census pull above)
  actual_hs10 <- hs10_monthly %>%
    filter(year == 2025, month == m) %>%
    select(hs10, cty_code, imports_actual = gen_val)

  # --- (A) True granular ETR: actual HS10 monthly weights ---
  # Left join: all actual imports, fill missing rates with 0
  true_granular <- actual_hs10 %>%
    left_join(snapshot, by = c("hs10", "cty_code")) %>%
    mutate(total_rate = coalesce(total_rate, 0))

  etr_true <- weighted.mean(true_granular$total_rate,
                            w = true_granular$imports_actual, na.rm = TRUE)

  # --- (B) Synthetic ETR: HS2 x country monthly, within-cell fixed ---
  # First compute cell-level rates using 2024 HTS10 weights (same as report)
  all_with_rates <- imports_2024 %>%
    left_join(snapshot, by = c("hs10", "cty_code")) %>%
    mutate(total_rate = coalesce(total_rate, 0),
           hs2 = substr(hs10, 1, 2))

  cell_rates <- all_with_rates %>%
    group_by(hs2, cty_code) %>%
    summarize(
      mean_rate = weighted.mean(total_rate, w = imports_2024, na.rm = TRUE),
      .groups = "drop"
    )

  # Monthly HS2 x country imports from the actual HS10 data
  actual_cells <- actual_hs10 %>%
    mutate(hs2 = substr(hs10, 1, 2)) %>%
    group_by(hs2, cty_code) %>%
    summarize(imports_actual = sum(imports_actual), .groups = "drop")

  # Synthetic = cell rates weighted by actual monthly cell totals
  synthetic_merged <- cell_rates %>%
    inner_join(actual_cells, by = c("hs2", "cty_code"))

  etr_synthetic <- weighted.mean(synthetic_merged$mean_rate,
                                 w = synthetic_merged$imports_actual, na.rm = TRUE)

  # --- (C) 2024-weight ETR for reference ---
  etr_2024w <- weighted.mean(all_with_rates$total_rate,
                             w = all_with_rates$imports_2024, na.rm = TRUE)

  # --- Coverage ---
  coverage <- sum(actual_hs10$imports_actual[
    paste(actual_hs10$hs10, actual_hs10$cty_code) %in%
    paste(imports_2024$hs10, imports_2024$cty_code)
  ]) / sum(actual_hs10$imports_actual)

  results[[month_label]] <- tibble(
    month = month_label,
    date = query_date,
    etr_2024w = etr_2024w,
    etr_synthetic = etr_synthetic,
    etr_true_granular = etr_true,
    within_cell_effect_pp = (etr_synthetic - etr_true) * 100,
    cross_cell_effect_pp = (etr_2024w - etr_synthetic) * 100,
    total_behavioral_pp = (etr_2024w - etr_true) * 100,
    within_cell_share = (etr_synthetic - etr_true) / (etr_2024w - etr_true) * 100,
    n_actual_pairs = nrow(actual_hs10),
    coverage = coverage
  )
}

results_df <- bind_rows(results)

cat("Monthly within-cell substitution test (key countries):\n\n")
results_df %>%
  mutate(
    etr_2024w_pct = sprintf("%.2f%%", etr_2024w * 100),
    etr_synth_pct = sprintf("%.2f%%", etr_synthetic * 100),
    etr_true_pct = sprintf("%.2f%%", etr_true_granular * 100),
    within_pp = sprintf("%+.2f", within_cell_effect_pp),
    cross_pp = sprintf("%+.2f", cross_cell_effect_pp),
    total_pp = sprintf("%+.2f", total_behavioral_pp),
    within_share = sprintf("%.0f%%", within_cell_share),
    cov = sprintf("%.0f%%", coverage * 100)
  ) %>%
  select(month, etr_2024w_pct, etr_synth_pct, etr_true_pct,
         cross_pp, within_pp, total_pp, within_share, cov) %>%
  print(n = 20, width = 120)

cat("\n\nInterpretation:\n")
cat("  cross_pp   = cross-cell reweighting (captured by current decomposition)\n")
cat("  within_pp  = within-cell product substitution (currently in residual)\n")
cat("  total_pp   = full behavioral effect at HTS10 granularity\n")
cat("  within_share = % of total behavioral effect from within-cell substitution\n")

# --- By country ---
cat("\n\n=== Within-Cell Effect by Country ===\n\n")

country_results <- list()

for (m in available_months) {
  query_date <- as.Date(sprintf("2025-%02d-01", m))
  month_label <- format(query_date, "%b %Y")

  snapshot <- ts %>%
    filter(valid_from <= query_date, valid_until >= query_date) %>%
    rename(hs10 = hts10, cty_code = country) %>%
    select(hs10, cty_code, total_rate)

  actual_hs10_m <- hs10_monthly %>%
    filter(year == 2025, month == m) %>%
    select(hs10, cty_code, imports_actual = gen_val)

  all_with_rates <- imports_2024 %>%
    left_join(snapshot, by = c("hs10", "cty_code")) %>%
    mutate(total_rate = coalesce(total_rate, 0),
           hs2 = substr(hs10, 1, 2))

  cell_rates <- all_with_rates %>%
    group_by(hs2, cty_code) %>%
    summarize(
      mean_rate = weighted.mean(total_rate, w = imports_2024, na.rm = TRUE),
      .groups = "drop"
    )

  for (cty in KEY_COUNTRIES) {
    partner <- assign_partner_group(cty)

    actual_cty <- actual_hs10_m %>% filter(cty_code == cty)
    if (nrow(actual_cty) == 0) next

    # True granular
    true_cty <- actual_cty %>%
      left_join(snapshot, by = c("hs10", "cty_code")) %>%
      mutate(total_rate = coalesce(total_rate, 0))
    etr_true_cty <- weighted.mean(true_cty$total_rate, w = true_cty$imports_actual, na.rm = TRUE)

    # Synthetic (cell rates x actual cell totals)
    actual_cells_cty <- actual_cty %>%
      mutate(hs2 = substr(hs10, 1, 2)) %>%
      group_by(hs2) %>%
      summarize(imports_actual = sum(imports_actual), .groups = "drop")

    synth_cty <- cell_rates %>%
      filter(cty_code == cty) %>%
      inner_join(actual_cells_cty, by = "hs2")

    etr_synth_cty <- if (nrow(synth_cty) > 0) {
      weighted.mean(synth_cty$mean_rate, w = synth_cty$imports_actual, na.rm = TRUE)
    } else NA_real_

    country_results[[length(country_results) + 1]] <- tibble(
      month = month_label,
      date = query_date,
      cty_code = cty,
      partner_group = partner,
      etr_true = etr_true_cty,
      etr_synthetic = etr_synth_cty,
      within_cell_pp = (etr_synth_cty - etr_true_cty) * 100,
      imports_actual_B = sum(actual_cty$imports_actual) / 1e9
    )
  }
}

country_df <- bind_rows(country_results)

# Summarize by country
cat("Average within-cell substitution effect by country (pp):\n")
country_df %>%
  group_by(partner_group) %>%
  summarize(
    mean_within_pp = mean(within_cell_pp, na.rm = TRUE),
    sd_within_pp = sd(within_cell_pp, na.rm = TRUE),
    mean_imports_B = mean(imports_actual_B),
    .groups = "drop"
  ) %>%
  arrange(desc(abs(mean_within_pp))) %>%
  mutate(
    within = sprintf("%+.3f", mean_within_pp),
    sd = sprintf("%.3f", sd_within_pp),
    imp = sprintf("$%.1fB", mean_imports_B)
  ) %>%
  select(partner_group, within, sd, imp) %>%
  print(n = 20)

# Save results
write_csv(results_df, here("output", "within_cell_test_aggregate.csv"))
write_csv(country_df, here("output", "within_cell_test_by_country.csv"))
cat("\nResults saved to output/\n")
