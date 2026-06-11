# =============================================================================
# 02a_ladder.R — six-tier counterfactual ladder + channel gaps (+ strips)
# =============================================================================
# R port of the retired Stata steps 2 + 3 section A (archive/stata/code/
# 02_counterfactual_ladder.do, 03_etr_analysis.do A), with the S4 -> T timing
# gap newly decomposed via the strip modules ported from tariff-etr-adj.
#
# Tiers (percent; rates x weights over the panel):
#   S0: rate_2024     x imports     (USMCA 2024 baseline x 2024 wts; full mode)
#   S1: rate_h2avg    x imports     (post-July-2025 USMCA x 2024 wts)
#   S2: rate_h2avg    x con_val_mo  (              "      x monthly wts)
#   S3: rate_all_pref x con_val_mo  (+ non-USMCA preferences)
#   S4: sum(cal_dut_mo)/sum(con_val_mo)   (Census collected)
#   T : Treasury actual ETR
#
# Channels: gap_adjustment (S0-S1, full mode), gap_diversion (S1-S2),
# gap_others (S2-S3), gap_residual (S3-S4), gap_timing (S4-T). gap_timing is
# further split into gap_timing_deminimis + gap_timing_adcvd +
# gap_timing_residual using the strip estimates (collection channels that
# reach Treasury but structurally cannot appear in Census cal_dut_mo).
#
# Outputs (results/tables/): counterfactual_ladder.csv (tracker_vintage
# stamped), counterfactual_by_country.csv (+ _avg), decomp_monthly.csv
# (stamped), baseline_etr.csv, daily_etr.csv, revenue_monthly.csv.
# =============================================================================

here::i_am("code/02a_ladder.R")
setwd(here::here())
source("code/utils.R")
source("code/strips/adcvd_strip.R")
source("code/strips/deminimis_strip.R")

msg("[02a] Counterfactual ladder...")
panel   <- readRDS(file.path(DIR_PROCESSED, "panel.rds"))
HAVE_S0 <- isTRUE(attr(panel, "have_s0"))
VINTAGE <- tracker_vintage()
if (!HAVE_S0) msg("  publish mode: S0 absent -- ladder runs S1-S4 + T")

# --- Treasury revenue ---------------------------------------------------------
rev <- read_csv(file.path(DIR_RAW, "tariff_revenue.csv"),
                show_col_types = FALSE) %>%
  mutate(year_month = substr(date, 1, 7)) %>%
  filter(year_month >= ANALYSIS_LO, year_month <= ANALYSIS_HI) %>%
  select(year_month, customs_duties, imports_value, effective_rate)
stopifnot(all(rev$effective_rate >= 0 & rev$effective_rate < 100, na.rm = TRUE))
write_csv(rev, file.path(DIR_TABLES, "revenue_monthly.csv"))

# --- Aggregate ladder -----------------------------------------------------------
msg("  [B] Aggregate tiers...")
tiers <- list(
  if (HAVE_S0) compute_tier(panel, "rate_2024", "imports", "s0"),
  compute_tier(panel, "rate_h2avg",    "imports",    "s1"),
  compute_tier(panel, "rate_h2avg",    "con_val_mo", "s2"),
  compute_tier(panel, "rate_all_pref", "con_val_mo", "s3"),
  panel %>% group_by(year_month) %>%
    summarise(s4 = 100 * sum(cal_dut_mo) / sum(con_val_mo), .groups = "drop"),
  rev %>% transmute(year_month, t = effective_rate))
ladder <- Reduce(function(a, b) full_join(a, b, by = "year_month"),
                 Filter(Negate(is.null), tiers)) %>%
  arrange(year_month)

stopifnot(nrow(ladder) > 0,
          !anyNA(ladder$s1), !anyNA(ladder$s2),
          !anyNA(ladder$s3), !anyNA(ladder$s4))
if (anyNA(ladder$t))
  msg("  WARNING: Treasury T missing for %d months", sum(is.na(ladder$t)))

# --- S4 -> T decomposition via strips -------------------------------------------
# Both channels are dollars that reach Treasury with no Census entry-summary
# counterpart; expressing them over the Treasury import base converts to pp of
# the T denominator. (T = customs_duties / imports_value, both $M.)
msg("  [strips] Decomposing gap_timing (S4 - T)...")
census_duty <- panel %>% group_by(year_month) %>%
  summarise(cen_duty = sum(cal_dut_mo), .groups = "drop")
dm  <- deminimis_monthly_usd(census_duty,
                             rev %>% select(year_month, customs_duties))
adc <- adcvd_monthly_usd()

ladder <- ladder %>%
  left_join(rev %>% select(year_month, imports_value), by = "year_month") %>%
  left_join(dm, by = "year_month") %>%
  mutate(
    gap_diversion = s1 - s2,
    gap_others    = s2 - s3,
    gap_residual  = s3 - s4,
    gap_timing    = s4 - t,
    # channel components are NEGATIVE contributions to S4 - T (they raise T
    # above what Census can see), so they enter with sign flipped:
    gap_timing_deminimis = -100 * coalesce(deminimis_usd, 0) /
                             (imports_value * 1e6),
    gap_timing_adcvd     = -100 * coalesce(adc, 0) / (imports_value * 1e6),
    gap_timing_residual  = gap_timing - gap_timing_deminimis - gap_timing_adcvd)
if (HAVE_S0) ladder <- ladder %>%
  mutate(gap_adjustment = s0 - s1, gap_total = s0 - t)
ladder <- ladder %>% select(-imports_value, -deminimis_usd) %>%
  mutate(tracker_vintage = VINTAGE)

write_csv(ladder, file.path(DIR_TABLES, "counterfactual_ladder.csv"))
write_csv(ladder, file.path(DIR_TABLES, "decomp_monthly.csv"))
msg("  ladder (percent):")
print(as.data.frame(ladder %>%
  select(year_month, any_of(c("s0")), s1, s2, s3, s4, t) %>%
  mutate(across(where(is.numeric), ~round(.x, 2)))), row.names = FALSE)

# --- Country ladder (no T: Treasury is not by-country) ---------------------------
msg("  [D] Country ladder...")
cty <- list(
  if (HAVE_S0) compute_tier(panel, "rate_2024", "imports", "s0", by = "partner_group"),
  compute_tier(panel, "rate_h2avg",    "imports",    "s1", by = "partner_group"),
  compute_tier(panel, "rate_h2avg",    "con_val_mo", "s2", by = "partner_group"),
  compute_tier(panel, "rate_all_pref", "con_val_mo", "s3", by = "partner_group"),
  panel %>% group_by(year_month, partner_group) %>%
    summarise(s4 = 100 * sum(cal_dut_mo) / sum(con_val_mo), .groups = "drop"))
by_country <- Reduce(function(a, b)
  full_join(a, b, by = c("year_month", "partner_group")),
  Filter(Negate(is.null), cty)) %>%
  mutate(gap_diversion = s1 - s2, gap_others = s2 - s3,
         gap_residual = s3 - s4) %>%
  arrange(year_month, partner_group)
if (HAVE_S0) by_country <- by_country %>% mutate(gap_adjustment = s0 - s1)
write_csv(by_country, file.path(DIR_TABLES, "counterfactual_by_country.csv"))

by_country %>%
  group_by(partner_group) %>%
  summarise(across(where(is.numeric), mean), .groups = "drop") %>%
  write_csv(file.path(DIR_TABLES, "counterfactual_by_country_avg.csv"))

# --- Baseline ETR table (ports 03b section A data build) -------------------------
# The tracker's daily statutory ETR collapsed to monthly equals S1 by
# construction (same rate panel x same 2024 weights); exporting both makes the
# alignment visible and feeds the paper's 4.1 baseline figure in 03b.
msg("  [baseline] Daily-tracker monthly mean vs Treasury...")
daily <- read_csv(file.path(DIR_RAW, "daily_overall.csv"),
                  show_col_types = FALSE) %>%
  transmute(date = as.Date(date), revision,
            weighted_etr = 100 * weighted_etr,
            matched_imports_b, total_imports_b) %>%
  filter(substr(date, 1, 7) >= ANALYSIS_LO, substr(date, 1, 7) <= ANALYSIS_HI)
write_csv(daily, file.path(DIR_TABLES, "daily_etr.csv"))

daily %>%
  mutate(year_month = substr(date, 1, 7)) %>%
  group_by(year_month) %>%
  summarise(t1_h2avg = mean(weighted_etr), .groups = "drop") %>%
  left_join(rev %>% transmute(year_month, t4 = effective_rate),
            by = "year_month") %>%
  left_join(ladder %>% select(year_month, s1), by = "year_month") %>%
  mutate(gap = t1_h2avg - t4) %>%
  write_csv(file.path(DIR_TABLES, "baseline_etr.csv"))

write_run_meta("02a_ladder",
               notes = sprintf("have_s0=%s; deminimis=%s; adcvd=%s",
                               HAVE_S0,
                               !all(dm$deminimis_usd == 0),
                               is.finite(adc)))
msg("[02a] done.")
