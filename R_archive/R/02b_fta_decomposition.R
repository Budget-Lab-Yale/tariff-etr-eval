# ==============================================================================
# 02b_fta_decomposition.R
#
# Decomposes the Tier 2 → Tier 3 gap ("exemptions") into specific channels
# using IMDB detail data. This inserts a "Tier 2.5" into the decomposition
# framework from 02_decompose_gap.R.
#
# The Tier 2→3 gap = statutory ETR (tracker rates, monthly weights)
#                   - Census calculated ETR (cal_dut / con_val at HS10 x country)
#
# With IMDB rate-provision and preference codes, we can attribute this to:
#
#   (a) USMCA utilization: CA/MX imports entering under S/S+ preference codes
#       pay reduced or zero duty vs. the MFN/IEEPA statutory rate
#   (b) Other FTA utilization: KORUS, AUSFTA, Israel, Chile, Colombia, etc.
#   (c) GSP / AGOA / other preference programs
#   (d) Duty-free entries: rate_prov in {10, 18, 19} — free under HTS, GSP,
#       or ch99 provision (distinct from FTA preferences)
#   (e) Ch99 rate gap: difference between tracker statutory rate and the rate
#       actually assessed on ch99-dutiable entries (rate_prov 69/79)
#   (f) Residual: district-level variation, specific-rate effects, timing
#
# Inputs:
#   data/imdb/imdb_combined.rds  (from 01b_download_imdb.R)
#   tariff-rate-tracker: rate_timeseries.rds, import weights
#
# Outputs:
#   output/fta_decomposition_monthly.csv    -- monthly channel-level breakdown
#   output/fta_decomposition_by_country.csv -- by partner group
#   output/fta_utilization_rates.csv        -- USMCA/FTA utilization rates
#
# Author: John Iselin
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)

here::i_am("R/02b_fta_decomposition.R")
source(here("R", "utils.R"))

cat("=== FTA Utilization Decomposition (Tier 2.5) ===\n\n")

# ==============================================================================
# LOAD DATA
# ==============================================================================

# --- IMDB detail data ---
imdb_path <- here("data", "imdb", "imdb_combined.rds")
if (!file.exists(imdb_path)) {
  stop("IMDB data not found. Run R/01b_download_imdb.R first.")
}
imdb <- readRDS(imdb_path)
cat(sprintf("IMDB data: %s rows, %d months\n",
            format(nrow(imdb), big.mark = ","), n_distinct(imdb$year_month)))

# --- Statutory rates loaded per-month below via load_snapshot_at_date() ---

# --- 2024 import weights (for fixed-weight benchmarks) ---
local_paths <- yaml::read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)
imports_2024 <- readRDS(iw_path) %>%
  group_by(hs10, cty_code) %>%
  summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
  filter(imports > 0) %>%
  mutate(cty_code = as.character(cty_code))

# ==============================================================================
# CLASSIFY PREFERENCE CHANNELS
# ==============================================================================

#' Classify each IMDB entry into a preference channel based on cty_subco and
#' rate_prov codes.
classify_preference <- function(cty_subco, rate_prov, cty_code) {
  case_when(
    # USMCA preferences (CA/MX only)
    cty_subco %in% c("S", "S+", "CA", "MX") & cty_code %in% c("1220", "2010")
      ~ "usmca",
    # KORUS
    cty_subco == "KR" ~ "korus",
    # Other bilateral FTAs
    cty_subco %in% c("AU", "IL", "SG", "CL", "CO", "PE", "PA", "JO",
                      "MA", "OM", "BH", "P", "P+", "R", "JP", "NP")
      ~ "other_fta",
    # GSP / AGOA / CBERA
    cty_subco %in% c("A", "A+", "A*", "D", "E", "E*", "J", "J+", "J*",
                      "W", "Z", "N")
      ~ "gsp_agoa",
    # Free entries (by rate provision, no preference claimed)
    rate_prov %in% c("10", "18", "19") ~ "duty_free",
    # Dutiable at ch99 rates (Section 301, IEEPA, 232, etc.)
    rate_prov %in% c("69", "79") ~ "ch99_dutiable",
    # Dutiable at MFN or special rates
    rate_prov %in% c("61", "62", "64", "70") ~ "mfn_dutiable",
    # FTZ / bonded warehouse
    rate_prov == "00" ~ "ftz_bonded",
    TRUE ~ "other"
  )
}

# Apply classification
imdb <- imdb %>%
  mutate(
    pref_channel = classify_preference(cty_subco, rate_prov, cty_code),
    partner_group = assign_partner_group(cty_code)
  )

# ==============================================================================
# MONTHLY DECOMPOSITION
# ==============================================================================

cat("\n=== Monthly FTA Decomposition ===\n\n")

available_months <- imdb %>%
  filter(year == 2025) %>%
  distinct(year_month) %>%
  arrange(year_month) %>%
  pull(year_month)

monthly_results <- list()
country_results <- list()
utilization_results <- list()

for (ym in available_months) {
  m <- as.integer(substr(ym, 6, 7))
  query_date <- as.Date(paste0(ym, "-01"))
  month_label <- format(query_date, "%b %Y")

  # --- IMDB data for this month ---
  imdb_m <- imdb %>% filter(year_month == ym)
  total_imports <- sum(imdb_m$con_val_mo, na.rm = TRUE)
  total_duties <- sum(imdb_m$cal_dut_mo, na.rm = TRUE)

  # --- Statutory snapshot (memory-efficient: load only this revision) ---
  snapshot <- load_snapshot_at_date(query_date) %>%
    select(hts10, country, total_rate) %>%
    rename(hs10 = hts10, cty_code = country)

  # --- Tier 2: statutory ETR with IMDB monthly weights ---
  # Collapse IMDB to HS10 x country (sum across districts/provisions)
  imdb_hs10 <- imdb_m %>%
    group_by(commodity, cty_code) %>%
    summarize(
      import_val = sum(con_val_mo, na.rm = TRUE),
      cal_dut = sum(cal_dut_mo, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(import_val > 0)

  imdb_with_rates <- imdb_hs10 %>%
    left_join(snapshot, by = c("commodity" = "hs10", "cty_code")) %>%
    mutate(total_rate = coalesce(total_rate, 0))

  tier2 <- weighted.mean(imdb_with_rates$total_rate,
                          w = imdb_with_rates$import_val, na.rm = TRUE)

  # --- Tier 3: Census calculated duty ETR ---
  tier3 <- total_duties / total_imports

  # --- Channel-level decomposition ---
  # For each channel, compute:
  #   (1) Import value entering through this channel
  #   (2) Duties actually paid by entries in this channel
  #   (3) Statutory duties that *would* have been paid at tracker rates
  #   (4) Duty savings = (3) - (2)

  channel_stats <- imdb_m %>%
    # Join statutory rates at entry level
    left_join(snapshot, by = c("commodity" = "hs10", "cty_code")) %>%
    mutate(
      total_rate = coalesce(total_rate, 0),
      statutory_duty = con_val_mo * total_rate,
      actual_duty = coalesce(cal_dut_mo, 0),
      duty_savings = statutory_duty - actual_duty
    ) %>%
    group_by(pref_channel) %>%
    summarize(
      entries = n(),
      imports = sum(con_val_mo, na.rm = TRUE),
      actual_duties = sum(actual_duty, na.rm = TRUE),
      statutory_duties = sum(statutory_duty, na.rm = TRUE),
      duty_savings = sum(duty_savings, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      import_share = imports / total_imports,
      # Contribution to aggregate ETR gap (in pp of total imports)
      gap_contrib_pp = duty_savings / total_imports * 100,
      actual_etr = actual_duties / imports,
      statutory_etr = statutory_duties / imports,
      date = query_date,
      month = month_label
    )

  monthly_results[[ym]] <- channel_stats

  # --- Country x channel detail ---
  country_channel <- imdb_m %>%
    left_join(snapshot, by = c("commodity" = "hs10", "cty_code")) %>%
    mutate(
      total_rate = coalesce(total_rate, 0),
      statutory_duty = con_val_mo * total_rate,
      actual_duty = coalesce(cal_dut_mo, 0),
      duty_savings = statutory_duty - actual_duty
    ) %>%
    group_by(partner_group, pref_channel) %>%
    summarize(
      imports = sum(con_val_mo, na.rm = TRUE),
      actual_duties = sum(actual_duty, na.rm = TRUE),
      statutory_duties = sum(statutory_duty, na.rm = TRUE),
      duty_savings = sum(duty_savings, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      gap_contrib_pp = duty_savings / total_imports * 100,
      date = query_date,
      month = month_label
    )

  country_results[[ym]] <- country_channel

  # --- USMCA / FTA utilization rates ---
  # For CA and MX: what share of imports used USMCA preference?
  for (partner in c("Canada", "Mexico")) {
    cty <- if (partner == "Canada") "1220" else "2010"
    partner_data <- imdb_m %>% filter(cty_code == cty)
    partner_imports <- sum(partner_data$con_val_mo, na.rm = TRUE)

    if (partner_imports > 0) {
      usmca_imports <- partner_data %>%
        filter(cty_subco %in% c("S", "S+", "CA", "MX")) %>%
        pull(con_val_mo) %>%
        sum(na.rm = TRUE)

      utilization_results[[length(utilization_results) + 1]] <- tibble(
        date = query_date,
        month = month_label,
        partner = partner,
        program = "USMCA",
        total_imports = partner_imports,
        preference_imports = usmca_imports,
        utilization_rate = usmca_imports / partner_imports,
        # Also compute the duty savings from USMCA
        usmca_savings = partner_data %>%
          filter(cty_subco %in% c("S", "S+", "CA", "MX")) %>%
          left_join(snapshot, by = c("commodity" = "hs10", "cty_code")) %>%
          mutate(savings = con_val_mo * coalesce(total_rate, 0) -
                   coalesce(cal_dut_mo, 0)) %>%
          pull(savings) %>%
          sum(na.rm = TRUE)
      )
    }
  }

  # KORUS utilization
  kr_data <- imdb_m %>% filter(cty_code == "5800")
  kr_imports <- sum(kr_data$con_val_mo, na.rm = TRUE)
  if (kr_imports > 0) {
    kr_pref <- kr_data %>%
      filter(cty_subco == "KR") %>%
      pull(con_val_mo) %>%
      sum(na.rm = TRUE)

    utilization_results[[length(utilization_results) + 1]] <- tibble(
      date = query_date,
      month = month_label,
      partner = "S. Korea",
      program = "KORUS",
      total_imports = kr_imports,
      preference_imports = kr_pref,
      utilization_rate = kr_pref / kr_imports,
      usmca_savings = NA_real_
    )
  }

  # Print summary
  tier2_3_gap <- (tier2 - tier3) * 100
  top_channels <- channel_stats %>%
    filter(abs(gap_contrib_pp) > 0.01) %>%
    arrange(desc(gap_contrib_pp))

  cat(sprintf("  %s: Tier2=%.2f%% Tier3=%.2f%% Gap=%+.2f pp\n",
              month_label, tier2 * 100, tier3 * 100, tier2_3_gap))
  for (i in seq_len(min(5, nrow(top_channels)))) {
    r <- top_channels[i, ]
    cat(sprintf("    %-20s %+.2f pp  ($%.1fB imports, %.0f%% of total)\n",
                r$pref_channel, r$gap_contrib_pp,
                r$imports / 1e9, r$import_share * 100))
  }

  # Free memory before next iteration
  rm(imdb_m, imdb_hs10, imdb_with_rates, snapshot, channel_stats, country_channel)
  gc(verbose = FALSE)
}

# ==============================================================================
# COMBINE AND SAVE
# ==============================================================================

cat("\n=== Saving Outputs ===\n")
output_dir <- here("output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Monthly channel decomposition
monthly_all <- bind_rows(monthly_results)
write_csv(monthly_all, file.path(output_dir, "fta_decomposition_monthly.csv"))
cat(sprintf("  fta_decomposition_monthly.csv: %d rows\n", nrow(monthly_all)))

# Country x channel detail
country_all <- bind_rows(country_results)
write_csv(country_all, file.path(output_dir, "fta_decomposition_by_country.csv"))
cat(sprintf("  fta_decomposition_by_country.csv: %d rows\n", nrow(country_all)))

# FTA utilization rates
util_all <- bind_rows(utilization_results)
write_csv(util_all, file.path(output_dir, "fta_utilization_rates.csv"))
cat(sprintf("  fta_utilization_rates.csv: %d rows\n", nrow(util_all)))

# ==============================================================================
# SUMMARY TABLE
# ==============================================================================

cat("\n=== Aggregate FTA Decomposition (2025 average) ===\n\n")

monthly_all %>%
  filter(grepl("2025", month)) %>%
  group_by(pref_channel) %>%
  summarize(
    avg_gap_pp = mean(gap_contrib_pp, na.rm = TRUE),
    avg_import_share = mean(import_share, na.rm = TRUE),
    avg_actual_etr = mean(actual_etr, na.rm = TRUE) * 100,
    avg_statutory_etr = mean(statutory_etr, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(abs(avg_gap_pp))) %>%
  mutate(
    gap = sprintf("%+.2f pp", avg_gap_pp),
    share = sprintf("%.1f%%", avg_import_share * 100),
    actual = sprintf("%.1f%%", avg_actual_etr),
    statutory = sprintf("%.1f%%", avg_statutory_etr)
  ) %>%
  select(pref_channel, gap, share, actual, statutory) %>%
  print(n = 15)

cat("\n=== USMCA Utilization Rates ===\n\n")
util_all %>%
  filter(program == "USMCA") %>%
  mutate(
    util = sprintf("%.1f%%", utilization_rate * 100),
    imports_B = sprintf("$%.1fB", total_imports / 1e9),
    savings_B = sprintf("$%.2fB", usmca_savings / 1e9)
  ) %>%
  select(month, partner, util, imports_B, savings_B) %>%
  print(n = 30)

cat("\nDone.\n")
