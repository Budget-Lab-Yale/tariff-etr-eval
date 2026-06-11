# =============================================================================
# 08_eta_calibration.R
# Calibrate the State-of-Tariffs compliance parameter (eta) from the observed
# actual-vs-statutory ETR gap, and test it out-of-sample on the post-IEEPA
# (Section 122) regime.
#
# Design (see docs/eta_calibration_methodology.md):
#   eta_g defined by 1 - eta_g = (value-weighted actual ETR) / (statutory ETR)
#   within group g. Three specs: constant / two-way (country+product effects) /
#   full interaction (with empirical-Bayes shrinkage). Two statutory baselines:
#     S1 = announced (2024 fixed weights), S2 = composition-adjusted (monthly).
#   Cross-section identified from Census-declared duties; aggregate level pinned
#   to Treasury via a timing factor k. Train = IEEPA (2025m1-2026m2);
#   test = 2026m3 (post-SCOTUS / Section 122).
#
# Usage:  Rscript code/R/08_eta_calibration.R
# Inputs: data/working/merged_analysis.dta, data/working/revenue_monthly.dta
# Output: results/tables/eta_*.csv, results/figures/figure_eta_*.png
# =============================================================================

suppressPackageStartupMessages({
  library(haven); library(dplyr); library(tidyr); library(readr)
  library(ggplot2); library(scales); library(writexl)
})

options(dplyr.summarise.inform = FALSE)
TAB <- "results/tables"
FIG <- "results/figures"
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

TEST_YM    <- 794L       # 2026m3 in Stata monthly units (ym(2026,3))
WIN_LO     <- 780L       # 2025m1
WIN_HI     <- 794L       # 2026m3
POSTAPR_LO <- 784L       # 2025m5: first month after the volatile Jan-Apr ramp-up
KAPPA_FRAC <- 1.0        # EB shrinkage: kappa = KAPPA_FRAC * mean(statrev per cell)
RECENCY_HL <- 6          # recency-weighting half-life (months) for robustness
CURRENT_COMPLIANCE <- 0.10  # the flat assumption we are refining

msg <- function(...) cat(sprintf(...), "\n")

# ---------------------------------------------------------------------------
# 1. Load data
# ---------------------------------------------------------------------------
msg("[1] Loading panel (this reads ~550MB; ~1 min)...")
cells <- read_dta("data/working/merged_analysis.dta",
                  col_select = c("hs10", "cty_code", "partner_group",
                                 "hs2", "ym", "rate_h2avg", "census_etr",
                                 "cal_dut_mo", "con_val_mo", "imports"))

cells <- cells %>%
  mutate(ym = as.integer(ym),
         hs2 = as.character(hs2),
         cty_code = as.character(cty_code),
         partner_group = as.character(partner_group)) %>%
  filter(ym >= WIN_LO, ym <= WIN_HI,
         !is.na(con_val_mo), con_val_mo > 0) %>%
  mutate(rate_h2avg = coalesce(rate_h2avg, 0),
         cal_dut_mo = coalesce(cal_dut_mo, 0),
         imports    = coalesce(imports, 0),
         period = if_else(ym == TEST_YM, "test", "train"))
msg("    cells: %d (train=%d, test=%d)", nrow(cells),
    sum(cells$period == "train"), sum(cells$period == "test"))

rev <- read_dta("data/working/revenue_monthly.dta") %>%
  transmute(ym = as.integer(ym), customs_duties, imports_value,
            treas_etr = actual_rate) %>%
  filter(ym >= WIN_LO, ym <= WIN_HI) %>%
  distinct(ym, .keep_all = TRUE)

# --- AD/CVD strip: remove antidumping/countervailing duty from the COLLECTED
# side (both the Census shape cal_dut_mo and the Treasury level customs_duties,
# by the same dollars) so eta measures the compliance gap and not legally-owed
# AD/CVD. INERT until resources/adcvd_collected.csv exists; see
# code/R/adcvd_strip.R. Must run BEFORE treas_train_etr / treas_march_etr.
source("code/R/adcvd_strip.R")
adcvd <- load_adcvd_collected()
if (!is.null(adcvd)) {
  st <- apply_adcvd_strip(cells, rev, adcvd)
  cells <- st$panel; rev <- st$rev
}

treas_train_etr <- with(filter(rev, ym != TEST_YM),
                        sum(customs_duties) / sum(imports_value))
treas_march_etr <- rev$treas_etr[rev$ym == TEST_YM]
msg("    Treasury ETR: train(pooled)=%.4f  March=%.4f", treas_train_etr, treas_march_etr)

# ---------------------------------------------------------------------------
# 2. Helpers
# ---------------------------------------------------------------------------
# Statutory weight depends on baseline: S2 -> monthly value, S1 -> 2024 value.
wcol_for <- function(baseline) if (baseline == "S2") "con_val_mo" else "imports"

# Aggregate cells to a grouping; return statutory ETR, Census ETR, raw (1-eta),
# statutory revenue (the regression/shrinkage weight), and trade value.
group_agg <- function(df, gvars, baseline) {
  w <- wcol_for(baseline)
  df %>%
    group_by(across(all_of(gvars))) %>%
    summarise(
      statrev = sum(.data[[w]] * rate_h2avg),
      statwt  = sum(.data[[w]]),
      actduty = sum(cal_dut_mo),
      conval  = sum(con_val_mo),
      .groups = "drop") %>%
    mutate(setr = statrev / statwt,                 # statutory ETR
           aetr = actduty / conval,                 # Census actual ETR
           om_eta = if_else(setr > 0, aetr / setr, NA_real_))  # 1 - eta (raw)
}

# Two-way model: log(1-eta_cp) = a_c + b_p, weighted by statutory revenue.
# Returns a function mapping (c,p) -> predicted (1-eta), robust to unseen levels.
fit_twoway <- function(cp, c_name, p_name) {
  d <- cp %>% filter(is.finite(om_eta), om_eta > 0, statrev > 0)
  d$.c <- d[[c_name]]; d$.p <- d[[p_name]]
  fit <- lm(log(om_eta) ~ .c + .p, data = d, weights = statrev)
  co <- coef(fit)
  b0 <- co[["(Intercept)"]]
  a_c <- co[grepl("^\\.c", names(co))]; names(a_c) <- sub("^\\.c", "", names(a_c))
  b_p <- co[grepl("^\\.p", names(co))]; names(b_p) <- sub("^\\.p", "", names(b_p))
  function(cc, pp) {
    ac <- ifelse(cc %in% names(a_c), a_c[cc], 0); ac[is.na(ac)] <- 0
    bp <- ifelse(pp %in% names(b_p), b_p[pp], 0); bp[is.na(bp)] <- 0
    as.numeric(exp(b0 + ac + bp))
  }
}

# Build the per-cell Census shape (1-eta) lookup for a (spec, granularity) on a
# given sample. Returns the input df with column `om` populated for every cell,
# plus the share of raw cell-ratios that had to be clipped (full spec only).
assign_shape <- function(df, spec, baseline, c_name, p_name) {
  if (spec == "constant") {
    g  <- group_agg(df, character(0), baseline)
    df$om <- g$aetr / g$setr
    return(list(df = df, frac_clipped = NA_real_))
  }
  gv <- c(c_name, p_name)
  cp <- group_agg(df, gv, baseline)
  tw <- fit_twoway(cp, c_name, p_name)
  cp$tw <- tw(cp[[c_name]], cp[[p_name]])
  frac_clipped <- NA_real_
  if (spec == "twoway") {
    cp$om_use <- cp$tw
  } else {                                          # full interaction + EB shrink
    raw0 <- ifelse(is.finite(cp$om_eta), cp$om_eta, cp$tw)
    raw  <- pmin(pmax(raw0, 0), 2)                  # clip implausible cell ratios
    frac_clipped <- weighted.mean(raw0 != raw, w = pmax(cp$statrev, 0), na.rm = TRUE)
    kappa  <- KAPPA_FRAC * mean(cp$statrev[cp$statrev > 0])
    lambda <- cp$statrev / (cp$statrev + kappa)
    cp$om_use <- lambda * raw + (1 - lambda) * cp$tw
  }
  glob_om <- { g <- group_agg(df, character(0), baseline); g$aetr / g$setr }
  df <- df %>% left_join(select(cp, all_of(gv), om_use), by = gv)
  df$om <- df$om_use
  unseen <- is.na(df$om)                            # (c,p) not in this sample
  if (any(unseen)) df$om[unseen] <- tw(df[[c_name]][unseen], df[[p_name]][unseen])
  df$om[is.na(df$om)] <- glob_om                    # last-resort global fallback
  df$om_use <- NULL
  list(df = df, frac_clipped = frac_clipped)
}

# Weighted cross-sectional RMSE of the predicted Census rate (om * stat) vs the
# observed Census ETR, value-weighted. Measures how well the *shape* fits.
xsec_rmse <- function(df) {
  pr <- df$om * df$rate_h2avg
  sqrt(sum(df$con_val_mo * (pr - df$census_etr)^2) / sum(df$con_val_mo))
}

# Predicted ETR under shape `om` (and optional level k) on baseline weights.
pred_etr <- function(df, baseline, om = df$om) {
  w <- wcol_for(baseline)
  sum(df[[w]] * om * df$rate_h2avg) / sum(df[[w]])
}

# Pooled Treasury ETR over a training window (excludes the held-out test month).
treas_etr_window <- function(train_lo) {
  r <- filter(rev, ym >= train_lo, ym <= WIN_HI, ym != TEST_YM)
  sum(r$customs_duties) / sum(r$imports_value)
}

# Stricter OOS prediction that ALSO withholds the test-month import basket.
# Reweights the test cells with the most recent training month's basket (a naive
# carry-forward forecast: "next month's basket looks like this month's"), keeping
# the frozen training shape `om`, the known test-month statutory rates, and the
# training level k. Returns the predicted Treasury ETR plus the share of test-month
# trade value sitting in cells that also appear in the reference month (coverage).
# Note: for the announced (S1) baseline the weight column is the fixed 2024 value,
# so this nearly coincides with the standard prediction; it bites for S2 only.
pred_etr_fcst_basket <- function(te, tr, baseline, k) {
  w <- wcol_for(baseline)
  ref_ym <- max(tr$ym)                                # last training month (2026m2)
  ref <- cells %>% filter(ym == ref_ym) %>%
    group_by(hs10, cty_code) %>%
    summarise(w_ref = sum(.data[[w]]), .groups = "drop")
  d <- te %>% left_join(ref, by = c("hs10", "cty_code"))
  coverage <- sum(d[[w]][!is.na(d$w_ref)]) / sum(d[[w]])
  d <- filter(d, !is.na(w_ref), w_ref > 0)
  etr <- sum(d$w_ref * d$om * d$rate_h2avg) / sum(d$w_ref)
  list(pred = etr * k, coverage = coverage, ref_ym = ref_ym)
}

# ---------------------------------------------------------------------------
# 3. Calibrate one (window x baseline x spec x granularity) and score it OOS
# ---------------------------------------------------------------------------
# train_lo sets the first training month (WIN_LO = full, POSTAPR_LO = post-ramp);
# the test month is always March 2026 (TEST_YM), so a tighter window is a cleaner
# but smaller training sample for the same out-of-sample target.
calibrate <- function(baseline, spec, c_name = NULL, p_name = NULL,
                      gran_label = "", train_lo = WIN_LO, train_window = "full") {
  w  <- wcol_for(baseline)
  tr <- filter(cells, ym >= train_lo, ym != TEST_YM)
  te <- filter(cells, ym == TEST_YM)
  treas_tr <- treas_etr_window(train_lo)

  # --- shape (from Census), assigned to every train & test cell ---
  sh_tr <- assign_shape(tr, spec, baseline, c_name, p_name)
  tr <- sh_tr$df
  # test cells: use the TRAIN-estimated shape (frozen), with fallbacks.
  te <- assign_shape_to_test(te, tr, spec, baseline, c_name, p_name)

  # --- level: pin aggregate to Treasury via timing factor k (train) ---
  # k = ETR_treas / ETR_census(train shape) = Census->Treasury timing factor;
  # identical across specs (constant collapses to 1 - treas/stat by construction).
  P_train_tr <- pred_etr(tr, baseline)              # train-shape Census ETR on TRAIN
  k <- treas_tr / P_train_tr

  # --- out-of-sample prediction on March ---
  P_train_mar <- pred_etr(te, baseline)             # train shape applied to March
  march_pred_treas <- P_train_mar * k               # uses ACTUAL March basket
  march_err <- march_pred_treas - treas_march_etr

  # stricter OOS: also withhold the March basket (carry forward last training month)
  fb <- pred_etr_fcst_basket(te, tr, baseline, k)
  march_err_fcst <- fb$pred - treas_march_etr

  # --- aggregate eta (train) ---
  eta_agg <- 1 - (sum(tr[[w]] * tr$om * tr$rate_h2avg) /
                  sum(tr[[w]] * tr$rate_h2avg))

  # --- oracle: recalibrate the SAME spec on March alone (best achievable) ---
  sh_mar <- assign_shape(te, spec, baseline, c_name, p_name)
  te_or  <- sh_mar$df
  P_march_mar <- pred_etr(te_or, baseline)          # March shape on March (Census)
  k_march <- treas_march_etr / P_march_mar          # March Census->Treasury factor
  oracle_err <- P_march_mar * k_march - treas_march_etr   # ~0 by construction

  # --- shape vs level/timing decomposition of the March error (methodology s8) ---
  # err = (P_train_mar - P_march_mar)*k  +  P_march_mar*(k - k_march)
  #        \____ cross-section failed to transfer ___/   \__ timing wedge moved __/
  shape_comp <- (P_train_mar - P_march_mar) * k
  level_comp <- P_march_mar * (k - k_march)

  tibble(train_window = train_window, baseline = baseline, spec = spec,
         granularity = gran_label,
         eta_agg = eta_agg,                          # Census-shape aggregate gap (no k)
         eta_treas_agg = 1 - k * (1 - eta_agg),      # Treasury-calibrated aggregate gap (headline)
         k_train = k, k_march = k_march,
         train_xsec_rmse = xsec_rmse(tr),
         march_xsec_rmse = xsec_rmse(te),
         frac_clipped = sh_tr$frac_clipped,
         march_pred_treas_etr = march_pred_treas,
         march_actual_treas_etr = treas_march_etr,
         march_err_pp = 100 * march_err,
         shape_err_pp = 100 * shape_comp,
         level_err_pp = 100 * level_comp,
         oracle_err_pp = 100 * oracle_err,
         # stricter OOS: March basket also withheld (last training month carried forward)
         march_pred_fcst_etr = fb$pred,
         march_err_fcst_pp = 100 * march_err_fcst,
         fcst_basket_coverage = fb$coverage)
}

# Apply a TRAIN-estimated shape to the test cells (freeze the calibration).
# Re-fits the two-way map on train to predict unseen test (c,p) combinations.
assign_shape_to_test <- function(te, tr, spec, baseline, c_name, p_name) {
  if (spec == "constant") {
    te$om <- tr$om[1]
    return(te)
  }
  gv <- c(c_name, p_name)
  # train per-cell shape lookup (one row per (c,p)), plus the train two-way map.
  look <- tr %>% distinct(across(all_of(gv)), om)
  cp_tr <- group_agg(tr, gv, baseline)
  tw <- fit_twoway(cp_tr, c_name, p_name)
  glob_om <- { g <- group_agg(tr, character(0), baseline); g$aetr / g$setr }
  te <- te %>% left_join(look, by = gv)
  unseen <- is.na(te$om)
  if (any(unseen)) te$om[unseen] <- tw(te[[c_name]][unseen], te[[p_name]][unseen])
  te$om[is.na(te$om)] <- glob_om
  te
}

# ---------------------------------------------------------------------------
# 4. Driver: all (window x baseline x spec x granularity) combinations
# ---------------------------------------------------------------------------
msg("[2] Calibrating all specifications (x 2 training windows)...")
grid <- list(
  list(spec = "constant", c = NULL,            p = NULL, lab = "—"),
  list(spec = "twoway",   c = "partner_group", p = "hs2", lab = "partner_group x hts2"),
  list(spec = "twoway",   c = "cty_code",      p = "hs2", lab = "country x hts2"),
  list(spec = "full",     c = "partner_group", p = "hs2", lab = "partner_group x hts2"),
  list(spec = "full",     c = "cty_code",      p = "hs2", lab = "country x hts2")
)
windows <- list(list(lab = "full", lo = WIN_LO),
                list(lab = "post-Apr", lo = POSTAPR_LO))

summary_rows <- list()
for (win in windows) {
  for (bl in c("S1", "S2")) {
    for (g in grid) {
      msg("    [%-8s] %s / %-8s / %s", win$lab, bl, g$spec, g$lab)
      summary_rows[[length(summary_rows) + 1]] <-
        calibrate(bl, g$spec, g$c, g$p, g$lab,
                  train_lo = win$lo, train_window = win$lab)
    }
  }
}
eta_summary <- bind_rows(summary_rows) %>%
  mutate(baseline_label = if_else(baseline == "S2",
                                  "composition-adjusted", "announced (2024)"))
write_csv(eta_summary, file.path(TAB, "eta_summary.csv"))
msg("    -> %s (%d rows)", file.path(TAB, "eta_summary.csv"), nrow(eta_summary))

# ---------------------------------------------------------------------------
# 5. By-month constant eta + recency-weighted robustness
# ---------------------------------------------------------------------------
msg("[3] By-month diagnostics...")
month_eta <- function(baseline) {
  w <- wcol_for(baseline)
  cells %>%
    group_by(ym) %>%
    summarise(setr   = sum(.data[[w]] * rate_h2avg) / sum(.data[[w]]),
              cetr   = sum(cal_dut_mo) / sum(con_val_mo), .groups = "drop") %>%
    left_join(select(rev, ym, treas_etr), by = "ym") %>%
    transmute(ym, baseline,
              setr, census_etr = cetr, treas_etr,
              eta_census  = 1 - cetr / setr,         # statutory -> Census gap
              eta_treas   = 1 - treas_etr / setr)    # statutory -> Treasury gap
}
eta_by_month <- bind_rows(month_eta("S1"), month_eta("S2"))
write_csv(eta_by_month, file.path(TAB, "eta_by_month.csv"))

# Recency-weighted pooled constant eta (robustness; half-life RECENCY_HL months).
recency_eta <- function(baseline) {
  w <- wcol_for(baseline)
  tr <- filter(cells, period == "train")
  decay <- 0.5 ^ ((TEST_YM - tr$ym) / RECENCY_HL)    # newer months weigh more
  setr <- sum(tr[[w]] * decay * tr$rate_h2avg) / sum(tr[[w]] * decay)
  cetr <- sum(tr$cal_dut_mo * decay) / sum(tr$con_val_mo * decay)
  tibble(baseline = baseline,
         eta_pooled  = 1 - treas_train_etr /
           (sum(tr[[w]] * tr$rate_h2avg) / sum(tr[[w]])),
         eta_recency_census = 1 - cetr / setr)
}
eta_recency <- bind_rows(recency_eta("S1"), recency_eta("S2"))
write_csv(eta_recency, file.path(TAB, "eta_recency.csv"))

# Pooled constant eta over a training window (excludes the held-out test month).
# Treasury-calibrated (the level we adopt) and Census-based variants, plus the
# implied statutory/collected ETRs so the window comparison is fully legible.
pooled_constant <- function(baseline, lo, label) {
  w <- wcol_for(baseline)
  d <- cells %>% filter(ym >= lo, ym <= WIN_HI, ym != TEST_YM)
  r <- rev    %>% filter(ym >= lo, ym <= WIN_HI, ym != TEST_YM)
  setr <- sum(d[[w]] * d$rate_h2avg) / sum(d[[w]])
  cetr <- sum(d$cal_dut_mo) / sum(d$con_val_mo)
  tetr <- sum(r$customs_duties) / sum(r$imports_value)
  tibble(baseline = baseline, window = label,
         n_months = n_distinct(d$ym),
         setr = setr, census_etr = cetr, treas_etr = tetr,
         eta_treas = 1 - tetr / setr, eta_census = 1 - cetr / setr)
}
eta_by_window <- bind_rows(
  pooled_constant("S1", WIN_LO,     "full (2025m1-2026m2)"),
  pooled_constant("S1", POSTAPR_LO, "post-Apr (2025m5-2026m2)"),
  pooled_constant("S2", WIN_LO,     "full (2025m1-2026m2)"),
  pooled_constant("S2", POSTAPR_LO, "post-Apr (2025m5-2026m2)"))
write_csv(eta_by_window, file.path(TAB, "eta_by_window.csv"))

# S2 (composition-adjusted, Treasury-calibrated) constants for the month chart.
eta_const_full <- eta_by_window$eta_treas[eta_by_window$baseline == "S2" &
                                          grepl("^full", eta_by_window$window)]
eta_const_pa   <- eta_by_window$eta_treas[eta_by_window$baseline == "S2" &
                                          grepl("^post", eta_by_window$window)]

# ---------------------------------------------------------------------------
# 6. Where the gap concentrates: eta by country and by product (two-way, S2)
# ---------------------------------------------------------------------------
msg("[4] Cross-section of eta x 2 baselines x 2 training windows...")
# Marginal Census-declared compliance gap by partner / by chapter, for each
# baseline (S1 announced / S2 composition-adjusted) and training window.
cross_section <- function(bl, train_lo, win_lab) {
  tr <- filter(cells, ym >= train_lo, ym != TEST_YM)
  list(
    ctry = group_agg(tr, "partner_group", bl) %>%
      transmute(baseline = bl, train_window = win_lab, partner_group, statwt, setr,
                census_etr = aetr, eta = 1 - om_eta),
    prod = group_agg(tr, "hs2", bl) %>%
      transmute(baseline = bl, train_window = win_lab, hs2, statwt, setr,
                census_etr = aetr, eta = 1 - om_eta) %>%
      filter(is.finite(eta)))
}
cs <- list()
for (bl in c("S1", "S2")) for (win in windows)
  cs[[length(cs) + 1]] <- cross_section(bl, win$lo, win$lab)
eta_by_country <- bind_rows(lapply(cs, `[[`, "ctry")) %>% arrange(baseline, train_window, desc(eta))
eta_by_product <- bind_rows(lapply(cs, `[[`, "prod")) %>% arrange(baseline, train_window, desc(statwt))
write_csv(eta_by_country, file.path(TAB, "eta_by_country.csv"))
write_csv(eta_by_product, file.path(TAB, "eta_by_product.csv"))

# ---------------------------------------------------------------------------
# 6b. Bundle all eta tables into a single workbook for exploration
# ---------------------------------------------------------------------------
# Leading "readme" sheet documents what each tab holds; one sheet per table.
readme <- tribble(
  ~sheet,           ~contents,
  "summary",        "Every train_window x baseline x spec x granularity calibration (20 rows). eta_agg = Census-shape aggregate gap (no k); eta_treas_agg = Treasury-calibrated aggregate gap (the headline, = 1-k*(1-eta_agg)); plus k, train/March RMSE, OOS error + shape/level decomposition. march_err_pp uses the ACTUAL March basket; march_err_fcst_pp is the stricter test that also withholds the March basket (carries forward the last training month, 2026m2), with fcst_basket_coverage = share of March trade value covered. train_window = full (2025m1-2026m2) vs post-Apr (2025m5-2026m2); test month always 2026m3.",
  "by_window",      "Pooled constant eta by training window, Treasury- and Census-calibrated, with implied ETRs. Lead value: S2 post-Apr ~19% (full ~23%).",
  "by_month",       "Monthly statutory/Census/Treasury ETR and the two monthly eta measures, per baseline (window-independent).",
  "recency",        "Recency-weighted (half-life 6mo) constant eta vs the flat full-window pooled value, per baseline.",
  "by_country",     "Marginal Census eta by partner group, for BOTH baselines (S1/S2) x BOTH training windows.",
  "by_product",     "Marginal Census eta by HTS-2 chapter, for BOTH baselines (S1/S2) x BOTH training windows, sorted by statutory weight.")
sheets <- list(readme = readme, summary = eta_summary, by_window = eta_by_window,
               by_month = eta_by_month, recency = eta_recency,
               by_country = eta_by_country, by_product = eta_by_product)
xlsx_path <- file.path(TAB, "eta_analysis.xlsx")
write_xlsx(sheets, xlsx_path)
msg("    -> %s (%d sheets)", xlsx_path, length(sheets))

# ---------------------------------------------------------------------------
# 7. Figures
# ---------------------------------------------------------------------------
msg("[5] Figures...")
ym_to_date <- function(ym) as.Date(sprintf("%d-%02d-01", 1960 + ym %/% 12, ym %% 12 + 1))

# All four figures for one statutory baseline. S2 (composition-adjusted) writes
# the canonical unsuffixed files; S1 (announced) writes parallel *_announced files.
make_figures <- function(bl, suffix, bl_label) {
  cw <- eta_by_window$eta_treas[eta_by_window$baseline == bl & grepl("^full", eta_by_window$window)]
  cp <- eta_by_window$eta_treas[eta_by_window$baseline == bl & grepl("^post", eta_by_window$window)]

  # --- monthly eta vs flat 10% + the two calibrated constants (Treasury) ---
  df_m <- eta_by_month %>% filter(baseline == bl) %>%
    mutate(date = ym_to_date(ym)) %>%
    select(date, eta_treas, eta_census) %>%
    pivot_longer(c(eta_treas, eta_census), names_to = "measure", values_to = "eta") %>%
    mutate(measure = recode(measure,
                            eta_treas  = "vs Treasury (calibration target)",
                            eta_census = "vs Census-declared"))
  xr <- range(df_m$date)
  p_month <- ggplot(df_m, aes(date, eta, colour = measure)) +
    geom_hline(yintercept = CURRENT_COMPLIANCE, linetype = "dashed", colour = "grey45") +
    geom_hline(yintercept = cw, linetype = "dashed", colour = "#1f4e79") +
    geom_hline(yintercept = cp, linetype = "dotted", colour = "#2e7d32", linewidth = 0.8) +
    annotate("text", x = xr[1], y = CURRENT_COMPLIANCE - 0.013,
             label = "current flat 10% assumption", hjust = 0, size = 3, colour = "grey45") +
    annotate("text", x = xr[2], y = cw + 0.013, hjust = 1, size = 3, colour = "#1f4e79",
             label = sprintf("calibrated constant, full window (%.0f%%)", 100 * cw)) +
    annotate("text", x = xr[2], y = cp - 0.013, hjust = 1, size = 3, colour = "#2e7d32",
             label = sprintf("calibrated constant, post-Apr 2025 (%.0f%%)", 100 * cp)) +
    geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    scale_colour_manual(values = c("vs Treasury (calibration target)" = "#1f4e79",
                                   "vs Census-declared" = "#c0504d")) +
    labs(title = expression(paste("Calibrated compliance gap ", eta, " by month")),
         subtitle = paste0(bl_label, " statutory baseline; share of statutory revenue not collected"),
         x = NULL, y = expression(eta), colour = NULL) +
    theme_minimal(base_size = 12) + theme(legend.position = "top")
  ggsave(file.path(FIG, paste0("figure_eta_by_month", suffix, ".png")), p_month,
         width = 8, height = 5, dpi = 150)

  # --- eta by partner group, full vs post-April training window ---
  ec <- eta_by_country %>% filter(baseline == bl)
  ord_c <- ec %>% filter(train_window == "full") %>% arrange(eta) %>% pull(partner_group)
  p_ctry <- ec %>%
    mutate(partner_group = factor(partner_group, levels = ord_c),
           train_window = factor(train_window, levels = c("full", "post-Apr"))) %>%
    ggplot(aes(eta, partner_group)) +
    geom_col(fill = "#1f4e79") +
    geom_vline(xintercept = CURRENT_COMPLIANCE, linetype = "dashed", colour = "grey40") +
    facet_wrap(~ train_window) +
    scale_x_continuous(labels = percent_format(accuracy = 1)) +
    labs(title = expression(paste("Compliance gap ", eta, " by partner")),
         subtitle = paste0("Marginal Census ratio, ", bl_label, "; full vs post-April 2025 training window"),
         x = expression(eta), y = NULL) +
    theme_minimal(base_size = 12)
  ggsave(file.path(FIG, paste0("figure_eta_by_country", suffix, ".png")), p_ctry,
         width = 8.5, height = 4.5, dpi = 150)

  # --- eta by product (top-15 chapters by trade), full vs post-April ---
  ep <- eta_by_product %>% filter(baseline == bl)
  top15 <- ep %>% filter(train_window == "full") %>% slice_max(statwt, n = 15) %>% pull(hs2)
  ord_p <- ep %>% filter(train_window == "full", hs2 %in% top15) %>% arrange(eta) %>% pull(hs2)
  p_prod <- ep %>%
    filter(hs2 %in% top15) %>%
    mutate(hs2 = factor(hs2, levels = ord_p),
           train_window = factor(train_window, levels = c("full", "post-Apr"))) %>%
    ggplot(aes(eta, hs2)) +
    geom_col(fill = "#4f81bd") +
    geom_vline(xintercept = CURRENT_COMPLIANCE, linetype = "dashed", colour = "grey40") +
    facet_wrap(~ train_window) +
    scale_x_continuous(labels = percent_format(accuracy = 1)) +
    labs(title = expression(paste("Compliance gap ", eta, " by product (top-15 chapters by trade)")),
         subtitle = paste0(bl_label, "; full vs post-April 2025 training window"),
         x = expression(eta), y = "HTS-2 chapter") +
    theme_minimal(base_size = 11)
  ggsave(file.path(FIG, paste0("figure_eta_by_product", suffix, ".png")), p_prod,
         width = 8.5, height = 5.5, dpi = 150)

  # --- train fit vs OOS error by spec, faceted by training window ---
  db <- eta_summary %>% filter(baseline == bl) %>%
    mutate(train_window = factor(train_window, levels = c("full", "post-Apr")))
  p_bv <- ggplot(db, aes(train_xsec_rmse * 100, abs(march_err_pp))) +
    geom_point(aes(colour = spec), size = 3) +
    geom_text(aes(label = granularity), size = 2.4, vjust = -0.9, colour = "grey30") +
    facet_wrap(~ train_window) +
    scale_x_continuous(expand = expansion(mult = 0.12)) +
    labs(title = "Bias-variance: in-sample fit vs out-of-sample error",
         subtitle = paste0(bl_label, " baseline. Flexibility tightens train fit (left), but OOS error stays small and unordered"),
         caption = "RMSE not comparable across panels (different training samples).",
         x = "Train cross-sectional RMSE (pp)", y = "|March OOS error| (pp)", colour = NULL) +
    theme_minimal(base_size = 12) + theme(legend.position = "top")
  ggsave(file.path(FIG, paste0("figure_eta_train_test", suffix, ".png")), p_bv,
         width = 9, height = 5, dpi = 150)
}

make_figures("S2", "",          "composition-adjusted")
make_figures("S1", "_announced", "announced (2024 fixed basket)")

# ---------------------------------------------------------------------------
# 8. Console summary
# ---------------------------------------------------------------------------
msg("\n================ CALIBRATION SUMMARY ================")
eta_summary %>%
  transmute(train_window, baseline, spec, granularity,
            eta_cens = round(eta_agg, 4), eta_treas = round(eta_treas_agg, 4),
            k_train = round(k_train, 3),
            train_rmse_pp = round(train_xsec_rmse * 100, 3),
            march_err_pp = round(march_err_pp, 3),
            march_err_fcst_pp = round(march_err_fcst_pp, 3),
            fcst_cov = round(fcst_basket_coverage, 3)) %>%
  as.data.frame() %>% print(row.names = FALSE)
msg("\nPooled constant eta by window (Treasury- and Census-calibrated):")
eta_by_window %>%
  transmute(baseline, window, n_months,
            setr = round(setr, 4), treas_etr = round(treas_etr, 4),
            eta_treas = round(eta_treas, 4), eta_census = round(eta_census, 4)) %>%
  as.data.frame() %>% print(row.names = FALSE)
msg("\nRecency-weighted constant eta:")
as.data.frame(eta_recency) %>% print(row.names = FALSE)
msg("\nTables  -> %s/eta_{summary,by_month,recency,by_window,by_country,by_product}.csv", TAB)
msg("Workbook-> %s/eta_analysis.xlsx (all tables as sheets)", TAB)
msg("Figures -> %s/figure_eta_{by_month,by_country,by_product,train_test}[_announced].png", FIG)
msg("           (unsuffixed = composition-adjusted S2; _announced = S1 fixed-2024 basket)")
msg("Done.")
