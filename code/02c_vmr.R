# =============================================================================
# 02c_vmr.R — value-misreporting decomposition (tables)
# =============================================================================
# Successor to code/R/09_value_misreporting.R under the 01/02/03 pipeline
# layout: identical method and parameters, but (i) the statutory rate path
# comes from data/processed/panel.rds instead of the Stata merged_analysis.dta,
# and (ii) figures moved to 03a_figures_framework.R (this script writes the
# vmr_* CSVs only, including the flow-level sample the scatter draws from).
#
# Method (docs/value_misreporting_methodology.md; v2 upgrade proposal in
# docs/vmr_v2_proposal.md): within a flow (HS10 x country) the identity
#   dln(value) = dln(quantity) + dln(unit_value)
# decomposes each post-tariff value change. Value down with quantity flat
# (bucket B2) implies the unit value collapsed -- a misreporting signal. The
# strict signal additionally requires the unit-value drop to exceed that of
# untariffed origins of the same HS10 (cross-partner, within-product control).
# Eta is structurally blind to this channel: under-invoicing scales duty and
# value proportionally, leaving duty/value unchanged.
# =============================================================================

here::i_am("code/02c_vmr.R")
setwd(here::here())
source("code/utils.R")
suppressPackageStartupMessages(library(data.table))

# ---- Parameters (unchanged from 09_value_misreporting.R) --------------------
WIN_LO        <- 780L   # 2025m1 (Stata %tm)
WIN_HI        <- 794L   # 2026m3
LOAD_LO       <- 768L   # 2024m1: pre-windows / fixed baseline reach into 2024
T_V           <- 0.10
T_Q           <- 0.10
T_W           <- 0.10
DRATE_THRESH  <- 0.03
CTRL_DRATE_MAX<- 0.01
MIN_CTRL      <- 2L
VALUE_FLOOR   <- 1e5
PRE_OFFSETS   <- -3:-1
POST_OFFSETS  <-  2:4
EVENT_MODE    <- "flow"
FIXED_EVENT_YM<- 783L
QTY_MODE      <- "qy1"
DRY_RUN       <- FALSE

msg("[02c] Value-misreporting decomposition...")

# ---------------------------------------------------------------------------
# 1. Load: value/quantity (augmented IMDB CSV) + statutory rate path (panel)
# ---------------------------------------------------------------------------
msg("  [1] Loading IMDB aggregate + rate path...")
agg <- fread(file.path(DIR_RAW, "imdb_hs10_country_monthly.csv"),
             colClasses = list(character = c("hs10", "cty_code", "year_month")),
             showProgress = FALSE) %>% as_tibble()
need <- c("con_qy1_mo", "ship_wgt_mo")
miss <- setdiff(need, names(agg))
if (length(miss) > 0)
  stop("Augmented columns missing from IMDB CSV: ", paste(miss, collapse = ", "),
       "\n  Run: Rscript code/01a_pull_raw_data.R --only-imdb", call. = FALSE)

agg <- agg %>%
  mutate(ym = ym_int(year_month)) %>%
  filter(ym >= LOAD_LO, ym <= WIN_HI, con_val_mo > 0)

rates <- readRDS(file.path(DIR_PROCESSED, "panel.rds")) %>%
  transmute(hs10, cty_code, ym = ym_int(year_month), rate_h2avg)

product_groups <- read_csv("resources/product_groups.csv",
                           col_types = cols(.default = col_character()))

flows <- agg %>%
  left_join(rates, by = c("hs10", "cty_code", "ym")) %>%
  mutate(rate_h2avg    = coalesce(rate_h2avg, 0),   # 2024 months: no tariffs
         hs2           = substr(hs10, 1, 2),
         partner_group = as.character(assign_partner_group(cty_code))) %>%
  left_join(product_groups, by = "hs2") %>%
  mutate(product_group = coalesce(product_group, "Other Manufactured"))

if (DRY_RUN) {
  flows <- flows %>% filter(partner_group == "China", ym >= 782L, ym <= 784L)
  msg("    DRY_RUN: China only, 2025m3-m5 (%s rows)",
      format(nrow(flows), big.mark = ","))
}
msg("    flows: %s cell-months", format(nrow(flows), big.mark = ","))

# ---------------------------------------------------------------------------
# 2. Unit value: physical anchor, flag unmeasurable flows
# ---------------------------------------------------------------------------
msg("  [2] Unit value (anchor = %s)...", QTY_MODE)
flows <- flows %>%
  mutate(
    qty = if (QTY_MODE == "weight") {
      if_else(ship_wgt_mo > 0, ship_wgt_mo, NA_real_)
    } else {
      case_when(con_qy1_mo > 0 ~ con_qy1_mo,
                ship_wgt_mo > 0 ~ ship_wgt_mo,
                TRUE ~ NA_real_)
    },
    unit_value = if_else(!is.na(qty) & qty > 0, con_val_mo / qty, NA_real_))
if (QTY_MODE == "weight")
  flows <- flows %>% filter(!(partner_group %in% c("Canada", "Mexico")))

cov_total <- sum(flows$con_val_mo)
cov_noqty <- sum(flows$con_val_mo[is.na(flows$qty)])
msg("    no-quantity value share: %.1f%%", 100 * cov_noqty / cov_total)

mf <- flows %>%
  filter(!is.na(qty), qty > 0, con_val_mo > 0) %>%
  select(hs10, cty_code, partner_group, product_group, hs2, ym,
         value = con_val_mo, qty, rate_h2avg)

# ---------------------------------------------------------------------------
# 3. Tariff-change event per flow
# ---------------------------------------------------------------------------
msg("  [3] Events (mode = %s)...", EVENT_MODE)
flow_rate <- mf %>%
  distinct(hs10, cty_code, ym, rate_h2avg) %>%
  filter(ym >= WIN_LO, ym <= WIN_HI) %>%
  arrange(hs10, cty_code, ym) %>%
  group_by(hs10, cty_code) %>%
  mutate(drate = rate_h2avg - lag(rate_h2avg)) %>%
  ungroup()

events <- flow_rate %>%
  filter(!is.na(drate), drate >= DRATE_THRESH) %>%
  group_by(hs10, cty_code) %>%
  slice_max(drate, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  transmute(hs10, cty_code, event_ym = ym, event_drate = drate)
if (EVENT_MODE == "fixed") events <- events %>% mutate(event_ym = FIXED_EVENT_YM)
msg("    %s flows with a >=%.0fpp tariff step",
    format(nrow(events), big.mark = ","), 100 * DRATE_THRESH)
if (nrow(events) == 0) stop("No flows with a tariff step in the window.")

# ---------------------------------------------------------------------------
# 4./6. Window aggregation, dln decomposition, cross-partner control
# ---------------------------------------------------------------------------
msg("  [4/6] Window decomposition + cross-partner control...")
window_agg_for_E <- function(E) {
  pre  <- E + PRE_OFFSETS
  post <- E + POST_OFFSETS
  w <- mf %>%
    filter(ym %in% c(pre, post)) %>%
    mutate(win = if_else(ym %in% pre, "pre", "post")) %>%
    group_by(hs10, cty_code, partner_group, product_group, hs2, win) %>%
    summarise(V = mean(value), Q = mean(qty), rate = mean(rate_h2avg),
              .groups = "drop") %>%
    pivot_wider(names_from = win, values_from = c(V, Q, rate))
  for (col in c("V_pre","V_post","Q_pre","Q_post","rate_pre","rate_post"))
    if (!col %in% names(w)) w[[col]] <- NA_real_
  w %>%
    filter(!is.na(V_pre), !is.na(V_post), V_pre > 0, V_post > 0,
           Q_pre > 0, Q_post > 0) %>%
    mutate(uv_pre = V_pre / Q_pre, uv_post = V_post / Q_post,
           dln_value = log(V_post) - log(V_pre),
           dln_qty   = log(Q_post) - log(Q_pre),
           dln_uv    = log(uv_post) - log(uv_pre),
           drate_win = coalesce(rate_post, 0) - coalesce(rate_pre, 0),
           event_ym  = E)
}

per_E <- lapply(sort(unique(events$event_ym)), function(E) {
  w <- window_agg_for_E(E)
  if (nrow(w) == 0) return(NULL)
  ctrl <- w %>%
    filter(abs(drate_win) <= CTRL_DRATE_MAX) %>%
    group_by(hs10) %>%
    summarise(world_uv_pre  = sum(V_pre)  / sum(Q_pre),
              world_uv_post = sum(V_post) / sum(Q_post),
              n_ctrl = dplyr::n(), .groups = "drop") %>%
    mutate(world_dln_uv = log(world_uv_post) - log(world_uv_pre)) %>%
    select(hs10, world_dln_uv, n_ctrl)
  treated <- events %>% filter(event_ym == E) %>%
    select(hs10, cty_code, event_drate)
  w %>%
    inner_join(treated, by = c("hs10", "cty_code")) %>%
    left_join(ctrl, by = "hs10")
})
flow_dln <- bind_rows(per_E) %>%
  mutate(id_resid      = dln_value - dln_qty - dln_uv,
         dln_uv_excess = dln_uv - world_dln_uv)
msg("    %s treated flows; max |identity residual| = %.2e",
    format(nrow(flow_dln), big.mark = ","), max(abs(flow_dln$id_resid)))

# ---------------------------------------------------------------------------
# 5. Bucket classification + strict signal
# ---------------------------------------------------------------------------
msg("  [5] Classifying...")
flow_class <- flow_dln %>%
  mutate(
    bucket = case_when(
      dln_value < -T_V & dln_qty < -T_Q          ~ "B1_real_contraction",
      dln_value < -T_V & abs(dln_qty) <= T_Q     ~ "B2_misreport_suspect",
      abs(dln_value) <= T_V & dln_qty < -T_Q     ~ "B3_quantity_driven",
      dln_value >  T_V & dln_qty >  T_Q          ~ "B4_real_expansion",
      dln_value >  T_V & abs(dln_qty) <= T_Q     ~ "B5_unit_value_spike",
      TRUE                                        ~ "B6_mixed"),
    suspect        = bucket == "B2_misreport_suspect",
    suspect_strict = suspect & !is.na(dln_uv_excess) &
                     n_ctrl >= MIN_CTRL & dln_uv_excess < -T_W,
    lumpy       = V_pre < VALUE_FLOOR,
    classify_ok = !lumpy)

bt <- flow_class %>% filter(classify_ok) %>% count(bucket) %>%
  mutate(share = n / sum(n))
for (i in seq_len(nrow(bt)))
  msg("      %-22s n=%6s  (%.1f%%)", bt$bucket[i],
      format(bt$n[i], big.mark = ","), 100 * bt$share[i])

# ---------------------------------------------------------------------------
# 7./8. Aggregate + write tables
# ---------------------------------------------------------------------------
msg("  [7/8] Aggregating + writing tables...")
agg_one <- function(df, gvars) {
  df %>%
    filter(classify_ok) %>%
    group_by(across(all_of(gvars))) %>%
    summarise(
      n_flows            = dplyr::n(),
      n_suspect          = sum(suspect),
      n_suspect_strict   = sum(suspect_strict, na.rm = TRUE),
      val_total          = sum(V_post),
      val_suspect        = sum(V_post[suspect]),
      val_suspect_strict = sum(V_post[suspect_strict %in% TRUE]),
      share_suspect_value        = val_suspect / val_total,
      share_suspect_strict_value = val_suspect_strict / val_total,
      mean_dln_value    = weighted.mean(dln_value, V_post),
      mean_dln_qty      = weighted.mean(dln_qty,   V_post),
      mean_dln_uv       = weighted.mean(dln_uv,    V_post),
      mean_world_dln_uv = weighted.mean(world_dln_uv, V_post, na.rm = TRUE),
      .groups = "drop")
}

write_csv(agg_one(flow_class, c("partner_group", "product_group")),
          file.path(DIR_TABLES, "vmr_decomp_by_partner_product.csv"))
write_csv(agg_one(flow_class, "partner_group"),
          file.path(DIR_TABLES, "vmr_decomp_by_partner.csv"))
write_csv(agg_one(flow_class, "product_group"),
          file.path(DIR_TABLES, "vmr_decomp_by_product.csv"))
write_csv(flow_class %>% filter(partner_group == "China") %>%
            agg_one("hs2") %>% arrange(desc(val_total)),
          file.path(DIR_TABLES, "vmr_decomp_china_by_hs2.csv"))

flow_class %>%
  arrange(desc(V_post)) %>%
  transmute(hs10, cty_code, partner_group, product_group, hs2, event_ym,
            event_drate, V_pre, V_post, Q_pre, Q_post, uv_pre, uv_post,
            dln_value, dln_qty, dln_uv, world_dln_uv, dln_uv_excess, n_ctrl,
            bucket, suspect, suspect_strict, lumpy, classify_ok) %>%
  head(5000) %>%
  write_csv(file.path(DIR_TABLES, "vmr_flow_classified.csv"))

tibble(n_flows        = nrow(flow_dln),
       max_abs_resid  = max(abs(flow_dln$id_resid)),
       mean_abs_resid = mean(abs(flow_dln$id_resid)),
       noqty_value_share = cov_noqty / cov_total,
       n_no_control   = sum(is.na(flow_dln$world_dln_uv)),
       n_lumpy        = sum(flow_class$lumpy),
       value_floor    = VALUE_FLOOR) %>%
  write_csv(file.path(DIR_TABLES, "vmr_identity_check.csv"))

write_run_meta("02c_vmr",
               notes = sprintf("qty_mode=%s; event_mode=%s; treated=%d",
                               QTY_MODE, EVENT_MODE, nrow(flow_dln)))
msg("[02c] done.")
