# =============================================================================
# 09_value_misreporting.R
# Decompose post-tariff import-value changes into REAL flow changes vs VALUE
# MISREPORTING (under-invoicing), using Census import quantity / shipping weight.
#
# Logic. Within a flow (HS10 x country), the accounting identity
#     dln(value) = dln(quantity) + dln(unit_value),  unit_value = value/quantity.
# A real value decline should be matched by a quantity decline. If value falls
# but quantity holds (|dln_qty| ~ 0), the implied unit value collapsed -- a
# misreporting / under-invoicing signal (bucket B2). To net out genuine
# world-price declines we compare each tariffed flow's unit-value change to the
# value-weighted change of UNtariffed origins of the SAME HS10 over the same
# months (cross-partner, within-product control; Fisman-Wei in spirit).
#
# Orthogonality to eta. The compliance gap is a revenue ratio
# 1 - eta = duty/(rate*value). Under-invoicing scales value down, duty = rate*
# value falls proportionally, so duty/value (hence eta) is UNCHANGED -- eta is
# blind to value under-invoicing. This script measures the base-erosion channel
# eta omits, on the same partner x product grid (sidecar to eta_by_*.csv).
#
# Usage:  Rscript code/R/09_value_misreporting.R
# Inputs: data/raw/imdb_hs10_country_monthly.csv  (augmented: con_qy1_mo,
#           con_qy2_mo, air/ves/cnt_wgt_mo, ship_wgt_mo -- needs one prior
#           run of 00_pull_raw_data.R --only-imdb to populate them)
#         data/working/merged_analysis.dta        (rate_h2avg path only)
#         resources/product_groups.csv            (HS2 -> 9 product groups)
# Output: results/tables/vmr_*.csv, results/figures/figure_vmr_*.png
#
# Limitations (see also plan): the cross-partner control removes product-wide
# price/mix drift, not origin-specific genuine quality downgrading; HS10 with no
# clean control origin (e.g. China-dominant lines) are out of scope for the
# control; shipping weight is zero for land modes (CA/MX) so the weight
# robustness anchor excludes them; no-quantity ("X") HTS are unmeasurable;
# declared data only -- this flags patterns consistent with understatement, not
# adjudicated fraud.
# =============================================================================

suppressPackageStartupMessages({
  library(haven); library(dplyr); library(tidyr); library(readr)
  library(ggplot2); library(scales)
})
options(dplyr.summarise.inform = FALSE)

TAB <- "results/tables"
FIG <- "results/figures"
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

msg <- function(...) cat(sprintf(...), "\n")

# ---- Parameters (top-of-file knobs; robustness = sweep these) --------------
WIN_LO        <- 780L   # 2025m1 (ym = (year-1960)*12 + (month-1))
WIN_HI        <- 794L   # 2026m3
LOAD_LO       <- 768L   # 2024m1: load value/qty back to here so pre-windows and
                        #          the fixed-baseline robustness can reach 2024
T_V           <- 0.10   # |dln value| dead-band
T_Q           <- 0.10   # |dln quantity| dead-band ("quantity does not change")
T_W           <- 0.10   # excess (relative-to-control) unit-value band, strict signal
DRATE_THRESH  <- 0.03   # >=3pp statutory step = a flow "tariff change" event
CTRL_DRATE_MAX<- 0.01   # control origins: |window rate change| <= 1pp
MIN_CTRL      <- 2L     # >=2 clean control origins for the cross-partner control
VALUE_FLOOR   <- 1e5    # $100k mean monthly pre-window value to enter classification
PRE_OFFSETS   <- -3:-1  # pre-window months relative to event t*
POST_OFFSETS  <-  2:4   # post-window months (skip t* and t*+1: in-transit/front-run)
EVENT_MODE    <- "flow" # "flow" = per-flow largest in-window step (primary);
                        # "fixed" = single calendar anchor FIXED_EVENT_YM for all
FIXED_EVENT_YM<- 783L   # 2025m4 (Liberation Day) -- used only if EVENT_MODE="fixed"
QTY_MODE      <- "qy1"  # "qy1" = con_qy1_mo + ship-weight fallback (primary);
                        # "weight" = air+ves only, CA/MX excluded (robustness)
DRY_RUN       <- FALSE  # TRUE -> 2025m3-m5 window, China only (fast smoke test)

# Wong colorblind-safe palette, matching code/utils/globals.do $color_<partner>
PARTNER_COLS <- c("China"="#D55E00", "Canada"="#0072B2", "Mexico"="#009E73",
                  "EU"="#F0E442", "Japan"="#CC79A7", "S. Korea"="#E69F00",
                  "UK"="#56B4E9", "ROW"="#999999")

# Port of assign_partner_group (code/utils/programs.do) + EU27 codes (globals.do)
EU_CODES <- c("4280","4220","4230","4240","4253","4254","4270","4350","4360",
              "4380","4390","4550","4560","4570","4590","4610","4690","4700",
              "4720","4740","4810","4760","4770","4780","4840","4850","4870")
assign_partner_group <- function(cty) {
  pg <- rep("ROW", length(cty))
  pg[cty == "5700"] <- "China";  pg[cty == "1220"] <- "Canada"
  pg[cty == "2010"] <- "Mexico"; pg[cty == "5880"] <- "Japan"
  pg[cty == "5800"] <- "S. Korea"; pg[cty == "4120"] <- "UK"
  pg[cty %in% EU_CODES] <- "EU"
  pg
}

# Save a figure in both titled and clean (no title/subtitle) variants (~2400px),
# mirroring the repo's export_fig titled/clean convention.
save_fig <- function(p, stub, title, subtitle = NULL, width = 10, height = 6) {
  ggsave(file.path(FIG, paste0(stub, "_titled.png")),
         p + labs(title = title, subtitle = subtitle),
         width = width, height = height, dpi = 240)
  ggsave(file.path(FIG, paste0(stub, ".png")),
         p + labs(title = NULL, subtitle = NULL),
         width = width, height = height, dpi = 240)
}

# ---------------------------------------------------------------------------
# 1. Load: value/quantity (augmented IMDB CSV) + statutory rate path (dta)
# ---------------------------------------------------------------------------
msg("[1] Loading augmented IMDB aggregate + rate path...")
imdb_csv <- "data/raw/imdb_hs10_country_monthly.csv"
agg <- read_csv(imdb_csv,
                col_types = cols(hs10 = col_character(), cty_code = col_character(),
                                 year_month = col_character(), .default = col_double()))
need <- c("con_qy1_mo", "ship_wgt_mo")
miss <- setdiff(need, names(agg))
if (length(miss) > 0)
  stop("Augmented columns missing from ", imdb_csv, ": ", paste(miss, collapse = ", "),
       "\n  Run: Rscript code/R/00_pull_raw_data.R --only-imdb", call. = FALSE)

agg <- agg %>%
  mutate(year  = as.integer(substr(year_month, 1, 4)),
         month = as.integer(substr(year_month, 6, 7)),
         ym    = (year - 1960L) * 12L + (month - 1L)) %>%
  filter(ym >= LOAD_LO, ym <= WIN_HI, con_val_mo > 0)

# Statutory rate path (day-weighted monthly total_rate); 2024 has no tariffs -> 0
rates <- read_dta("data/working/merged_analysis.dta",
                  col_select = c("hs10", "cty_code", "ym", "rate_h2avg")) %>%
  mutate(ym = as.integer(ym), hs10 = as.character(hs10),
         cty_code = as.character(cty_code)) %>%
  filter(ym >= LOAD_LO, ym <= WIN_HI) %>%
  group_by(hs10, cty_code, ym) %>%
  summarise(rate_h2avg = dplyr::first(rate_h2avg), .groups = "drop")

product_groups <- read_csv("resources/product_groups.csv",
                           col_types = cols(hs2 = col_character(),
                                            product_group = col_character()))

flows <- agg %>%
  left_join(rates, by = c("hs10", "cty_code", "ym")) %>%
  mutate(rate_h2avg    = coalesce(rate_h2avg, 0),
         hs2           = substr(hs10, 1, 2),
         partner_group = assign_partner_group(cty_code)) %>%
  left_join(product_groups, by = "hs2") %>%
  mutate(product_group = coalesce(product_group, "Other Manufactured"))

if (DRY_RUN) {
  flows <- flows %>% filter(partner_group == "China",
                            ym >= 782L, ym <= 784L)   # 2025m3..m5
  msg("    DRY_RUN: China only, 2025m3-m5 (%s rows)", format(nrow(flows), big.mark = ","))
}
msg("    flows: %s cell-months (%d..%d)", format(nrow(flows), big.mark = ","),
    min(flows$ym), max(flows$ym))

# ---------------------------------------------------------------------------
# 2. Unit value: pick the physical anchor, flag unmeasurable flows
# ---------------------------------------------------------------------------
msg("[2] Unit value (anchor = %s)...", QTY_MODE)
flows <- flows %>%
  mutate(
    qty = if (QTY_MODE == "weight") {
      # air+vessel weight only; land modes report zero -> CA/MX excluded below
      if_else(ship_wgt_mo > 0, ship_wgt_mo, NA_real_)
    } else {
      # primary: con_qy1_mo, fall back to shipping weight where qy1 is 0/missing
      dplyr::case_when(con_qy1_mo > 0 ~ con_qy1_mo,
                       ship_wgt_mo > 0 ~ ship_wgt_mo,
                       TRUE ~ NA_real_)
    },
    qty_source = dplyr::case_when(
      QTY_MODE == "weight" & ship_wgt_mo > 0 ~ "ship_wgt",
      QTY_MODE != "weight" & con_qy1_mo > 0  ~ "qy1",
      QTY_MODE != "weight" & ship_wgt_mo > 0 ~ "ship_wgt",
      TRUE ~ NA_character_),
    unit_value = if_else(!is.na(qty) & qty > 0, con_val_mo / qty, NA_real_))

if (QTY_MODE == "weight")
  flows <- flows %>% filter(!(partner_group %in% c("Canada", "Mexico")))

# Coverage: value share with no usable physical anchor (e.g. "X" no-qty HTS)
cov_total  <- sum(flows$con_val_mo)
cov_noqty  <- sum(flows$con_val_mo[is.na(flows$qty)])
msg("    no-quantity value share (unmeasurable anchor): %.1f%%",
    100 * cov_noqty / cov_total)

# Monthly flow table with a usable unit value (basis for window aggregation)
mf <- flows %>%
  filter(!is.na(qty), qty > 0, con_val_mo > 0) %>%
  select(hs10, cty_code, partner_group, product_group, hs2, ym,
         value = con_val_mo, qty, rate_h2avg)

# ---------------------------------------------------------------------------
# 3. Tariff-change event per flow
# ---------------------------------------------------------------------------
msg("[3] Defining tariff-change events (mode = %s)...", EVENT_MODE)
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
  slice_max(drate, n = 1, with_ties = FALSE) %>%   # largest step is the headline
  ungroup() %>%
  transmute(hs10, cty_code, event_ym = ym, event_drate = drate)

if (EVENT_MODE == "fixed")
  events <- events %>% mutate(event_ym = FIXED_EVENT_YM)

msg("    %s flows with a >=%.0fpp tariff step", format(nrow(events), big.mark = ","),
    100 * DRATE_THRESH)
if (nrow(events) == 0) stop("No flows with a tariff step in the window.", call. = FALSE)

# ---------------------------------------------------------------------------
# 4. + 6. Per-event window aggregation, dln decomposition, cross-partner control
# ---------------------------------------------------------------------------
# Done per distinct event month E so each treated flow's pre/post windows and
# its control origins (same HS10, same calendar months) are computed together.
msg("[4/6] Window decomposition + cross-partner control...")

window_agg_for_E <- function(E) {
  pre  <- E + PRE_OFFSETS
  post <- E + POST_OFFSETS
  w <- mf %>%
    filter(ym %in% c(pre, post)) %>%
    mutate(win = if_else(ym %in% pre, "pre", "post")) %>%
    group_by(hs10, cty_code, partner_group, product_group, hs2, win) %>%
    summarise(V = mean(value), Q = mean(qty), rate = mean(rate_h2avg),
              n_mo = dplyr::n(), .groups = "drop") %>%
    pivot_wider(names_from = win, values_from = c(V, Q, rate, n_mo))
  # backfill any window column a missing side (pre/post) didn't create, so the
  # mutate below is safe even when an event's post window is beyond the data
  for (col in c("V_pre","V_post","Q_pre","Q_post","rate_pre","rate_post"))
    if (!col %in% names(w)) w[[col]] <- NA_real_
  w %>%
    filter(!is.na(V_pre), !is.na(V_post), V_pre > 0, V_post > 0,
           Q_pre > 0, Q_post > 0) %>%
    mutate(uv_pre  = V_pre / Q_pre, uv_post = V_post / Q_post,
           dln_value = log(V_post) - log(V_pre),
           dln_qty   = log(Q_post) - log(Q_pre),
           dln_uv    = log(uv_post) - log(uv_pre),
           drate_win = coalesce(rate_post, 0) - coalesce(rate_pre, 0),
           event_ym  = E)
}

event_months <- sort(unique(events$event_ym))
per_E <- lapply(event_months, function(E) {
  w <- window_agg_for_E(E)
  if (nrow(w) == 0) return(NULL)
  # Control origins for each HS10: ~untariffed change over the same window
  ctrl <- w %>%
    filter(abs(drate_win) <= CTRL_DRATE_MAX) %>%
    group_by(hs10) %>%
    summarise(world_uv_pre  = sum(V_pre)  / sum(Q_pre),
              world_uv_post = sum(V_post) / sum(Q_post),
              n_ctrl = dplyr::n(), .groups = "drop") %>%
    mutate(world_dln_uv = log(world_uv_post) - log(world_uv_pre)) %>%
    select(hs10, world_dln_uv, n_ctrl)
  treated <- events %>% filter(event_ym == E) %>% select(hs10, cty_code, event_drate)
  w %>%
    inner_join(treated, by = c("hs10", "cty_code")) %>%
    left_join(ctrl, by = "hs10")
})
flow_dln <- bind_rows(per_E) %>%
  mutate(id_resid     = dln_value - dln_qty - dln_uv,           # ~0 by construction
         dln_uv_excess = dln_uv - world_dln_uv)                 # NA if no control

msg("    decomposed %s treated flows; max |identity residual| = %.2e",
    format(nrow(flow_dln), big.mark = ","), max(abs(flow_dln$id_resid)))

# ---------------------------------------------------------------------------
# 5. Bucket classification (dead-band T_V / T_Q) + strict (control) signal
# ---------------------------------------------------------------------------
msg("[5] Classifying flows...")
flow_class <- flow_dln %>%
  mutate(
    bucket = dplyr::case_when(
      dln_value < -T_V & dln_qty < -T_Q          ~ "B1_real_contraction",
      dln_value < -T_V & abs(dln_qty) <= T_Q     ~ "B2_misreport_suspect",
      abs(dln_value) <= T_V & dln_qty < -T_Q     ~ "B3_quantity_driven",
      dln_value >  T_V & dln_qty >  T_Q          ~ "B4_real_expansion",
      dln_value >  T_V & abs(dln_qty) <= T_Q     ~ "B5_unit_value_spike",
      TRUE                                        ~ "B6_mixed"),
    suspect       = bucket == "B2_misreport_suspect",
    # strict: value down, quantity flat, AND unit value fell RELATIVE to
    # untariffed origins of the same product (nets out common world price)
    suspect_strict = suspect & !is.na(dln_uv_excess) &
                     n_ctrl >= MIN_CTRL & dln_uv_excess < -T_W,
    lumpy      = V_pre < VALUE_FLOOR,            # below floor -> noisy, not classified
    classify_ok = !lumpy)

bt <- flow_class %>% filter(classify_ok) %>% count(bucket) %>%
  mutate(share = n / sum(n))
msg("    bucket counts (classified flows):")
for (i in seq_len(nrow(bt)))
  msg("      %-22s n=%6s  (%.1f%%)", bt$bucket[i],
      format(bt$n[i], big.mark = ","), 100 * bt$share[i])

# ---------------------------------------------------------------------------
# 7. Aggregate to partner x product (value-weighted by post-window value)
# ---------------------------------------------------------------------------
msg("[7] Aggregating...")
agg_one <- function(df, gvars) {
  df %>%
    filter(classify_ok) %>%
    group_by(across(all_of(gvars))) %>%
    summarise(
      n_flows           = dplyr::n(),
      n_suspect         = sum(suspect),
      n_suspect_strict  = sum(suspect_strict, na.rm = TRUE),
      val_total         = sum(V_post),
      val_suspect       = sum(V_post[suspect]),
      val_suspect_strict= sum(V_post[suspect_strict %in% TRUE]),
      share_suspect_value        = val_suspect / val_total,
      share_suspect_strict_value = val_suspect_strict / val_total,
      mean_dln_value    = weighted.mean(dln_value, V_post),
      mean_dln_qty      = weighted.mean(dln_qty,   V_post),
      mean_dln_uv       = weighted.mean(dln_uv,    V_post),
      mean_world_dln_uv = weighted.mean(world_dln_uv, V_post, na.rm = TRUE),
      .groups = "drop")
}

agg_pp      <- agg_one(flow_class, c("partner_group", "product_group"))
agg_partner <- agg_one(flow_class, "partner_group")
agg_product <- agg_one(flow_class, "product_group")
# China HS2 breakout
agg_china_hs2 <- flow_class %>%
  filter(partner_group == "China") %>%
  agg_one("hs2") %>% arrange(desc(val_total))

# ---------------------------------------------------------------------------
# 8. Write tables
# ---------------------------------------------------------------------------
msg("[8] Writing tables + figures...")
write_csv(agg_pp,      file.path(TAB, "vmr_decomp_by_partner_product.csv"))
write_csv(agg_partner, file.path(TAB, "vmr_decomp_by_partner.csv"))
write_csv(agg_product, file.path(TAB, "vmr_decomp_by_product.csv"))
write_csv(agg_china_hs2, file.path(TAB, "vmr_decomp_china_by_hs2.csv"))

# Flow-level detail: top flows by post value (audit / spot-check)
flow_out <- flow_class %>%
  arrange(desc(V_post)) %>%
  transmute(hs10, cty_code, partner_group, product_group, hs2, event_ym,
            event_drate, V_pre, V_post, Q_pre, Q_post, uv_pre, uv_post,
            dln_value, dln_qty, dln_uv, world_dln_uv, dln_uv_excess, n_ctrl,
            bucket, suspect, suspect_strict, lumpy)
write_csv(head(flow_out, 5000), file.path(TAB, "vmr_flow_classified.csv"))

# Identity check + coverage
identity_check <- tibble(
  n_flows           = nrow(flow_dln),
  max_abs_resid     = max(abs(flow_dln$id_resid)),
  mean_abs_resid    = mean(abs(flow_dln$id_resid)),
  noqty_value_share = cov_noqty / cov_total,
  n_no_control      = sum(is.na(flow_dln$world_dln_uv)),
  n_lumpy           = sum(flow_class$lumpy),
  value_floor       = VALUE_FLOOR)
write_csv(identity_check, file.path(TAB, "vmr_identity_check.csv"))

# ---------------------------------------------------------------------------
# 9. Figures (titled + clean pairs, Wong palette)
# ---------------------------------------------------------------------------
# (a) Suspect value share by partner (loose vs strict)
df_a <- agg_partner %>%
  select(partner_group, loose = share_suspect_value,
         strict = share_suspect_strict_value) %>%
  pivot_longer(c(loose, strict), names_to = "signal", values_to = "share") %>%
  mutate(partner_group = factor(partner_group,
                                levels = agg_partner$partner_group[order(agg_partner$share_suspect_strict_value)]))
p_a <- ggplot(df_a, aes(share, partner_group, fill = signal)) +
  geom_col(position = "dodge") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c(loose = "#999999", strict = "#D55E00"),
                    labels = c(loose = "value down, qty flat",
                               strict = "+ unit value < control")) +
  labs(x = "Value-weighted share of flows", y = NULL, fill = NULL) +
  theme_minimal(base_size = 12) + theme(legend.position = "top")
save_fig(p_a, "figure_vmr_suspect_share_by_partner",
         "Misreporting-suspect import-value share, by partner",
         "Value down with quantity flat after a tariff step; strict also requires unit value below untariffed peers")

# (b) Heatmap partner x product (strict share)
p_b <- ggplot(agg_pp, aes(product_group, partner_group,
                          fill = share_suspect_strict_value)) +
  geom_tile(colour = "white") +
  scale_fill_gradient(low = "#f7f7f7", high = "#D55E00",
                      labels = percent_format(accuracy = 1), name = "strict\nshare") +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))
save_fig(p_b, "figure_vmr_suspect_share_heatmap",
         "Misreporting-suspect value share (strict), partner x product",
         "Strict = value down, quantity flat, and unit value below untariffed peers", height = 6.5)

# (c) dln_qty vs dln_value scatter, B2 quadrant shaded, size = post value
df_c <- flow_class %>% filter(classify_ok) %>%
  slice_max(V_post, n = 4000)
p_c <- ggplot(df_c, aes(dln_qty, dln_value)) +
  annotate("rect", xmin = -T_Q, xmax = T_Q, ymin = -Inf, ymax = -T_V,
           fill = "#D55E00", alpha = 0.10) +
  geom_hline(yintercept = 0, colour = "grey70") +
  geom_vline(xintercept = 0, colour = "grey70") +
  geom_point(aes(size = V_post, colour = partner_group), alpha = 0.5) +
  scale_colour_manual(values = PARTNER_COLS, name = NULL) +
  scale_size_area(max_size = 6, guide = "none") +
  coord_cartesian(xlim = c(-3, 3), ylim = c(-3, 3)) +
  labs(x = expression(Delta * "ln quantity"), y = expression(Delta * "ln value")) +
  theme_minimal(base_size = 12) + theme(legend.position = "top")
save_fig(p_c, "figure_vmr_dln_scatter",
         "Value vs quantity change after a tariff step",
         "Shaded band: value↓ with quantity flat (misreporting-suspect). Point size = post-window value")

msg("Done: 09_value_misreporting.R")
msg("  Tables -> %s/vmr_{decomp_by_partner_product,by_partner,by_product,china_by_hs2,flow_classified,identity_check}.csv", TAB)
msg("  Figures -> %s/figure_vmr_{suspect_share_by_partner,suspect_share_heatmap,dln_scatter}[_titled].png", FIG)
