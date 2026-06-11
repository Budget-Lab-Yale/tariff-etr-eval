# =============================================================================
# adcvd_strip.R — remove AD/CVD from the COLLECTED side before calibrating eta
# =============================================================================
# Ported from ../tariff-etr-adj/code/adcvd_strip.R and adapted to this repo's
# 08_eta_calibration.R conventions (Stata monthly-integer `ym`, the `cells`
# panel, the `rev` monthly Treasury table where `treas_etr` is the separately
# sourced `actual_rate`). Sourced by 08_eta_calibration.R but INERT until a
# curated CBP AD/CVD-collected input exists at resources/adcvd_collected.csv
# (until then load_adcvd_collected() returns NULL and the calibration is
# unchanged). See ../tariff-rate-tracker/docs/analysis/eta_compliance_gap_drivers.md
# and ../tariff-rate-tracker/docs/adcvd_layer_design.md §"Decision (2026-06-08)"
# for why we strip rather than model AD/CVD statutorily.
#
# WHY THIS EXISTS
# ---------------
# Calibrated eta is 1 - k * (collected ETR / statutory ETR). The tracker's
# statutory rate (rate_h2avg) carries NO antidumping/countervailing duty, but
# the collected side does, so AD/CVD pushes eta negative — but ONLY where
# statutory is low enough for collected to exceed it. The spot check
# (code/R/adcvd_spot_check.R) locates the over-collection cluster in
# LOW-statutory machinery / instruments / solar: HS84/85/90 and bearings
# (HTS8482) for Japan / EU / UK / Korea (collected ~+$1B over statutory each on
# ch84), plus Vietnam HS85 solar (~+$1.2B). NOTE: HS72/73 steel is NOT in this
# cluster — its §232 (+§301/IEEPA for China) statutory of 25-86% dwarfs
# collections, so steel runs net UNDER-collected (positive eta) for every
# partner and any AD/CVD there is masked. That over-collection is a statutory
# COVERAGE gap, not a compliance gap, and eta should not absorb it. We remove
# AD/CVD from the collected numerator(s) so the deliverable eta means
# "compliance gap" and nothing else.
#
# DO EXACTLY ONE (double-count guard). Either strip AD/CVD from the collected
# side HERE, or model it as a statutory rung (a tracker `rate_adcvd` layer).
# NOT both — doing both removes the AD/CVD wedge twice. Verified (2026-06-08):
# no .do file in this repo adds AD/CVD to the statutory side, so the strip is
# the only place AD/CVD is handled. Keep it that way.
#
# STRIP BOTH SIDES, BY THE SAME DOLLARS (the project decision)
# ------------------------------------------------------------
# The Treasury-calibrated aggregate eta is, exactly, 1 - treas_train_etr / setr
# (the Census shape `om` cancels out of 1 - k*(1 - eta_agg)). So the two strips
# do DIFFERENT jobs:
#   - Census `cal_dut_mo` strip  -> changes ONLY the per-cell DISTRIBUTION of
#     etas (which partner x chapter cells the pull-back lands on). It cannot
#     move the aggregate.
#   - Treasury `customs_duties` strip -> the ONLY thing that moves the aggregate
#     eta (lowers treas_train_etr).
# Strip Census alone and k = treas/pred_etr rises to re-absorb exactly what you
# removed (aggregate is pinned), so it is pure redistribution. You must strip
# BOTH, by the SAME realized dollars, so the distributional fix (Census) and the
# level change (Treasury) stay mutually consistent and k is left ~neutral.
#
# We guarantee the match BY CONSTRUCTION: allocate the curated AD/CVD onto
# Census cells once, take the realized per-cell reduction (after the no-negative
# floor), and derive the Treasury monthly removal as the SUM of that same
# realized reduction per month. Treasury-removed == Census-removed, month by
# month — no `unplaced`/window drift is possible. The run logs the matched
# total so the invariant is visible.
#
# DOES Census `cal_dut_mo` INCLUDE AD/CVD?  (resolved: assume YES)
# ----------------------------------------------------------------
# Observed collections settle it: e.g. Vietnam ch85 collects ~$1.26B in
# cal_dut_mo on solar lines the tracker correctly models at statutory 0 — duty
# with no schedule rate behind it can only be AD/CVD. So CENSUS_INCLUDES_ADCVD
# defaults TRUE and we strip the Census shape as well as the Treasury level.
# Confirm with code/R/adcvd_spot_check.R before publishing; flip to FALSE only
# if the check comes back clean (then the Treasury-only fallback runs and the
# schedule's per-cell distribution is left untouched).
#
# GRANULARITY CAVEAT
# ------------------
# No public HTS- or country-level AD/CVD *collection* breakdown exists — only
# orders *coverage*. The only published collected magnitudes are aggregate /
# by-program / by-major-partner CBP figures (e.g. FY2025 assessed: Mexico
# $5.56B, Canada $1.95B). So the curated input is coarse (partner [x period]
# [x chapter]) and we ALLOCATE it down to cells by import value. This is an
# order-of-magnitude correction, not a per-cell read; label any eta produced
# with the strip as AD/CVD-adjusted-approximate. Where a cell's allocated AD/CVD
# exceeds its declared duty the excess is floored away (never negative duty) and
# reported as "floored" — a large floored total means the import-value
# allocation is landing dollars on low-duty cells.
#
# CURATED INPUT — resources/adcvd_collected.csv (see .TEMPLATE.csv)
#   partner_group  chr   one of ADCVD_PARTNER_LEVELS below: China / Canada /
#                        Mexico / EU / Japan / "S. Korea" / UK / ROW — note the
#                        EXACT strings (Korea is "S. Korea", with the space;
#                        mirrors assign_partner_group in code/utils/programs.do).
#   year_month     chr   "YYYY-MM", or blank to spread one figure across the
#                        calibration window (train + test months) by import value
#   hs2            chr   2-digit chapter, or blank to spread across all chapters
#                        in that partner proportional to import value
#   adcvd_usd      dbl   AD/CVD cash deposits collected/assessed, in DOLLARS
#                        (same units as cal_dut_mo / con_val_mo; Treasury
#                        customs_duties is $M and is handled by the rescale here)
# Comment lines beginning '#' are skipped.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr)
})

ADCVD_COLLECTED_PATH <- file.path("resources", "adcvd_collected.csv")

# Partner-group strings, EXACT (mirrors assign_partner_group, programs.do).
ADCVD_PARTNER_LEVELS <- c("China", "Canada", "Mexico", "EU",
                          "Japan", "S. Korea", "UK", "ROW")

# Switch: see "DOES Census cal_dut_mo INCLUDE AD/CVD?" above. Default TRUE — the
# project decision is to strip BOTH sides by the same dollars. Set FALSE only if
# the spot check shows cal_dut_mo excludes AD/CVD; the Treasury-only fallback
# then runs and the per-cell schedule distribution is left untouched.
CENSUS_INCLUDES_ADCVD <- TRUE

# msg() is defined by 08_eta_calibration.R; provide a fallback if sourced alone.
if (!exists("msg")) msg <- function(...) cat(sprintf(...), "\n")

# Local safe divide (this repo's R has no shared helper): 0 where denom <= 0.
.adcvd_safe_divide <- function(num, den) ifelse(den > 0, num / den, 0)

# "YYYY-MM" -> Stata monthly integer ym = (year-1960)*12 + (month-1); NA->NA.
.ym_from_label <- function(x) {
  out <- rep(NA_integer_, length(x))
  ok <- !is.na(x) & grepl("^[0-9]{4}-[0-9]{1,2}$", x)
  if (any(ok)) {
    y <- as.integer(substr(x[ok], 1, 4))
    m <- as.integer(sub("^[0-9]{4}-", "", x[ok]))
    out[ok] <- (y - 1960L) * 12L + (m - 1L)
  }
  out
}

#' Load the curated CBP AD/CVD-collected table.
#'
#' @param path CSV path (default ADCVD_COLLECTED_PATH).
#' @return tibble(partner_group, year_month, hs2, adcvd_usd, ym) with NA for
#'   blank dimension columns (ym = integer month, NA when year_month blank);
#'   NULL if the file is absent or has no data rows (caller then no-ops — the
#'   calibration is unchanged).
load_adcvd_collected <- function(path = ADCVD_COLLECTED_PATH) {
  if (!file.exists(path)) {
    msg("    AD/CVD strip: %s not found — no-op (eta unchanged).", path)
    return(NULL)
  }
  ct <- cols(partner_group = col_character(), year_month = col_character(),
             hs2 = col_character(), adcvd_usd = col_double())
  adcvd <- read_csv(path, col_types = ct, comment = "#", show_col_types = FALSE)
  adcvd <- adcvd %>%
    mutate(across(c(partner_group, year_month, hs2),
                  ~ ifelse(is.na(.) | !nzchar(.), NA_character_, .)),
           ym = .ym_from_label(year_month))
  if (nrow(adcvd) == 0) return(NULL)
  bad <- setdiff(na.omit(unique(adcvd$partner_group)), ADCVD_PARTNER_LEVELS)
  if (length(bad)) warning("AD/CVD strip: unknown partner_group(s): ",
                           paste(bad, collapse = ", "), " (expected one of: ",
                           paste(ADCVD_PARTNER_LEVELS, collapse = ", "), ")")
  bad_ym <- !is.na(adcvd$year_month) & is.na(adcvd$ym)
  if (any(bad_ym)) warning("AD/CVD strip: unparseable year_month(s): ",
                           paste(unique(adcvd$year_month[bad_ym]), collapse = ", "),
                           " (expected 'YYYY-MM' or blank)")
  adcvd
}

#' Allocate coarse AD/CVD dollars onto IN-SCOPE panel cells by import value.
#'
#' Each input row carries `adcvd_usd` for a (partner_group [, ym] [, hs2]) block.
#' Distribute it across the matching panel cells in proportion to `con_val_mo`
#' (import value). Matching is restricted to cells whose `period` is in `periods`
#' (default train + test). Blank year_month (ym = NA) spreads the figure across
#' every in-scope month in the block; blank hs2 spreads across all chapters.
#' Rows whose block matches no in-scope cell are reported and dropped.
#'
#' @param adcvd output of load_adcvd_collected().
#' @param panel the analysis panel `cells` (needs partner_group, hs2, ym,
#'   con_val_mo, period).
#' @param periods cell periods eligible to receive AD/CVD (default
#'   c("train","test")).
#' @return panel + numeric column `adcvd_dut` (AD/CVD $ assigned to each cell,
#'   0 where none); attribute "unplaced_usd" = dollars that matched no cell.
allocate_adcvd_to_cells <- function(adcvd, panel, periods = c("train", "test")) {
  stopifnot(all(c("partner_group", "hs2", "ym", "con_val_mo", "period")
                %in% names(panel)))
  panel$.row <- seq_len(nrow(panel))
  in_scope <- panel$period %in% periods
  alloc <- numeric(nrow(panel))
  unplaced <- 0

  for (i in seq_len(nrow(adcvd))) {
    r <- adcvd[i, ]
    keep <- in_scope & panel$partner_group == r$partner_group
    if (!is.na(r$ym))  keep <- keep & panel$ym == r$ym
    if (!is.na(r$hs2)) keep <- keep & panel$hs2 == r$hs2
    block <- panel[keep, , drop = FALSE]
    denom <- sum(block$con_val_mo, na.rm = TRUE)
    if (nrow(block) == 0 || denom <= 0) { unplaced <- unplaced + r$adcvd_usd; next }
    alloc[block$.row] <- alloc[block$.row] +
      r$adcvd_usd * (block$con_val_mo / denom)
  }

  if (unplaced > 0)
    msg("    AD/CVD strip: $%.3gB could not be placed (no matching in-scope trade).",
        unplaced / 1e9)
  panel$.row <- NULL
  panel$adcvd_dut <- alloc
  attr(panel, "unplaced_usd") <- unplaced
  panel
}

#' Strip AD/CVD from BOTH the Census shape and the Treasury level, matched.
#'
#' The single entry point used by the pipeline. Allocates the curated AD/CVD onto
#' Census cells, removes the realized per-cell amount from `cal_dut_mo` (floored
#' at 0) and recomputes `census_etr`, then removes that SAME realized amount —
#' summed per month — from Treasury `customs_duties`. Because the Treasury
#' removal is derived from the realized Census removal, Treasury-removed ==
#' Census-removed in every month by construction. When CENSUS_INCLUDES_ADCVD is
#' FALSE the Census shape is left untouched and only the Treasury level is
#' stripped (by the curated total restricted to in-scope months) — the fallback.
#'
#' NOTE (eval-specific): `rev$treas_etr` here is the separately sourced
#' `actual_rate`, not customs_duties/imports_value. To preserve that definition
#' we strip treas_etr by SUBTRACTING the removed AD/CVD rate ((rm/1e6) /
#' imports_value) rather than recomputing the ratio — so only the AD/CVD wedge
#' moves and any pre-existing actual_rate-vs-ratio gap is kept intact.
#'
#' @param panel analysis panel `cells`; needs the columns
#'   allocate_adcvd_to_cells() requires plus cal_dut_mo, con_val_mo, census_etr.
#' @param rev monthly Treasury tibble with ym, customs_duties ($M),
#'   imports_value ($M), treas_etr (ratio).
#' @param adcvd output of load_adcvd_collected().
#' @param periods cell periods to strip (default train + test).
#' @return list(panel = stripped cells, rev = stripped rev).
apply_adcvd_strip <- function(panel, rev, adcvd, periods = c("train", "test")) {
  panel <- allocate_adcvd_to_cells(adcvd, panel, periods)
  unplaced <- attr(panel, "unplaced_usd")

  if (CENSUS_INCLUDES_ADCVD) {
    # Realized per-cell reduction: never drive declared duty negative.
    removed  <- pmin(panel$adcvd_dut, panel$cal_dut_mo)
    floored  <- sum(panel$adcvd_dut - removed)
    etr_before <- sum(panel$cal_dut_mo[panel$period %in% periods]) /
                  sum(panel$con_val_mo[panel$period %in% periods])
    panel$cal_dut_mo <- panel$cal_dut_mo - removed
    if ("census_etr" %in% names(panel))
      panel$census_etr <- .adcvd_safe_divide(panel$cal_dut_mo, panel$con_val_mo)
    etr_after <- sum(panel$cal_dut_mo[panel$period %in% periods]) /
                 sum(panel$con_val_mo[panel$period %in% periods])
    # Treasury removal = the SAME realized dollars, by month.
    rm_by_month <- tibble(ym = panel$ym, rm = removed) %>%
      group_by(ym) %>% summarise(rm = sum(rm), .groups = "drop")
    matched <- sum(removed)
  } else {
    # Fallback: Treasury level only. Remove the curated total (less anything
    # that fell outside in-scope trade), spread to months by in-scope import
    # value so the train window is respected.
    floored <- 0
    placed  <- sum(panel$adcvd_dut)
    wt      <- ifelse(panel$period %in% periods, panel$con_val_mo, 0)
    wsum    <- sum(wt)
    rm_by_month <- tibble(ym = panel$ym,
                          rm = if (wsum > 0) placed * wt / wsum else 0) %>%
      group_by(ym) %>% summarise(rm = sum(rm), .groups = "drop")
    matched <- placed
  }
  panel$adcvd_dut <- NULL

  rev <- rev %>%
    left_join(rm_by_month, by = "ym") %>%
    mutate(rm = coalesce(rm, 0),
           customs_duties = pmax(customs_duties - rm / 1e6, 0),
           treas_etr = pmax(treas_etr - .adcvd_safe_divide(rm / 1e6, imports_value), 0)) %>%
    select(-rm)

  if (CENSUS_INCLUDES_ADCVD) {
    msg("    AD/CVD strip: removed Treasury $%.3gB == Census $%.3gB (matched); collected ETR %.4f -> %.4f (-%.0fbp)",
        matched / 1e9, matched / 1e9, etr_before, etr_after,
        (etr_before - etr_after) * 1e4)
    if (floored > 0)
      msg("    AD/CVD strip: $%.3gB floored (allocated AD/CVD exceeded declared duty in some cells).",
          floored / 1e9)
  } else {
    msg("    AD/CVD strip (Treasury level only; CENSUS_INCLUDES_ADCVD=FALSE): removed $%.3gB.",
        matched / 1e9)
  }
  if (unplaced > 0)
    msg("    AD/CVD strip: note $%.3gB unplaced was NOT removed from either side (kept matched).",
        unplaced / 1e9)

  list(panel = panel, rev = rev)
}

# -----------------------------------------------------------------------------
# Integration (active in 08_eta_calibration.R, just after `cells` and `rev` are
# loaded and BEFORE treas_train_etr / treas_march_etr are derived):
#
#   source("code/R/adcvd_strip.R")
#   adcvd <- load_adcvd_collected()
#   if (!is.null(adcvd)) {
#     st <- apply_adcvd_strip(cells, rev, adcvd)   # strips train + test cells
#     cells <- st$panel; rev <- st$rev
#   }
#
# Everything downstream (treas_train_etr, treas_march_etr, the shape, the OOS
# test, the cross-sections) then reads the stripped objects, so the Census shape
# and the Treasury level move together. Effect: pulls the Japan/UK/EU (and
# China/Korea) negative etas back toward zero by the AD/CVD share of their
# collections, lowers the aggregate eta by the AD/CVD share of total receipts,
# and leaves k ~neutral — all WITHOUT touching the tracker's statutory rates.
# The strip operates on in-memory objects only; it never edits data/working/.
# -----------------------------------------------------------------------------
