# =============================================================================
# 02b_decomposition.R — channel decompositions by country and product
# =============================================================================
# R port of the analysis core of the retired Stata step 3 (archive/stata/code/
# 03_etr_analysis.do sections B, B2, B3, B5, and the cmp_* table builds of
# sections D/D7/D8). Figures live in 03a; this script writes CSVs only.
#
#   1. S1 -> S2 trade diversion: Shapley two-way (between/within) under the
#      country and product partitions. Both lenses sum to gap_diversion.
#   2. S2 -> S3 (other preferences) and S3 -> S4 (residual): per-group dollar
#      attribution at fixed monthly weights.
#   3. S0 -> S1 (USMCA adjustment) attribution at 2024 weights — full mode only.
#   4. Unified per-group attribution tables (4 channels x month x group).
#   5. cmp_* comparison tables: S2 vs S4 vs T overall / by partner / by
#      product / HS2 ranking / top-HS10 anomalies / S1 vs S2 by group.
#
# Every decomposition is validated against the ladder: per-month group sums
# must reproduce the aggregate channel to 1e-3 pp (warns if not, mirroring
# the Stata checks).
# =============================================================================

here::i_am("code/02b_decomposition.R")
setwd(here::here())
source("code/utils.R")

msg("[02b] Channel decompositions...")
panel   <- readRDS(file.path(DIR_PROCESSED, "panel.rds"))
HAVE_S0 <- isTRUE(attr(panel, "have_s0"))
ladder  <- read_csv(file.path(DIR_TABLES, "counterfactual_ladder.csv"),
                    show_col_types = FALSE)

check_sums <- function(df, val, target, label, tol = 1e-3) {
  resid <- df %>%
    group_by(year_month) %>%
    summarise(s = sum(.data[[val]]), .groups = "drop") %>%
    left_join(ladder %>% select(year_month, tgt = all_of(target)),
              by = "year_month") %>%
    mutate(r = abs(s - tgt))
  if (max(resid$r, na.rm = TRUE) > tol)
    warning(sprintf("%s: group sums differ from %s by up to %.4f pp",
                    label, target, max(resid$r, na.rm = TRUE)))
  else msg("      %s: max residual vs %s = %.2e pp (OK)",
           label, target, max(resid$r, na.rm = TRUE))
}

# --- 1. S1 -> S2 Shapley diversion ---------------------------------------------
msg("  [B] S1 -> S2 Shapley (country + product lenses)...")
div_c <- shapley_decomp(panel, "rate_h2avg", "partner_group")
div_p <- shapley_decomp(panel, "rate_h2avg", "product_group")
check_sums(div_c, "total", "gap_diversion", "country lens")
check_sums(div_p, "total", "gap_diversion", "product lens")
write_csv(div_c, file.path(DIR_TABLES, "diversion_by_country.csv"))
write_csv(div_p, file.path(DIR_TABLES, "diversion_by_product.csv"))
div_c %>% group_by(partner_group) %>%
  summarise(across(c(between, within, total), mean), .groups = "drop") %>%
  arrange(desc(total)) %>%
  write_csv(file.path(DIR_TABLES, "diversion_by_country_avg.csv"))
div_p %>% group_by(product_group) %>%
  summarise(across(c(between, within, total), mean), .groups = "drop") %>%
  arrange(desc(total)) %>%
  write_csv(file.path(DIR_TABLES, "diversion_by_product_avg.csv"))

# --- 2./3. Per-group attributions ------------------------------------------------
msg("  [B2/B3] S2->S3 and S3->S4 attributions...")
oth_c <- per_group_attribution(panel, "rate_h2avg", "rate_all_pref",
                               "con_val_mo", "partner_group", "others_pp")
oth_p <- per_group_attribution(panel, "rate_h2avg", "rate_all_pref",
                               "con_val_mo", "product_group", "others_pp")
res_c <- per_group_attribution(panel, "rate_all_pref", "census_etr",
                               "con_val_mo", "partner_group", "residual_pp")
res_p <- per_group_attribution(panel, "rate_all_pref", "census_etr",
                               "con_val_mo", "product_group", "residual_pp")
check_sums(oth_c, "others_pp",   "gap_others",   "others by country")
check_sums(res_c, "residual_pp", "gap_residual", "residual by country")

adj_c <- adj_p <- NULL
if (HAVE_S0) {
  msg("  [B5] S0->S1 adjustment attribution (full mode)...")
  adj_c <- per_group_attribution(panel, "rate_2024", "rate_h2avg",
                                 "imports", "partner_group", "adjustment_pp")
  adj_p <- per_group_attribution(panel, "rate_2024", "rate_h2avg",
                                 "imports", "product_group", "adjustment_pp")
}

# --- 4. Unified attribution tables -------------------------------------------------
attr_join <- function(div, oth, res, adj, by) {
  out <- div %>% select(year_month, all_of(by), diversion_pp = total) %>%
    left_join(oth, by = c("year_month", by)) %>%
    left_join(res, by = c("year_month", by))
  out <- if (is.null(adj)) mutate(out, adjustment_pp = NA_real_)
         else left_join(out, adj, by = c("year_month", by))
  out %>% select(year_month, all_of(by), adjustment_pp, diversion_pp,
                 others_pp, residual_pp) %>%
    arrange(year_month, .data[[by]])
}
write_csv(attr_join(div_c, oth_c, res_c, adj_c, "partner_group"),
          file.path(DIR_TABLES, "attribution_by_country.csv"))
write_csv(attr_join(div_p, oth_p, res_p, adj_p, "product_group"),
          file.path(DIR_TABLES, "attribution_by_product.csv"))

# --- 5. S2 vs S4 vs T comparison tables --------------------------------------------
msg("  [D] cmp_* comparison tables...")
# overall (s2/s4 recomputed row-level so the table is self-contained)
ladder %>%
  select(year_month, s2, s4, t) %>%
  mutate(gap_s2_s4 = s2 - s4, gap_s4_t = s4 - t, gap_s2_t = s2 - t) %>%
  write_csv(file.path(DIR_TABLES, "cmp_overall_monthly.csv"))

cmp_by <- function(by) {
  panel %>%
    group_by(year_month, across(all_of(by))) %>%
    summarise(stat_num  = sum(rate_h2avg * con_val_mo),
              cens_num  = sum(cal_dut_mo),
              total_val = sum(con_val_mo), .groups = "drop") %>%
    mutate(s2 = 100 * safe_divide(stat_num, total_val, 0),
           s4 = 100 * safe_divide(cens_num, total_val, 0),
           gap_pp  = s2 - s4,
           gap_usd = stat_num - cens_num) %>%
    group_by(year_month) %>%
    mutate(gap_contrib_pp = 100 * (stat_num - cens_num) / sum(total_val)) %>%
    ungroup()
}
write_csv(cmp_by("partner_group"),
          file.path(DIR_TABLES, "cmp_partner_monthly.csv"))
write_csv(cmp_by("product_group"),
          file.path(DIR_TABLES, "cmp_product_monthly.csv"))

# product x partner period-average grid (03a heatmap input)
panel %>%
  group_by(product_group, partner_group) %>%
  summarise(stat_num = sum(rate_h2avg * con_val_mo),
            cens_num = sum(cal_dut_mo),
            total_val = sum(con_val_mo), .groups = "drop") %>%
  mutate(s2 = 100 * safe_divide(stat_num, total_val, 0),
         s4 = 100 * safe_divide(cens_num, total_val, 0),
         gap_pp = s2 - s4) %>%
  write_csv(file.path(DIR_TABLES, "cmp_product_partner_avg.csv"))

# HS2 ranking + top-HS10 anomalies (period-aggregated)
panel %>%
  group_by(hs2) %>%
  summarise(stat_num = sum(rate_h2avg * con_val_mo),
            cens_num = sum(cal_dut_mo),
            total_val = sum(con_val_mo), .groups = "drop") %>%
  mutate(s2 = 100 * safe_divide(stat_num, total_val, 0),
         s4 = 100 * safe_divide(cens_num, total_val, 0),
         gap_pp = s2 - s4, gap_usd = stat_num - cens_num) %>%
  arrange(desc(abs(gap_usd))) %>%
  write_csv(file.path(DIR_TABLES, "cmp_hs2_ranking.csv"))

panel %>%
  group_by(hs10, cty_code, partner_group, product_group) %>%
  summarise(stat_num = sum(rate_h2avg * con_val_mo),
            cens_num = sum(cal_dut_mo),
            total_val = sum(con_val_mo), .groups = "drop") %>%
  filter(total_val > 0) %>%
  mutate(s2 = 100 * safe_divide(stat_num, total_val, 0),
         s4 = 100 * safe_divide(cens_num, total_val, 0),
         gap_pp = s2 - s4, gap_usd = stat_num - cens_num) %>%
  slice_max(abs(gap_usd), n = 200) %>%
  write_csv(file.path(DIR_TABLES, "cmp_top_hs10_anomalies.csv"))

# S1 vs S2 by group (composition-shift lens, 03a facet input)
s1s2_by <- function(by) {
  panel %>%
    group_by(year_month, across(all_of(by))) %>%
    summarise(s1_num = sum(rate_h2avg * imports),
              s2_num = sum(rate_h2avg * con_val_mo),
              imports = sum(imports), con_val_mo = sum(con_val_mo),
              .groups = "drop") %>%
    mutate(s1 = 100 * safe_divide(s1_num, imports, 0),
           s2 = 100 * safe_divide(s2_num, con_val_mo, 0),
           gap_s1_s2 = s1 - s2)
}
write_csv(s1s2_by("partner_group"),
          file.path(DIR_TABLES, "cmp_s1s2_country_monthly.csv"))
write_csv(s1s2_by("product_group"),
          file.path(DIR_TABLES, "cmp_s1s2_product_monthly.csv"))

write_run_meta("02b_decomposition", notes = sprintf("have_s0=%s", HAVE_S0))
msg("[02b] done.")
