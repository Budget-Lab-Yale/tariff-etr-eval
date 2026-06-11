# =============================================================================
# 03b_figures_baseline.R — paper baseline figures
# =============================================================================
# ggplot port of the retired Stata 03b_baseline_figures.do, reading only
# results/tables/*.csv (figure-isolation pattern; data built in 02a).
#
#   figure_baseline       paper 4.1: monthly statutory (= S1 by construction)
#                         vs Treasury actual, with policy-event reference lines
#   figure_daily_overlay  paper 4.5: daily statutory ETR with monthly means
#
# The USMCA adjustment explainer (Stata 03b section D) requires the S0 /
# usmca_monthly scenario panels, which the shared tracker publish does not
# carry -- it returns with full (DataWeb) mode; see docs/open_questions.md.
# =============================================================================

here::i_am("code/03b_figures_baseline.R")
setwd(here::here())
source("code/utils.R")
suppressPackageStartupMessages({ library(ggplot2); library(scales) })

msg("[03b] Baseline figures...")
tbl <- function(f) read_csv(file.path(DIR_TABLES, f), show_col_types = FALSE)

events_in_window <- POLICY_EVENTS %>%
  filter(date >= ym_date(ANALYSIS_LO), date <= ym_date(ANALYSIS_HI))

# --- Paper 4.1 baseline: statutory vs Treasury -------------------------------
base <- tbl("baseline_etr.csv") %>% mutate(date = ym_date(year_month))
df <- base %>%
  select(date, Statutory = t1_h2avg, Actual = t4) %>%
  pivot_longer(-date) %>%
  filter(!is.na(value)) %>%
  mutate(name = factor(name, c("Statutory", "Actual"),
                       c("Statutory ETR (tracker, monthly mean)",
                         "Actual ETR (Treasury)")))
p <- ggplot(df, aes(date, value, colour = name)) +
  geom_vline(data = events_in_window, aes(xintercept = date),
             colour = "grey80", linetype = "dashed") +
  geom_text(data = events_in_window, aes(x = date, y = Inf, label = label),
            inherit.aes = FALSE, angle = 90, vjust = -0.4, hjust = 1.1,
            size = 2.6, colour = "grey40") +
  geom_line(linewidth = 1) + geom_point(size = 1.6) +
  scale_colour_manual(values = setNames(c(COL_STATUTORY, COL_ACTUAL),
                                        levels(df$name)), name = NULL) +
  scale_x_date(date_breaks = "2 months", date_labels = "%b %Y") +
  labs(x = NULL, y = "Effective tariff rate (%)") +
  theme_etr()
save_fig(p, "figure_baseline", "Statutory vs actual effective tariff rate",
         "Tracker statutory ETR (monthly mean of daily series; equals framework S1) vs Treasury collections")

# --- Paper 4.5 daily overlay --------------------------------------------------
daily <- tbl("daily_etr.csv") %>%
  mutate(date = as.Date(date), year_month = substr(date, 1, 7)) %>%
  group_by(year_month) %>%
  mutate(monthly_etr = mean(weighted_etr),
         mid = date == sort(date)[ceiling(dplyr::n() / 2)]) %>%
  ungroup()
p <- ggplot(daily, aes(date, weighted_etr)) +
  geom_vline(data = events_in_window, aes(xintercept = date),
             colour = "grey80", linetype = "dashed") +
  geom_step(colour = COL_STATUTORY, linewidth = 0.8) +
  geom_point(data = daily %>% filter(mid), aes(y = monthly_etr),
             colour = COL_ACTUAL, size = 2) +
  scale_x_date(date_breaks = "2 months", date_labels = "%b %Y") +
  labs(x = NULL, y = "Statutory ETR (%)") +
  theme_etr()
save_fig(p, "figure_daily_overlay", "Daily statutory ETR with monthly means",
         "Step line: tracker daily import-weighted statutory ETR; points: monthly means at mid-month")

msg("[03b] done. (USMCA adjustment explainer deferred: needs full-mode panels)")
