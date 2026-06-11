# =============================================================================
# 03a_figures_framework.R — framework + decomposition + VMR figures
# =============================================================================
# Reads ONLY results/tables/*.csv (never the panel or raw data), so figures
# can be restyled without re-running the pipeline — the figure-isolation
# pattern ported from tariff-etr-adj. Every figure exports as a titled +
# clean pair via save_fig (see utils.R).
#
# Figures (ggplot ports of the retired Stata 03_etr_analysis.do output):
#   figure_ladder                 tier lines (S0 when present, S1-S4, T)
#   figure_channel_stacked        monthly channel stack (S1 -> T)
#   figure_timing_decomp          gap_timing split: de-minimis / AD/CVD / resid
#   figure_diversion_decomp       Shapley between/within stack
#   figure_diversion_country/product   per-group contributions
#   figure_others_country/product      S2->S3 contributions
#   figure_residual_country/product    S3->S4 contributions
#   figure_attribution_country/product 4-channel facet grid
#   figure_s2s4_overall           S2 vs S4 vs T lines
#   figure_s2s4_heatmap           period-avg S2-S4 gap, product x partner
#   figure_vmr_suspect_share_by_partner / _heatmap / _dln_scatter
# =============================================================================

here::i_am("code/03a_figures_framework.R")
setwd(here::here())
source("code/utils.R")
suppressPackageStartupMessages({ library(ggplot2); library(scales) })

msg("[03a] Framework figures...")
tbl <- function(f) read_csv(file.path(DIR_TABLES, f), show_col_types = FALSE)

ladder  <- tbl("decomp_monthly.csv")  %>% mutate(date = ym_date(year_month))
HAVE_S0 <- "s0" %in% names(ladder)

pg_factor   <- function(x) factor(x, levels = PARTNER_LEVELS)
prod_factor <- function(x) factor(x, levels = PRODUCT_LEVELS)
month_axis  <- scale_x_date(date_breaks = "2 months", date_labels = "%b %Y")

# --- Ladder lines --------------------------------------------------------------
tier_levels <- c(if (HAVE_S0) "s0", "s1", "s2", "s3", "s4", "t")
tier_labels <- c(if (HAVE_S0) "S0: USMCA 2024 base x 2024 wts",
                 "S1: Statutory x 2024 wts", "S2: Statutory x monthly wts",
                 "S3: + non-USMCA preferences", "S4: Census collected",
                 "T: Treasury actual")
tier_cols <- setNames(
  c(if (HAVE_S0) "#CC79A7", "#0072B2", "#56B4E9", "#009E73", "#E69F00",
    "#D55E00"), tier_levels)
df <- ladder %>%
  pivot_longer(all_of(tier_levels), names_to = "tier", values_to = "etr") %>%
  mutate(tier = factor(tier, tier_levels, tier_labels))
p <- ggplot(df, aes(date, etr, colour = tier)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_colour_manual(values = setNames(unname(tier_cols), tier_labels),
                      name = NULL) +
  month_axis + labs(x = NULL, y = "Effective tariff rate (%)") +
  guides(colour = guide_legend(nrow = 2)) + theme_etr()
save_fig(p, "figure_ladder", "Counterfactual ETR ladder",
         "Statutory tiers vs Census-collected and Treasury-actual ETRs")

# --- Channel stack (S1 -> T) ------------------------------------------------------
chan_levels <- c("gap_diversion", "gap_others", "gap_residual", "gap_timing")
chan_labels <- c("Import composition (S1-S2)", "Non-USMCA preferences (S2-S3)",
                 "Residual (S3-S4)", "Timing/enforcement (S4-T)")
chan_cols <- c("#0072B2", "#009E73", "#E69F00", "#999999")
df <- ladder %>%
  pivot_longer(all_of(chan_levels), names_to = "ch", values_to = "pp") %>%
  mutate(ch = factor(ch, chan_levels, chan_labels))
p <- ggplot(df, aes(date, pp, fill = ch)) +
  geom_col() +
  geom_hline(yintercept = 0, colour = "grey60") +
  scale_fill_manual(values = setNames(chan_cols, chan_labels), name = NULL) +
  month_axis + labs(x = NULL, y = "Contribution to S1 - T gap (pp)") +
  guides(fill = guide_legend(nrow = 2)) + theme_etr()
save_fig(p, "figure_channel_stacked", "Statutory-to-actual gap by channel",
         "Monthly channel stack; channels sum to S1 - T")

# --- Timing decomposition (new: strips) -------------------------------------------
tm_levels <- c("gap_timing_deminimis", "gap_timing_adcvd", "gap_timing_residual")
tm_labels <- c("De-minimis postal channel", "AD/CVD deposits",
               "Residual timing/enforcement")
df <- ladder %>%
  pivot_longer(all_of(tm_levels), names_to = "ch", values_to = "pp") %>%
  mutate(ch = factor(ch, tm_levels, tm_labels))
p <- ggplot(df, aes(date, pp, fill = ch)) +
  geom_col() +
  geom_line(data = ladder, aes(date, gap_timing), inherit.aes = FALSE,
            colour = "black", linewidth = 0.7) +
  geom_hline(yintercept = 0, colour = "grey60") +
  scale_fill_manual(values = setNames(c("#CC79A7", "#E69F00", "#999999"),
                                      tm_labels), name = NULL) +
  month_axis + labs(x = NULL, y = "S4 - T (pp)") + theme_etr()
save_fig(p, "figure_timing_decomp", "Timing/enforcement gap decomposition",
         "Black line = S4 - T; bars split it into collection channels invisible to Census (strips ported from tariff-etr-adj)")

# --- Diversion: Shapley stack + per-group bars --------------------------------------
div_c <- tbl("diversion_by_country.csv") %>% mutate(date = ym_date(year_month))
div_p <- tbl("diversion_by_product.csv") %>% mutate(date = ym_date(year_month))

df <- div_c %>% group_by(date) %>%
  summarise(Between = sum(between), Within = sum(within), .groups = "drop") %>%
  pivot_longer(-date)
p <- ggplot(df, aes(date, value, fill = name)) +
  geom_col() + geom_hline(yintercept = 0, colour = "grey60") +
  scale_fill_manual(values = c(Between = "#0072B2", Within = "#009E73"),
                    labels = c("Between-country (share shifts)",
                               "Within-country (product mix)"), name = NULL) +
  month_axis + labs(x = NULL, y = "Contribution to import-composition gap (pp)") +
  theme_etr()
save_fig(p, "figure_diversion_decomp",
         "Import composition decomposition: country lens",
         "Shapley two-way; segments sum to the S1-S2 gap")

stacked_group <- function(df, group, cols, ylab) {
  ggplot(df, aes(date, val, fill = .data[[group]])) +
    geom_col() + geom_hline(yintercept = 0, colour = "grey60") +
    scale_fill_manual(values = cols, name = NULL) +
    month_axis + labs(x = NULL, y = ylab) +
    guides(fill = guide_legend(nrow = ifelse(length(cols) > 8, 2, 1))) +
    theme_etr()
}
save_fig(stacked_group(div_c %>% mutate(val = total,
                                        partner_group = pg_factor(partner_group)),
                       "partner_group", PARTNER_COLS,
                       "Contribution to import-composition gap (pp)"),
         "figure_diversion_country", "Import composition: country contributions",
         "Stacked monthly, signed")
save_fig(stacked_group(div_p %>% mutate(val = total,
                                        product_group = prod_factor(product_group)),
                       "product_group", PRODUCT_COLS,
                       "Contribution to import-composition gap (pp)"),
         "figure_diversion_product", "Import composition: product contributions",
         "Stacked monthly, signed")

# --- Others / residual contributions -------------------------------------------------
attr_c <- tbl("attribution_by_country.csv") %>%
  mutate(date = ym_date(year_month), partner_group = pg_factor(partner_group))
attr_p <- tbl("attribution_by_product.csv") %>%
  mutate(date = ym_date(year_month), product_group = prod_factor(product_group))

save_fig(stacked_group(attr_c %>% mutate(val = others_pp), "partner_group",
                       PARTNER_COLS, "Contribution to non-USMCA-preferences gap (pp)"),
         "figure_others_country", "All-other preferences: country contributions",
         "Stacked monthly, signed; sums to the S2-S3 gap")
save_fig(stacked_group(attr_p %>% mutate(val = others_pp), "product_group",
                       PRODUCT_COLS, "Contribution to non-USMCA-preferences gap (pp)"),
         "figure_others_product", "All-other preferences: product contributions",
         "Stacked monthly, signed; sums to the S2-S3 gap")
save_fig(stacked_group(attr_c %>% mutate(val = residual_pp), "partner_group",
                       PARTNER_COLS, "Contribution to residual gap (pp)"),
         "figure_residual_country", "Residual: country contributions",
         "Stacked monthly, signed; sums to the S3-S4 gap")
save_fig(stacked_group(attr_p %>% mutate(val = residual_pp), "product_group",
                       PRODUCT_COLS, "Contribution to residual gap (pp)"),
         "figure_residual_product", "Residual: product contributions",
         "Stacked monthly, signed; sums to the S3-S4 gap")

# --- 4-channel attribution facets -----------------------------------------------------
facet_attr <- function(df, group, cols, stub, title) {
  chans <- c(adjustment_pp = "USMCA adjustment", diversion_pp = "Import composition",
             others_pp = "Non-USMCA preferences", residual_pp = "Residual")
  d <- df %>%
    pivot_longer(all_of(names(chans)), names_to = "ch", values_to = "pp") %>%
    mutate(ch = factor(chans[ch], unname(chans))) %>%
    filter(!is.na(pp))
  p <- ggplot(d, aes(date, pp, fill = .data[[group]])) +
    geom_col() + geom_hline(yintercept = 0, colour = "grey60") +
    facet_wrap(~ch, ncol = 2) +
    scale_fill_manual(values = cols, name = NULL) +
    month_axis + labs(x = NULL, y = "pp") +
    guides(fill = guide_legend(nrow = 2)) +
    theme_etr(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  save_fig(p, stub, title,
           "Stacked monthly; the timing channel (S4-T) is aggregate-only and not shown",
           width = 12, height = 8)
}
facet_attr(attr_c, "partner_group", PARTNER_COLS, "figure_attribution_country",
           "Per-country attribution across the four decomposable channels")
facet_attr(attr_p, "product_group", PRODUCT_COLS, "figure_attribution_product",
           "Per-product attribution across the four decomposable channels")

# --- S2 vs S4 vs T -----------------------------------------------------------------
cmp <- tbl("cmp_overall_monthly.csv") %>% mutate(date = ym_date(year_month))
df <- cmp %>% pivot_longer(c(s2, s4, t)) %>%
  mutate(name = factor(name, c("s2", "s4", "t"),
                       c("S2: Statutory (monthly wts)", "S4: Census collected",
                         "T: Treasury actual")))
p <- ggplot(df, aes(date, value, colour = name)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_colour_manual(values = setNames(c(COL_STATUTORY, COL_GAP, COL_ACTUAL),
                                        levels(df$name)), name = NULL) +
  month_axis + labs(x = NULL, y = "Effective tariff rate (%)") + theme_etr()
save_fig(p, "figure_s2s4_overall", "Statutory vs collected vs actual",
         "S2 (statutory at monthly weights), S4 (Census collected), T (Treasury)")

# heatmap: period-avg S2-S4 gap on the product x partner grid (geom_tile
# replaces the Stata heatplot dependency)
hm <- tbl("cmp_product_partner_avg.csv") %>%
  mutate(partner_group = pg_factor(partner_group),
         product_group = prod_factor(product_group))
p <- ggplot(hm, aes(product_group, partner_group, fill = gap_pp)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.1f", gap_pp)), size = 2.8) +
  scale_fill_gradient2(low = "#0072B2", mid = "#f7f7f7", high = "#D55E00",
                       midpoint = 0, name = "S2-S4 (pp)") +
  labs(x = NULL, y = NULL) +
  theme_etr(base_size = 11) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1),
        legend.position = "right")
save_fig(p, "figure_s2s4_heatmap", "Statutory-collected gap, product x partner",
         "Period-average S2-S4 gap (pp)", height = 6.5)

# --- VMR figures (from 02c tables) ---------------------------------------------------
vmr_p  <- tbl("vmr_decomp_by_partner.csv")
vmr_pp <- tbl("vmr_decomp_by_partner_product.csv")
vmr_fl <- tbl("vmr_flow_classified.csv")

df <- vmr_p %>%
  select(partner_group, loose = share_suspect_value,
         strict = share_suspect_strict_value) %>%
  pivot_longer(c(loose, strict), names_to = "signal", values_to = "share") %>%
  mutate(partner_group = factor(partner_group,
           levels = vmr_p$partner_group[order(vmr_p$share_suspect_strict_value)]))
p <- ggplot(df, aes(share, partner_group, fill = signal)) +
  geom_col(position = "dodge") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c(loose = "#999999", strict = "#D55E00"),
                    labels = c(loose = "value down, qty flat",
                               strict = "+ unit value < control"), name = NULL) +
  labs(x = "Value-weighted share of flows", y = NULL) + theme_etr() +
  theme(legend.position = "top")
save_fig(p, "figure_vmr_suspect_share_by_partner",
         "Misreporting-suspect import-value share, by partner",
         "Value down with quantity flat after a tariff step; strict also requires unit value below untariffed peers")

p <- ggplot(vmr_pp %>% mutate(partner_group = pg_factor(partner_group),
                              product_group = prod_factor(product_group)),
            aes(product_group, partner_group, fill = share_suspect_strict_value)) +
  geom_tile(colour = "white") +
  scale_fill_gradient(low = "#f7f7f7", high = "#D55E00",
                      labels = percent_format(accuracy = 1),
                      name = "strict\nshare") +
  labs(x = NULL, y = NULL) + theme_etr(base_size = 11) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1),
        legend.position = "right")
save_fig(p, "figure_vmr_suspect_share_heatmap",
         "Misreporting-suspect value share (strict), partner x product",
         "Strict = value down, quantity flat, and unit value below untariffed peers",
         height = 6.5)

df <- vmr_fl %>% filter(classify_ok) %>% slice_max(V_post, n = 4000)
p <- ggplot(df, aes(dln_qty, dln_value)) +
  annotate("rect", xmin = -0.10, xmax = 0.10, ymin = -Inf, ymax = -0.10,
           fill = "#D55E00", alpha = 0.10) +
  geom_hline(yintercept = 0, colour = "grey70") +
  geom_vline(xintercept = 0, colour = "grey70") +
  geom_point(aes(size = V_post, colour = pg_factor(partner_group)), alpha = 0.5) +
  scale_colour_manual(values = PARTNER_COLS, name = NULL) +
  scale_size_area(max_size = 6, guide = "none") +
  coord_cartesian(xlim = c(-3, 3), ylim = c(-3, 3)) +
  labs(x = expression(Delta * "ln quantity"), y = expression(Delta * "ln value")) +
  theme_etr() + theme(legend.position = "top")
save_fig(p, "figure_vmr_dln_scatter", "Value vs quantity change after a tariff step",
         "Shaded band: value down with quantity flat (misreporting-suspect). Point size = post-window value")

msg("[03a] done.")
