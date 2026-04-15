# ==============================================================================
# 02c_max_district_crosscheck.R
#
# Cross-check tariff-rate-tracker statutory rates against the Gopinath-Neiman
# "max across districts" approach. For each HTS10 x country, the max effective
# rate observed across customs districts approximates the statutory rate,
# since lower-rate districts reflect FTA/preference utilization.
#
# This comparison reveals:
#   (1) Products where tracker and observed max agree -> validation
#   (2) Products where tracker > observed max -> ALL importers use preferences
#       (statutory rate is correct but never observed at full value)
#   (3) Products where observed max > tracker -> potential tracker parsing error
#       or specific-rate / compound-rate effects
#
# Methodology:
#   - For each HS10 x country in a given month, compute:
#       max_rate = max(cal_dut_mo / con_val_mo) across (dist_entry, rate_prov)
#     filtering out zero-value entries and rate_prov == "00" (FTZ/bonded)
#   - Compare to tracker statutory rate for the same HS10 x country x date
#
# Inputs:
#   data/imdb/imdb_combined.rds  (from 01b_download_imdb.R)
#   tariff-rate-tracker: rate_timeseries.rds
#
# Outputs:
#   output/max_district_crosscheck.csv        -- HS10 x country comparison
#   output/max_district_summary.csv           -- aggregate match statistics
#   output/max_district_divergences.csv       -- flagged discrepancies
#
# Author: John Iselin
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)

here::i_am("R/02c_max_district_crosscheck.R")
source(here("R", "utils.R"))

cat("=== Max-Across-Districts Statutory Rate Cross-Check ===\n\n")

# ==============================================================================
# LOAD DATA
# ==============================================================================

imdb_path <- here("data", "imdb", "imdb_combined.rds")
if (!file.exists(imdb_path)) {
  stop("IMDB data not found. Run R/01b_download_imdb.R first.")
}
imdb <- readRDS(imdb_path)
cat(sprintf("IMDB data: %s rows\n", format(nrow(imdb), big.mark = ",")))

# Statutory rates loaded per-month below via load_snapshot_at_date()

# --- 2024 import weights (for weighting the comparison) ---
local_paths <- yaml::read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)
imports_2024 <- readRDS(iw_path) %>%
  group_by(hs10, cty_code) %>%
  summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
  filter(imports > 0) %>%
  mutate(cty_code = as.character(cty_code))

# ==============================================================================
# COMPUTE MAX-ACROSS-DISTRICTS RATE
# ==============================================================================

# Focus on months with significant tariff activity
analysis_months <- imdb %>%
  filter(year == 2025) %>%
  distinct(year_month) %>%
  arrange(year_month) %>%
  pull(year_month)

cat(sprintf("\nAnalysis months: %s\n", paste(analysis_months, collapse = ", ")))

all_comparisons <- list()
all_summaries <- list()

for (ym in analysis_months) {
  m <- as.integer(substr(ym, 6, 7))
  query_date <- as.Date(paste0(ym, "-01"))
  month_label <- format(query_date, "%b %Y")

  cat(sprintf("\n--- %s ---\n", month_label))

  # --- IMDB data for this month ---
  imdb_m <- imdb %>%
    filter(year_month == ym,
           # Exclude FTZ / bonded warehouse (not real duty payments)
           rate_prov != "00",
           # Exclude zero / negative values
           con_val_mo > 0)

  # --- Compute effective rate per entry ---
  imdb_m <- imdb_m %>%
    mutate(entry_rate = cal_dut_mo / con_val_mo)

  # --- Filter extreme rates (following GN: drop rate == 2.0 unless CN/RU) ---
  imdb_m <- imdb_m %>%
    filter(
      entry_rate < 2.0 |
      cty_code %in% c("5700", "4621")  # China, Russia
    )

  # --- Max rate across districts for each HS10 x country ---
  max_rates <- imdb_m %>%
    group_by(commodity, cty_code) %>%
    summarize(
      max_rate = max(entry_rate, na.rm = TRUE),
      mean_rate = weighted.mean(entry_rate, w = con_val_mo, na.rm = TRUE),
      min_rate = min(entry_rate, na.rm = TRUE),
      n_districts = n_distinct(dist_entry),
      n_rate_provs = n_distinct(rate_prov),
      total_imports = sum(con_val_mo, na.rm = TRUE),
      total_duties = sum(cal_dut_mo, na.rm = TRUE),
      has_preference = any(cty_subco != "0"),
      .groups = "drop"
    )

  # --- Statutory snapshot (memory-efficient: load only this revision) ---
  snapshot <- load_snapshot_at_date(query_date) %>%
    select(hts10, country, total_rate) %>%
    rename(hs10 = hts10, cty_code = country) %>%
    mutate(cty_code = as.character(cty_code))

  # --- Merge ---
  comparison <- max_rates %>%
    left_join(snapshot, by = c("commodity" = "hs10", "cty_code")) %>%
    left_join(imports_2024, by = c("commodity" = "hs10", "cty_code")) %>%
    mutate(
      tracker_rate = coalesce(total_rate, NA_real_),
      imports_2024 = coalesce(imports, 0),
      partner_group = assign_partner_group(cty_code),
      # Comparison metrics
      diff_pp = (tracker_rate - max_rate) * 100,
      abs_diff_pp = abs(diff_pp),
      match_2pp = abs_diff_pp <= 2,
      match_5pp = abs_diff_pp <= 5,
      # Categories
      category = case_when(
        is.na(tracker_rate) ~ "no_tracker_rate",
        abs_diff_pp <= 2 ~ "match",
        diff_pp > 2 ~ "tracker_higher",
        diff_pp < -2 ~ "observed_higher"
      ),
      date = query_date,
      month = month_label,
      year_month = ym
    )

  all_comparisons[[ym]] <- comparison

  # --- Summary statistics ---
  n_total <- nrow(comparison)
  n_matched <- sum(comparison$match_2pp, na.rm = TRUE)
  n_no_tracker <- sum(is.na(comparison$tracker_rate))
  n_with_tracker <- n_total - n_no_tracker

  # Weighted match rates (by 2024 imports)
  comp_with_tracker <- comparison %>% filter(!is.na(tracker_rate))
  weighted_match_2pp <- if (sum(comp_with_tracker$imports_2024) > 0) {
    sum(comp_with_tracker$imports_2024[comp_with_tracker$match_2pp]) /
      sum(comp_with_tracker$imports_2024) * 100
  } else NA_real_

  weighted_match_5pp <- if (sum(comp_with_tracker$imports_2024) > 0) {
    sum(comp_with_tracker$imports_2024[comp_with_tracker$match_5pp]) /
      sum(comp_with_tracker$imports_2024) * 100
  } else NA_real_

  # Aggregate weighted ETRs
  if (sum(comp_with_tracker$imports_2024) > 0) {
    w <- comp_with_tracker$imports_2024
    agg_tracker <- weighted.mean(comp_with_tracker$tracker_rate, w = w, na.rm = TRUE)
    agg_max <- weighted.mean(comp_with_tracker$max_rate, w = w, na.rm = TRUE)
    agg_mean <- weighted.mean(comp_with_tracker$mean_rate, w = w, na.rm = TRUE)
  } else {
    agg_tracker <- agg_max <- agg_mean <- NA_real_
  }

  summary_row <- tibble(
    month = month_label,
    date = query_date,
    n_hs10_country = n_total,
    n_with_tracker = n_with_tracker,
    n_match_2pp = n_matched,
    pct_match_2pp = n_matched / n_with_tracker * 100,
    weighted_match_2pp = weighted_match_2pp,
    weighted_match_5pp = weighted_match_5pp,
    n_tracker_higher = sum(comparison$category == "tracker_higher", na.rm = TRUE),
    n_observed_higher = sum(comparison$category == "observed_higher", na.rm = TRUE),
    agg_tracker_etr = agg_tracker * 100,
    agg_max_district_etr = agg_max * 100,
    agg_collected_etr = agg_mean * 100
  )

  all_summaries[[ym]] <- summary_row

  cat(sprintf("  HS10 x country pairs: %s (tracker: %s)\n",
              format(n_total, big.mark = ","),
              format(n_with_tracker, big.mark = ",")))
  cat(sprintf("  Match within 2pp: %.1f%% (unweighted), %.1f%% (import-weighted)\n",
              n_matched / n_with_tracker * 100, weighted_match_2pp))
  cat(sprintf("  Match within 5pp: %.1f%% (import-weighted)\n", weighted_match_5pp))
  cat(sprintf("  Tracker higher: %d | Observed higher: %d\n",
              sum(comparison$category == "tracker_higher", na.rm = TRUE),
              sum(comparison$category == "observed_higher", na.rm = TRUE)))
  cat(sprintf("  Aggregate ETRs: tracker=%.2f%%, max-district=%.2f%%, collected=%.2f%%\n",
              agg_tracker * 100, agg_max * 100, agg_mean * 100))

  # Free memory before next iteration
  rm(imdb_m, max_rates, snapshot, comparison, comp_with_tracker)
  gc(verbose = FALSE)
}

# ==============================================================================
# DIVERGENCE ANALYSIS
# ==============================================================================

cat("\n=== Divergence Analysis ===\n\n")

comparisons_all <- bind_rows(all_comparisons)
summaries_all <- bind_rows(all_summaries)

# Flag large divergences (>5pp, >$100M in 2024 imports)
divergences <- comparisons_all %>%
  filter(abs_diff_pp > 5, imports_2024 > 1e8, !is.na(tracker_rate)) %>%
  arrange(desc(imports_2024)) %>%
  select(month, commodity, cty_code, partner_group,
         tracker_rate, max_rate, mean_rate, diff_pp,
         n_districts, n_rate_provs, has_preference,
         total_imports, imports_2024, category)

cat(sprintf("Large divergences (>5pp, >$100M): %d\n", nrow(divergences)))

if (nrow(divergences) > 0) {
  cat("\nTop divergences by 2024 import value:\n")
  divergences %>%
    head(20) %>%
    mutate(
      tracker = sprintf("%.1f%%", tracker_rate * 100),
      max_obs = sprintf("%.1f%%", max_rate * 100),
      collected = sprintf("%.1f%%", mean_rate * 100),
      diff = sprintf("%+.1f pp", diff_pp),
      imp24 = sprintf("$%.1fB", imports_2024 / 1e9)
    ) %>%
    select(month, commodity, partner_group, tracker, max_obs, collected,
           diff, n_districts, has_preference, imp24, category) %>%
    print(n = 20, width = 150)
}

# Category breakdown by partner
cat("\n\nDivergence categories by partner (latest month, import-weighted):\n")
latest_month <- max(analysis_months)
comparisons_all %>%
  filter(year_month == latest_month, !is.na(tracker_rate), imports_2024 > 0) %>%
  group_by(partner_group, category) %>%
  summarize(
    n = n(),
    imports_B = sum(imports_2024) / 1e9,
    .groups = "drop"
  ) %>%
  group_by(partner_group) %>%
  mutate(share = imports_B / sum(imports_B) * 100) %>%
  ungroup() %>%
  mutate(
    imports_B = sprintf("$%.1fB", imports_B),
    share = sprintf("%.1f%%", share)
  ) %>%
  pivot_wider(
    names_from = category,
    values_from = c(n, imports_B, share),
    values_fill = list(n = 0L, imports_B = "$0.0B", share = "0.0%")
  ) %>%
  print(n = 10, width = 200)

# "Tracker higher" analysis: these are products where tracker says there's a
# tariff but the max observed rate is lower. Main drivers:
#   - Universal preference utilization (every importer uses FTA)
#   - Duty-free treatment (IEEPA exempt, Berman, etc.)
#   - Specific/compound rates where ad-valorem equivalent differs
cat("\n\n=== 'Tracker Higher' Deep Dive (latest month) ===\n")
tracker_higher <- comparisons_all %>%
  filter(year_month == latest_month,
         category == "tracker_higher",
         imports_2024 > 0) %>%
  mutate(hs2 = substr(commodity, 1, 2))

if (nrow(tracker_higher) > 0) {
  cat("\nBy HS2 chapter (import-weighted gap contribution):\n")
  tracker_higher %>%
    group_by(hs2) %>%
    summarize(
      n = n(),
      imports_B = sum(imports_2024) / 1e9,
      mean_gap_pp = weighted.mean(diff_pp, w = imports_2024, na.rm = TRUE),
      gap_contrib = sum(diff_pp / 100 * imports_2024) / sum(imports_2024),
      pct_with_pref = mean(has_preference) * 100,
      .groups = "drop"
    ) %>%
    arrange(desc(imports_B)) %>%
    head(15) %>%
    mutate(
      imports_B = sprintf("$%.1fB", imports_B),
      mean_gap = sprintf("%+.1f pp", mean_gap_pp),
      pref = sprintf("%.0f%%", pct_with_pref)
    ) %>%
    select(hs2, n, imports_B, mean_gap, pref) %>%
    print(n = 15)

  cat(sprintf("\n  Total 'tracker higher' trade: $%.1fB (%.1f%% of matched)\n",
              sum(tracker_higher$imports_2024) / 1e9,
              sum(tracker_higher$imports_2024) /
                sum(comparisons_all$imports_2024[
                  comparisons_all$year_month == latest_month &
                  !is.na(comparisons_all$tracker_rate)]) * 100))
}

# "Observed higher" analysis: potential tracker errors
cat("\n=== 'Observed Higher' Flags (latest month) ===\n")
observed_higher <- comparisons_all %>%
  filter(year_month == latest_month,
         category == "observed_higher",
         imports_2024 > 0) %>%
  mutate(hs2 = substr(commodity, 1, 2))

if (nrow(observed_higher) > 0) {
  cat("\nBy HS2 chapter:\n")
  observed_higher %>%
    group_by(hs2) %>%
    summarize(
      n = n(),
      imports_B = sum(imports_2024) / 1e9,
      mean_gap_pp = weighted.mean(diff_pp, w = imports_2024, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(imports_B)) %>%
    head(15) %>%
    mutate(
      imports_B = sprintf("$%.1fB", imports_B),
      mean_gap = sprintf("%+.1f pp", mean_gap_pp)
    ) %>%
    select(hs2, n, imports_B, mean_gap) %>%
    print(n = 15)

  cat(sprintf("\n  Total 'observed higher' trade: $%.1fB\n",
              sum(observed_higher$imports_2024) / 1e9))
  cat("  (These may indicate tracker underestimates or specific-rate effects)\n")
}

# ==============================================================================
# SAVE OUTPUTS
# ==============================================================================

cat("\n=== Saving Outputs ===\n")
output_dir <- here("output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Summary by month
write_csv(summaries_all, file.path(output_dir, "max_district_summary.csv"))
cat(sprintf("  max_district_summary.csv: %d rows\n", nrow(summaries_all)))

# Divergence flags
write_csv(divergences, file.path(output_dir, "max_district_divergences.csv"))
cat(sprintf("  max_district_divergences.csv: %d rows\n", nrow(divergences)))

# Full comparison (can be large — save as RDS)
saveRDS(comparisons_all, file.path(output_dir, "max_district_crosscheck.rds"))
# Also save a trimmed CSV with just the latest month
latest_csv <- comparisons_all %>%
  filter(year_month == latest_month) %>%
  select(commodity, cty_code, partner_group, tracker_rate, max_rate, mean_rate,
         diff_pp, category, n_districts, has_preference, total_imports, imports_2024)
write_csv(latest_csv, file.path(output_dir, "max_district_crosscheck.csv"))
cat(sprintf("  max_district_crosscheck.csv: %d rows (latest month)\n", nrow(latest_csv)))

cat("\nDone.\n")
