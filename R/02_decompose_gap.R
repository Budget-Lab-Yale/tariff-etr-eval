# ==============================================================================
# 02_decompose_gap.R
#
# Decompose the statutory-actual ETR gap by granularity level.
#
# Key test: If the gap is driven by BEHAVIORAL changes (trade diversion,
# stockpiling), it should shrink at finer granularity because the gap comes
# from using 2024 weights on 2025 rates. If it's driven by IMPLEMENTATION
# frictions (Azzimonti 2025), the gap persists at all levels.
#
# Levels:
#   (a) Aggregate: single ETR across all products/countries
#   (b) By country: ETR within each partner
#   (c) By chapter: ETR within each HS2
#   (d) By chapter x country: finest available level
#
# Output: output/gap_decomposition.csv
# ==============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(here)

here::i_am("R/02_decompose_gap.R")
source(here("R", "utils.R"))

cat("=== ETR Gap Decomposition ===\n\n")

# --- Load data ---
census <- load_census_trade()
cat("Census data loaded:", nrow(census), "rows\n")

ts <- load_timeseries()
cat("Timeseries loaded:", nrow(ts), "rows\n\n")

# Also load actual ETR for comparison
actual_etr <- load_actual_etr() %>%
  filter(date >= "2025-01-01") %>%
  mutate(actual_rate = effective_rate / 100)

# --- Load HTS10-level import weights (2024 annual) ---
# These are essential for correctly weighting product-level rates when
# aggregating to HS2 x country. An unweighted mean drastically overstates
# rates (many low-import products with high tariffs).
imports_hs10 <- NULL
import_weights_file <- file.path(TRACKER_DIR, "config", "local_paths.yaml")
if (file.exists(import_weights_file)) {
  local_paths <- yaml::read_yaml(import_weights_file)
  iw_path <- local_paths$import_weights
  if (!is.null(iw_path) && !startsWith(iw_path, "/")) {
    iw_path <- normalizePath(file.path(TRACKER_DIR, iw_path), mustWork = FALSE)
  }
  if (!is.null(iw_path) && file.exists(iw_path)) {
    imports_hs10 <- readRDS(iw_path) %>%
      group_by(hs10, cty_code) %>%
      summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
      filter(imports > 0) %>%
      mutate(cty_code = as.character(cty_code))
    cat("HTS10 import weights loaded:", nrow(imports_hs10), "product-country pairs\n")
  }
}
if (is.null(imports_hs10)) {
  stop("HTS10 import weights not found. Configure local_paths.yaml in tariff-rate-tracker.")
}

# --- 2024 annual weights by HS2 x country ---
# Ensure cty_code is character for joining with timeseries
weights_2024 <- census %>%
  filter(year == 2024) %>%
  mutate(cty_code = as.character(cty_code)) %>%
  group_by(hs2, cty_code) %>%
  summarize(imports_2024 = sum(con_val_mo, na.rm = TRUE), .groups = "drop")

cat("2024 weight pairs:", nrow(weights_2024), "\n")

# --- Loop over key months in 2025 ---
ANALYSIS_MONTHS <- c("2025-01-01", "2025-04-01", "2025-06-01",
                     "2025-09-01", "2025-12-01")

results <- list()

for (month_str in ANALYSIS_MONTHS) {
  query_date <- as.Date(month_str)
  month_label <- format(query_date, "%b %Y")
  cat("\n--- ", month_label, " ---\n")

  # Get statutory snapshot
  snapshot <- ts %>%
    filter(valid_from <= query_date, valid_until >= query_date)

  # Join HTS10-level import weights, then aggregate to HS2 x country
  # using import-weighted means (not simple means)
  snapshot_weighted <- snapshot %>%
    rename(hs10 = hts10, cty_code = country) %>%
    inner_join(imports_hs10, by = c("hs10", "cty_code")) %>%
    mutate(hs2 = substr(hs10, 1, 2))

  stat_hs2_cty <- snapshot_weighted %>%
    group_by(hs2, cty_code) %>%
    summarize(
      mean_rate = weighted.mean(total_rate, w = imports, na.rm = TRUE),
      imports_hs10 = sum(imports),
      .groups = "drop"
    )

  # Get actual monthly imports
  m <- as.integer(format(query_date, "%m"))
  actual_imports <- census %>%
    filter(year == 2025, month == m) %>%
    mutate(cty_code = as.character(cty_code)) %>%
    select(hs2, cty_code, imports_actual = con_val_mo)

  # Merge: statutory rates + 2024 weights + actual 2025 imports
  merged <- stat_hs2_cty %>%
    inner_join(weights_2024, by = c("hs2", "cty_code")) %>%
    left_join(actual_imports, by = c("hs2", "cty_code")) %>%
    mutate(imports_actual = coalesce(imports_actual, 0))

  # Coverage diagnostic
  coverage <- sum(merged$imports_2024) / sum(weights_2024$imports_2024)

  # --- Compute ETR at each level ---

  # (a) Aggregate with 2024 Census weights (consistent two-stage aggregation)
  etr_agg_2024w <- weighted.mean(merged$mean_rate, w = merged$imports_2024, na.rm = TRUE)

  # (b) Aggregate with actual 2025 weights
  merged_pos <- merged %>% filter(imports_actual > 0)
  etr_agg_actual_w <- if (nrow(merged_pos) > 0) {
    weighted.mean(merged_pos$mean_rate, w = merged_pos$imports_actual, na.rm = TRUE)
  } else NA

  # (c) Treasury actual ETR for this month
  treasury_actual <- actual_etr %>%
    filter(date == query_date) %>%
    pull(actual_rate)
  treasury_actual <- if (length(treasury_actual) == 1) treasury_actual else NA

  # (d) By country: compute gap between 2024-weighted and actual-weighted ETR
  by_country <- merged %>%
    group_by(cty_code) %>%
    summarize(
      etr_2024w = weighted.mean(mean_rate, w = imports_2024, na.rm = TRUE),
      etr_actualw = ifelse(
        sum(imports_actual) > 0,
        weighted.mean(mean_rate, w = imports_actual, na.rm = TRUE),
        NA_real_
      ),
      imports_2024 = sum(imports_2024),
      imports_actual = sum(imports_actual),
      .groups = "drop"
    )

  # Variance of gap across countries (weighted)
  country_gaps <- by_country %>%
    filter(!is.na(etr_actualw)) %>%
    mutate(gap = etr_2024w - etr_actualw)
  mean_country_gap <- weighted.mean(country_gaps$gap, w = country_gaps$imports_2024, na.rm = TRUE)

  # (e) By chapter: same decomposition
  by_chapter <- merged %>%
    group_by(hs2) %>%
    summarize(
      etr_2024w = weighted.mean(mean_rate, w = imports_2024, na.rm = TRUE),
      etr_actualw = ifelse(
        sum(imports_actual) > 0,
        weighted.mean(mean_rate, w = imports_actual, na.rm = TRUE),
        NA_real_
      ),
      imports_2024 = sum(imports_2024),
      imports_actual = sum(imports_actual),
      .groups = "drop"
    )

  chapter_gaps <- by_chapter %>%
    filter(!is.na(etr_actualw)) %>%
    mutate(gap = etr_2024w - etr_actualw)
  mean_chapter_gap <- weighted.mean(chapter_gaps$gap, w = chapter_gaps$imports_2024, na.rm = TRUE)

  # (f) By chapter x country (finest): gap at cell level
  cell_gaps <- merged %>%
    filter(imports_actual > 0) %>%
    mutate(gap = 0)  # At the finest level, same rate applies — gap is 0 by construction
  # The gap at cell level = 0 because the rate is the rate. The question is
  # whether reweighting from 2024 to 2025 changes the aggregate.

  cat(sprintf("  Coverage (2024 imports):         %.1f%%\n", coverage * 100))
  cat(sprintf("  Statutory ETR (2024 weights):    %.2f%%\n", etr_agg_2024w * 100))
  cat(sprintf("  Statutory ETR (actual weights):  %.2f%%\n", etr_agg_actual_w * 100))
  cat(sprintf("  Weight-shift effect:             %.2f pp\n", (etr_agg_2024w - etr_agg_actual_w) * 100))
  cat(sprintf("  Treasury actual ETR:             %.2f%%\n", treasury_actual * 100))
  cat(sprintf("  Total gap (statutory - actual):   %.2f pp\n", (etr_agg_2024w - treasury_actual) * 100))
  cat(sprintf("  Behavioral (weight shift):        %.2f pp\n", (etr_agg_2024w - etr_agg_actual_w) * 100))
  cat(sprintf("  Residual (implementation etc):    %.2f pp\n", (etr_agg_actual_w - treasury_actual) * 100))

  results[[month_label]] <- tibble(
    month = month_label,
    date = query_date,
    etr_statutory_2024w = etr_agg_2024w,
    etr_statutory_actualw = etr_agg_actual_w,
    etr_treasury = treasury_actual,
    gap_total = etr_agg_2024w - treasury_actual,
    gap_behavioral = etr_agg_2024w - etr_agg_actual_w,
    gap_residual = etr_agg_actual_w - treasury_actual,
    coverage = coverage
  )
}

# --- Save results ---
decomp_results <- bind_rows(results)
write_csv(decomp_results, here("output", "gap_decomposition.csv"))
cat("\n\nSaved decomposition to output/gap_decomposition.csv\n")
print(decomp_results %>% mutate(across(where(is.numeric) & !matches("date"), ~ round(. * 100, 2))))

# --- Also save country-level detail for latest month ---
# Re-run for December 2025 and save country detail
query_date <- as.Date("2025-12-01")
snapshot <- ts %>% filter(valid_from <= query_date, valid_until >= query_date)

snapshot_weighted <- snapshot %>%
  rename(hs10 = hts10, cty_code = country) %>%
  inner_join(imports_hs10, by = c("hs10", "cty_code")) %>%
  mutate(hs2 = substr(hs10, 1, 2))

stat_hs2_cty <- snapshot_weighted %>%
  group_by(hs2, cty_code) %>%
  summarize(
    mean_rate = weighted.mean(total_rate, w = imports, na.rm = TRUE),
    .groups = "drop"
  )

actual_dec <- census %>%
  filter(year == 2025, month == 12) %>%
  mutate(cty_code = as.character(cty_code)) %>%
  select(hs2, cty_code, imports_actual = con_val_mo)

merged_dec <- stat_hs2_cty %>%
  inner_join(weights_2024, by = c("hs2", "cty_code")) %>%
  left_join(actual_dec, by = c("hs2", "cty_code")) %>%
  mutate(imports_actual = coalesce(imports_actual, 0))

# Country-level decomposition
country_detail <- merged_dec %>%
  mutate(partner_group = assign_partner_group(cty_code)) %>%
  group_by(partner_group) %>%
  summarize(
    etr_2024w = weighted.mean(mean_rate, w = imports_2024, na.rm = TRUE),
    etr_actualw = ifelse(
      sum(imports_actual) > 0,
      weighted.mean(mean_rate, w = imports_actual, na.rm = TRUE),
      NA_real_
    ),
    imports_2024_B = sum(imports_2024) / 1e9,
    imports_actual_B = sum(imports_actual) / 1e9,
    import_change_pct = (sum(imports_actual) / sum(imports_2024) * 12 - 1) * 100,
    .groups = "drop"
  ) %>%
  mutate(gap_pp = (etr_2024w - etr_actualw) * 100) %>%
  arrange(desc(imports_2024_B))

write_csv(country_detail, here("output", "gap_by_country.csv"))
cat("\nCountry-level gap (Dec 2025):\n")
country_detail %>%
  mutate(across(where(is.numeric), ~ round(., 2))) %>%
  print()

# Chapter-level decomposition
chapter_detail <- merged_dec %>%
  group_by(hs2) %>%
  summarize(
    etr_2024w = weighted.mean(mean_rate, w = imports_2024, na.rm = TRUE),
    etr_actualw = ifelse(
      sum(imports_actual) > 0,
      weighted.mean(mean_rate, w = imports_actual, na.rm = TRUE),
      NA_real_
    ),
    imports_2024_B = sum(imports_2024) / 1e9,
    imports_actual_B = sum(imports_actual) / 1e9,
    .groups = "drop"
  ) %>%
  mutate(gap_pp = (etr_2024w - etr_actualw) * 100) %>%
  arrange(desc(abs(gap_pp)))

write_csv(chapter_detail, here("output", "gap_by_chapter.csv"))
cat("\nTop 15 chapters by absolute gap (Dec 2025):\n")
chapter_detail %>%
  head(15) %>%
  mutate(across(where(is.numeric), ~ round(., 2))) %>%
  print()
