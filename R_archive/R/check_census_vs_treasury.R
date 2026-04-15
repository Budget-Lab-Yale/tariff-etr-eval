# ==============================================================================
# check_census_vs_treasury.R
#
# Compare Census calculated duties (CAL_DUT_MO) to Treasury actual collections
# at the aggregate level, and explore country-level Census duty data for
# potential residual allocation.
# ==============================================================================

library(here)
here::i_am("run_all.R")
source(here("R", "utils.R"))

# --- Load data ---
census <- load_census_trade()
treasury <- load_actual_etr() %>%
  filter(date >= "2024-01-01") %>%
  mutate(treasury_etr = effective_rate / 100)

# --- (A) Aggregate Census vs Treasury ---
cat("=== (A) Aggregate Census vs Treasury ===\n\n")

# Back out calculated duty from effective_rate (= cal_dut_mo / con_val_mo * 100)
census <- census %>%
  mutate(cal_duty = effective_rate / 100 * con_val_mo)

census_agg <- census %>%
  group_by(date, year, month) %>%
  summarize(
    total_imports = sum(con_val_mo, na.rm = TRUE),
    total_cal_duty = sum(cal_duty, na.rm = TRUE),
    total_dut_val = sum(dut_val_mo, na.rm = TRUE),
    n_countries = n_distinct(cty_code),
    .groups = "drop"
  ) %>%
  mutate(
    census_etr = total_cal_duty / total_imports,
    dutiable_share = total_dut_val / total_imports
  )

comparison <- census_agg %>%
  inner_join(treasury %>% select(date, customs_duties, imports_value, treasury_etr),
             by = "date") %>%
  mutate(
    gap_pp = (census_etr - treasury_etr) * 100,
    # Treasury is in $M, Census is in $
    treasury_imports_M = imports_value,
    census_imports_M = total_imports / 1e6,
    import_ratio = census_imports_M / treasury_imports_M
  )

cat("Monthly comparison (2024-2026):\n")
comparison %>%
  mutate(
    month_label = format(date, "%b %Y"),
    census_pct = sprintf("%.2f", census_etr * 100),
    treasury_pct = sprintf("%.2f", treasury_etr * 100),
    gap = sprintf("%+.2f", gap_pp),
    imp_ratio = sprintf("%.3f", import_ratio)
  ) %>%
  select(month_label, census_pct, treasury_pct, gap, imp_ratio) %>%
  print(n = 40)

cat("\n\nSummary stats on Census-Treasury gap:\n")
cat(sprintf("  Mean gap: %+.2f pp\n", mean(comparison$gap_pp, na.rm = TRUE)))
cat(sprintf("  SD gap: %.2f pp\n", sd(comparison$gap_pp, na.rm = TRUE)))
cat(sprintf("  Min gap: %+.2f pp\n", min(comparison$gap_pp, na.rm = TRUE)))
cat(sprintf("  Max gap: %+.2f pp\n", max(comparison$gap_pp, na.rm = TRUE)))
cat(sprintf("  Correlation (ETR levels): %.4f\n",
            cor(comparison$census_etr, comparison$treasury_etr)))
cat(sprintf("  Mean import ratio (Census/Treasury): %.3f\n",
            mean(comparison$import_ratio)))

# --- (B) Census duty ETR by country ---
cat("\n\n=== (B) Census Duty ETR by Country ===\n\n")

census_by_country <- census %>%
  filter(year >= 2025) %>%
  mutate(partner_group = assign_partner_group(as.character(cty_code))) %>%
  group_by(date, partner_group) %>%
  summarize(
    imports = sum(con_val_mo, na.rm = TRUE),
    cal_duty = sum(cal_duty, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(census_etr = cal_duty / imports)

cat("Census calculated duty ETR by partner (2025+):\n")
census_by_country %>%
  mutate(
    month_label = format(date, "%b %Y"),
    etr_pct = sprintf("%.2f%%", census_etr * 100),
    imports_B = sprintf("$%.1fB", imports / 1e9)
  ) %>%
  select(month_label, partner_group, etr_pct, imports_B) %>%
  tidyr::pivot_wider(names_from = partner_group, values_from = c(etr_pct, imports_B)) %>%
  print(n = 20)

# --- (C) Census aggregate duty vs Treasury, with country contributions ---
cat("\n\n=== (C) Allocating the Treasury Residual via Census ===\n\n")

# For each month: compute each country's share of Census total cal_duty
# Then scale to match Treasury actual collections
census_country_shares <- census %>%
  filter(year >= 2025) %>%
  mutate(partner_group = assign_partner_group(as.character(cty_code))) %>%
  group_by(date, partner_group) %>%
  summarize(
    cal_duty = sum(cal_duty, na.rm = TRUE),
    imports = sum(con_val_mo, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(date) %>%
  mutate(
    duty_share = cal_duty / sum(cal_duty),
    import_share = imports / sum(imports)
  ) %>%
  ungroup()

# Join with Treasury actuals to compute allocated residual
treasury_2025 <- treasury %>%
  filter(date >= "2025-01-01") %>%
  select(date, treasury_etr, customs_duties, imports_value)

census_total <- census_agg %>%
  filter(date >= "2025-01-01") %>%
  select(date, census_etr, total_cal_duty, total_imports)

residual_allocation <- census_country_shares %>%
  inner_join(treasury_2025, by = "date") %>%
  inner_join(census_total %>% select(date, census_etr_agg = census_etr), by = "date") %>%
  mutate(
    # Country's Census ETR contribution = country_duty / total_imports
    census_etr_contrib = cal_duty / sum(imports),
    # Allocated Treasury actual = Treasury total * country's duty share
    allocated_treasury_duty = customs_duties * 1e6 * duty_share,
    allocated_treasury_etr = allocated_treasury_duty / imports
  )

cat("Country duty shares and Census vs Treasury ETR (2025):\n")
residual_allocation %>%
  mutate(
    month_label = format(date, "%b %Y"),
    duty_share_pct = sprintf("%.1f%%", duty_share * 100),
    census_etr_pct = sprintf("%.2f%%", (cal_duty / imports) * 100),
    alloc_treasury_pct = sprintf("%.2f%%", allocated_treasury_etr * 100)
  ) %>%
  select(month_label, partner_group, duty_share_pct, census_etr_pct, alloc_treasury_pct) %>%
  tidyr::pivot_wider(
    names_from = partner_group,
    values_from = c(duty_share_pct, census_etr_pct, alloc_treasury_pct)
  ) %>%
  print(n = 20, width = 200)

cat("\n\nKey question: how stable are country duty shares across months?\n")
share_stability <- census_country_shares %>%
  filter(date >= "2025-01-01") %>%
  group_by(partner_group) %>%
  summarize(
    mean_share = mean(duty_share),
    sd_share = sd(duty_share),
    cv = sd(duty_share) / mean(duty_share),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_share))

cat("Country duty share stability:\n")
share_stability %>%
  mutate(
    mean_pct = sprintf("%.1f%%", mean_share * 100),
    sd_pct = sprintf("%.1f%%", sd_share * 100),
    cv_pct = sprintf("%.1f%%", cv * 100)
  ) %>%
  select(partner_group, mean_pct, sd_pct, cv_pct) %>%
  print()
