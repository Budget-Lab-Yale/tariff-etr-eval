# ==============================================================================
# 02_decompose_gap.R
#
# Four-tier decomposition of the statutory-actual ETR gap:
#
#   Tier 1: Statutory ETR (tracker rates, 2024 import weights)
#   Tier 2: Statutory ETR (tracker rates, 2025 monthly import weights)
#   Tier 3: Census calculated ETR (cal_dut / con_val at HTS10 x country)
#   Tier 4: Treasury actual ETR (aggregate customs duties / imports)
#
# Gap decomposition:
#   Tier 1 → Tier 2 = Behavioral (between-country + within-country, Shapley)
#   Tier 2 → Tier 3 = Exemptions, USMCA utilization, specific-rate effects
#   Tier 3 → Tier 4 = Timing, enforcement, evasion
#
# Also computes:
#   - YoY comparison (2024 annual vs 2025 annual weights)
#   - Azzimonti (May 2025) benchmark
#   - Gopinath-Neiman (Sept 2025) benchmark
#
# Inputs:
#   - tariff-rate-tracker: rate_timeseries.rds, daily ETRs
#   - tariff-rate-tracker: HTS10 import weights (2024 annual, via local_paths.yaml)
#   - data/census_hs10_country_monthly_2025_v2.csv (from pull_all_hs10.R)
#   - tariff-impact-tracker: tariff_revenue.csv (Treasury actual ETR)
#
# Outputs:
#   output/decomp_monthly.csv       -- monthly 4-tier decomposition
#   output/decomp_by_country.csv    -- country contributions by month
#   output/decomp_by_sector.csv     -- sector-level detail by month
#   output/decomp_yoy.csv           -- annual 2024 vs 2025
#   output/decomp_benchmarks.csv    -- Azzimonti + Gopinath-Neiman comparison
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)

here::i_am("R/02_decompose_gap.R")
source(here("R", "utils.R"))

cat("=== ETR Gap Decomposition (Four-Tier, HTS10 granularity) ===\n\n")

# ==============================================================================
# DATA LOADING
# ==============================================================================

# --- Statutory rate timeseries (HTS10 x country x revision) ---
ts <- load_timeseries()
cat(sprintf("Rate timeseries: %d rows\n", nrow(ts)))

# --- 2024 annual import weights (HTS10 x country) ---
local_paths <- yaml::read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)
imports_2024 <- readRDS(iw_path) %>%
  group_by(hs10, cty_code) %>%
  summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
  filter(imports > 0) %>%
  mutate(cty_code = as.character(cty_code))
total_imports_2024 <- sum(imports_2024$imports)
cat(sprintf("2024 HTS10 weights: %d pairs, $%.0fB total\n",
            nrow(imports_2024), total_imports_2024 / 1e9))

# --- 2025 monthly HTS10 imports + duties (from Census API pull) ---
hs10_file <- here("data", "census_hs10_country_monthly_2025_v2.csv")
if (!file.exists(hs10_file)) {
  stop("HTS10 monthly data not found. Run R/pull_all_hs10.R first.")
}
imports_monthly <- read_csv(hs10_file, show_col_types = FALSE) %>%
  mutate(
    cty_code = as.character(cty_code),
    year = as.integer(substr(year_month, 1, 4)),
    month = as.integer(substr(year_month, 6, 7)),
    # Use con_val as primary; fall back to gen_val
    import_val = coalesce(con_val, gen_val),
    # Calculated duty (Census estimate of assessed duty)
    cal_dut = coalesce(cal_dut, 0)
  )
cat(sprintf("Monthly HTS10 data: %d rows, %d countries, %d months\n",
            nrow(imports_monthly), n_distinct(imports_monthly$cty_code),
            n_distinct(imports_monthly$year_month)))

# --- Treasury actual ETR (aggregate monthly) ---
actual_etr <- load_actual_etr() %>%
  filter(date >= "2025-01-01") %>%
  mutate(actual_rate = effective_rate / 100)

# ==============================================================================
# HELPERS
# ==============================================================================

#' Assign statutory rates to a set of import weights.
#' Products not in the snapshot get rate = 0.
assign_rates <- function(weights_df, snapshot, hs10_col = "hs10", cty_col = "cty_code") {
  weights_df %>%
    left_join(
      snapshot %>% select(hs10, cty_code, total_rate),
      by = setNames(c("hs10", "cty_code"), c(hs10_col, cty_col))
    ) %>%
    mutate(total_rate = coalesce(total_rate, 0))
}

#' Shapley decomposition of ETR difference into between-country and within-country.
#' Returns list: etr_base, etr_new, between, within, country_detail
shapley_decompose <- function(base_rates, new_imports, snapshot) {
  # Base: country shares and country-level ETRs from 2024 weights
  country_base <- base_rates %>%
    group_by(cty_code) %>%
    summarize(
      E_c = weighted.mean(total_rate, w = imports, na.rm = TRUE),
      w_c = sum(imports),
      .groups = "drop"
    ) %>%
    mutate(s_c = w_c / sum(w_c))

  # New: assign same statutory rates to new monthly imports
  new_with_rates <- new_imports %>%
    left_join(
      base_rates %>% select(hs10, cty_code, total_rate) %>% distinct(),
      by = c("hs10", "cty_code")
    ) %>%
    mutate(total_rate = coalesce(total_rate, 0))

  country_new <- new_with_rates %>%
    group_by(cty_code) %>%
    summarize(
      E_c_new = weighted.mean(total_rate, w = import_val, na.rm = TRUE),
      w_c_new = sum(import_val),
      .groups = "drop"
    ) %>%
    mutate(s_c_new = w_c_new / sum(w_c_new))

  # Merge
  merged <- country_base %>%
    full_join(country_new, by = "cty_code") %>%
    mutate(across(c(E_c, s_c, w_c), ~ coalesce(., 0)),
           across(c(E_c_new, s_c_new, w_c_new), ~ coalesce(., 0)))

  etr_base <- sum(merged$s_c * merged$E_c)
  etr_new <- sum(merged$s_c_new * merged$E_c_new)

  # Shapley (average of two bases)
  merged <- merged %>%
    mutate(
      between_c = 0.5 * (E_c + E_c_new) * (s_c - s_c_new),
      within_c = 0.5 * (s_c + s_c_new) * (E_c - E_c_new),
      total_c = between_c + within_c,
      partner_group = assign_partner_group(cty_code)
    )

  list(
    etr_base = etr_base,
    etr_new = etr_new,
    between = sum(merged$between_c),
    within = sum(merged$within_c),
    country_detail = merged
  )
}

# ==============================================================================
# MONTHLY FOUR-TIER DECOMPOSITION
# ==============================================================================

cat("\n=== Monthly Four-Tier Decomposition ===\n")

available_months <- imports_monthly %>%
  filter(year == 2025) %>%
  distinct(month) %>%
  arrange(month) %>%
  pull(month)

monthly_results <- list()
country_results <- list()
sector_results <- list()

for (m in available_months) {
  query_date <- as.Date(sprintf("2025-%02d-01", m))
  month_label <- format(query_date, "%b %Y")

  # --- Statutory snapshot ---
  snapshot <- ts %>%
    filter(valid_from <= query_date, valid_until >= query_date) %>%
    rename(hs10 = hts10, cty_code = country)

  # --- Tier 1: Statutory ETR, 2024 weights ---
  rates_2024 <- assign_rates(imports_2024, snapshot)
  tier1 <- weighted.mean(rates_2024$total_rate, w = rates_2024$imports, na.rm = TRUE)

  # --- Monthly imports for this month ---
  monthly_m <- imports_monthly %>%
    filter(year == 2025, month == m) %>%
    select(hs10, cty_code, import_val, cal_dut)

  # --- Tier 2: Statutory ETR, 2025 monthly weights ---
  monthly_with_rates <- assign_rates(monthly_m, snapshot)
  tier2 <- if (sum(monthly_m$import_val, na.rm = TRUE) > 0) {
    weighted.mean(monthly_with_rates$total_rate, w = monthly_with_rates$import_val, na.rm = TRUE)
  } else NA_real_

  # --- Tier 3: Census calculated duty ETR ---
  total_monthly_imports <- sum(monthly_m$import_val, na.rm = TRUE)
  total_monthly_duty <- sum(monthly_m$cal_dut, na.rm = TRUE)
  tier3 <- if (total_monthly_imports > 0) {
    total_monthly_duty / total_monthly_imports
  } else NA_real_

  # --- Tier 4: Treasury actual ETR ---
  tier4 <- actual_etr %>%
    filter(date == query_date) %>%
    pull(actual_rate)
  tier4 <- if (length(tier4) == 1) tier4 else NA_real_

  # --- Shapley decomposition (Tier 1 → Tier 2) ---
  decomp <- shapley_decompose(rates_2024, monthly_m, snapshot)

  # --- Coverage ---
  coverage_imports <- sum(monthly_m$import_val, na.rm = TRUE)

  monthly_results[[month_label]] <- tibble(
    date = query_date,
    month = month_label,
    tier1_statutory_2024w = tier1,
    tier2_statutory_monthw = tier2,
    tier3_census_cal = tier3,
    tier4_treasury = tier4,
    gap_total = tier1 - tier4,
    gap_behavioral = tier1 - tier2,
    gap_behavioral_between = decomp$between,
    gap_behavioral_within = decomp$within,
    gap_exemptions = tier2 - tier3,
    gap_timing = tier3 - tier4,
    monthly_imports_B = coverage_imports / 1e9
  )

  # --- Country-level detail ---
  # Behavioral (from Shapley)
  cty_behavioral <- decomp$country_detail %>%
    group_by(partner_group) %>%
    summarize(
      between_pp = sum(between_c) * 100,
      within_pp = sum(within_c) * 100,
      behavioral_pp = sum(total_c) * 100,
      etr_base_pct = weighted.mean(E_c, w = pmax(w_c, 1e-10)) * 100,
      etr_new_pct = weighted.mean(E_c_new, w = pmax(w_c_new, 1e-10)) * 100,
      share_2024 = sum(s_c),
      share_month = sum(s_c_new),
      .groups = "drop"
    )

  # Census actual duty by country
  cty_census <- monthly_m %>%
    mutate(partner_group = assign_partner_group(cty_code)) %>%
    group_by(partner_group) %>%
    summarize(
      imports_B = sum(import_val, na.rm = TRUE) / 1e9,
      cal_duty_B = sum(cal_dut, na.rm = TRUE) / 1e9,
      census_etr_pct = sum(cal_dut, na.rm = TRUE) / sum(import_val, na.rm = TRUE) * 100,
      .groups = "drop"
    )

  cty_combined <- cty_behavioral %>%
    left_join(cty_census, by = "partner_group") %>%
    mutate(date = query_date, month = month_label)

  country_results[[month_label]] <- cty_combined

  # --- Sector-level detail ---
  sector_base <- rates_2024 %>%
    mutate(hs2 = substr(hs10, 1, 2)) %>%
    group_by(hs2) %>%
    summarize(
      etr_2024w = weighted.mean(total_rate, w = imports, na.rm = TRUE),
      imports_2024_B = sum(imports) / 1e9,
      .groups = "drop"
    )

  sector_month <- monthly_with_rates %>%
    mutate(hs2 = substr(hs10, 1, 2)) %>%
    group_by(hs2) %>%
    summarize(
      etr_monthw = weighted.mean(total_rate, w = import_val, na.rm = TRUE),
      imports_month_B = sum(import_val) / 1e9,
      .groups = "drop"
    )

  sector_census <- monthly_m %>%
    mutate(hs2 = substr(hs10, 1, 2)) %>%
    group_by(hs2) %>%
    summarize(
      census_etr = sum(cal_dut, na.rm = TRUE) / sum(import_val, na.rm = TRUE),
      .groups = "drop"
    )

  sector_merged <- sector_base %>%
    full_join(sector_month, by = "hs2") %>%
    left_join(sector_census, by = "hs2") %>%
    mutate(
      across(everything(), ~ coalesce(., 0)),
      behavioral_pp = (etr_2024w - etr_monthw) * 100,
      exemption_pp = (etr_monthw - census_etr) * 100,
      date = query_date,
      month = month_label
    )

  sector_results[[month_label]] <- sector_merged

  cat(sprintf("  %s: T1=%.2f%% T2=%.2f%% T3=%.2f%% T4=%.2f%% | beh=%+.2f (btw=%+.2f, win=%+.2f) exempt=%+.2f timing=%+.2f\n",
              month_label, tier1*100, tier2*100,
              ifelse(is.na(tier3), NA, tier3*100),
              ifelse(is.na(tier4), NA, tier4*100),
              (tier1-tier2)*100, decomp$between*100, decomp$within*100,
              ifelse(is.na(tier2-tier3), NA, (tier2-tier3)*100),
              ifelse(is.na(tier3-tier4), NA, (tier3-tier4)*100)))
}

decomp_monthly <- bind_rows(monthly_results)
country_all <- bind_rows(country_results)
sector_all <- bind_rows(sector_results)

# ==============================================================================
# YOY COMPARISON: 2024 annual vs 2025 annual weights
# ==============================================================================

cat("\n=== Year-over-Year Comparison (2024 vs 2025 annual) ===\n")

# 2025 annual = sum monthly HTS10 imports
imports_2025_annual <- imports_monthly %>%
  filter(year == 2025) %>%
  group_by(hs10, cty_code) %>%
  summarize(
    import_val = sum(import_val, na.rm = TRUE),
    cal_dut = sum(cal_dut, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(import_val > 0)

# Use Dec 2025 rates as representative
query_date <- as.Date("2025-12-01")
snapshot <- ts %>%
  filter(valid_from <= query_date, valid_until >= query_date) %>%
  rename(hs10 = hts10, cty_code = country)

rates_2024 <- assign_rates(imports_2024, snapshot)
tier1_yoy <- weighted.mean(rates_2024$total_rate, w = rates_2024$imports, na.rm = TRUE)

annual_with_rates <- assign_rates(imports_2025_annual, snapshot, "hs10", "cty_code")
tier2_yoy <- weighted.mean(annual_with_rates$total_rate, w = annual_with_rates$import_val, na.rm = TRUE)

tier3_yoy <- sum(imports_2025_annual$cal_dut) / sum(imports_2025_annual$import_val)

treasury_2025_avg <- actual_etr %>%
  filter(date >= "2025-01-01") %>%
  summarize(avg = mean(actual_rate, na.rm = TRUE)) %>%
  pull(avg)

decomp_yoy_shapley <- shapley_decompose(rates_2024, imports_2025_annual, snapshot)

decomp_yoy <- tibble(
  period = "2024 vs 2025",
  tier1 = tier1_yoy,
  tier2 = tier2_yoy,
  tier3 = tier3_yoy,
  tier4 = treasury_2025_avg,
  gap_total = tier1_yoy - treasury_2025_avg,
  behavioral_total = tier1_yoy - tier2_yoy,
  behavioral_between = decomp_yoy_shapley$between,
  behavioral_within = decomp_yoy_shapley$within,
  exemptions = tier2_yoy - tier3_yoy,
  timing = tier3_yoy - treasury_2025_avg
)

cat(sprintf("  Tier 1 (statutory, 2024w): %.2f%%\n", tier1_yoy * 100))
cat(sprintf("  Tier 2 (statutory, 2025w): %.2f%%\n", tier2_yoy * 100))
cat(sprintf("  Tier 3 (Census cal duty):  %.2f%%\n", tier3_yoy * 100))
cat(sprintf("  Tier 4 (Treasury actual):  %.2f%%\n", treasury_2025_avg * 100))
cat(sprintf("  Behavioral: %+.2f pp (between=%+.2f, within=%+.2f)\n",
            (tier1_yoy - tier2_yoy) * 100,
            decomp_yoy_shapley$between * 100,
            decomp_yoy_shapley$within * 100))
cat(sprintf("  Exemptions: %+.2f pp\n", (tier2_yoy - tier3_yoy) * 100))
cat(sprintf("  Timing/enforcement: %+.2f pp\n", (tier3_yoy - treasury_2025_avg) * 100))

# ==============================================================================
# BENCHMARKS: Azzimonti (May 2025) + Gopinath-Neiman (Sept 2025)
# ==============================================================================

cat("\n=== Benchmarks ===\n")

# --- Azzimonti (Aug 2025 paper): May 2025 snapshot ---
# She reports: predicted ETR = 17.5%, actual = 8.7%, gap = 8.8 pp
# Channels: within-country 0.6pp, cross-country 2.7pp, implementation 4.2pp
may <- decomp_monthly %>% filter(month == "May 2025")

# --- Gopinath-Neiman (Feb 2026 paper): Sept 2025 snapshot ---
# They report: statutory = 27.4%, actual = 14.1%, gap ~13 pp
# They attribute gap to: shipment lags, exemptions, USMCA (~2pp), evasion
sep <- decomp_monthly %>% filter(month == "Sep 2025")

benchmarks <- tibble(
  source = c(
    rep("Azzimonti (2025)", 4),
    rep("Our estimate, May 2025", 4),
    rep("Gopinath-Neiman (2026)", 3),
    rep("Our estimate, Sep 2025", 5)
  ),
  channel = c(
    # Azzimonti
    "Within-country product mix", "Cross-country sourcing",
    "Implementation", "Total gap",
    # Ours (May)
    "Within-country product mix", "Cross-country sourcing",
    "Exemptions + USMCA", "Timing + enforcement",
    # Gopinath-Neiman
    "Statutory ETR", "Actual ETR", "Total gap",
    # Ours (Sept)
    "Tier 1 (statutory 2024w)", "Tier 2 (statutory monthw)",
    "Tier 3 (Census cal duty)", "Tier 4 (Treasury actual)", "Total gap"
  ),
  value_pp = c(
    # Azzimonti
    0.6, 2.7, 4.2, 8.8,
    # Ours (May)
    if (nrow(may) > 0) c(may$gap_behavioral_within * 100,
                          may$gap_behavioral_between * 100,
                          may$gap_exemptions * 100,
                          may$gap_timing * 100) else rep(NA, 4),
    # Gopinath-Neiman
    27.4, 14.1, 13.3,
    # Ours (Sept)
    if (nrow(sep) > 0) c(sep$tier1_statutory_2024w * 100,
                          sep$tier2_statutory_monthw * 100,
                          sep$tier3_census_cal * 100,
                          sep$tier4_treasury * 100,
                          sep$gap_total * 100) else rep(NA, 5)
  )
)

cat("\nBenchmark comparison:\n")
print(benchmarks, n = 30)

# ==============================================================================
# SAVE OUTPUTS
# ==============================================================================

cat("\n=== Saving Outputs ===\n")
output_dir <- here("output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

write_csv(decomp_monthly, file.path(output_dir, "decomp_monthly.csv"))
write_csv(country_all, file.path(output_dir, "decomp_by_country.csv"))
write_csv(sector_all, file.path(output_dir, "decomp_by_sector.csv"))
write_csv(decomp_yoy, file.path(output_dir, "decomp_yoy.csv"))
write_csv(benchmarks, file.path(output_dir, "decomp_benchmarks.csv"))

cat("Saved 5 CSV files to output/\n")
cat("Done.\n")
