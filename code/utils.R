# =============================================================================
# utils.R — shared constants and helpers for the tariff-etr-eval R pipeline
# =============================================================================
# Sourced by every pipeline script (01b/02a/02b/02c/03a/03b). Ports the
# foundation layer of the retired Stata pipeline (archive/stata/code/utils/
# globals.do + programs.do) and mirrors conventions in the sibling repo
# tariff-etr-adj (code/utils.R there), which is the production home of the
# eta-calibration work.
#
# Conventions:
#   - year_month is a "YYYY-MM" character key everywhere (sortable, readable
#     in CSVs); ym_date() converts to Date for plotting.
#   - Tier values (S0..S4, T) are in PERCENT; gap channels in percentage
#     points. Rates on the panel are ratios (0.25 = 25%).
#   - All paths are relative to the repo root (here::here()).
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr)
})

# --- Paths -------------------------------------------------------------------
DIR_RAW       <- "data/raw"
DIR_PROCESSED <- "data/processed"
DIR_TABLES    <- "results/tables"
DIR_FIGURES   <- "results/figures"
for (d in c(DIR_PROCESSED, DIR_TABLES, DIR_FIGURES))
  dir.create(d, showWarnings = FALSE, recursive = TRUE)

msg <- function(...) cat(sprintf(...), "\n")

# --- Analysis window ---------------------------------------------------------
ANALYSIS_LO <- "2025-01"
ANALYSIS_HI <- "2026-03"

ym_date <- function(ym) as.Date(paste0(ym, "-01"))
# Stata %tm integer (months since 1960m1) — used by the VMR event arithmetic
# and when comparing against Stata-exported CSVs.
ym_int <- function(ym) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7))
  (y - 1960L) * 12L + (m - 1L)
}
int_ym <- function(i) sprintf("%04d-%02d", 1960L + i %/% 12L, i %% 12L + 1L)
# Stata's CSV export renders %tm as "2025m1" — parse those when validating.
stata_ym <- function(s) {
  y <- as.integer(sub("m.*", "", s)); m <- as.integer(sub(".*m", "", s))
  sprintf("%04d-%02d", y, m)
}

# --- Partner groups (Census country codes; ports assign_partner_group) -------
CTY_CHINA <- "5700"; CTY_CANADA <- "1220"; CTY_MEXICO <- "2010"
CTY_JAPAN <- "5880"; CTY_SKOREA <- "5800"; CTY_UK     <- "4120"
# EU27 Census Schedule C codes, verified against the tracker's
# resources/census_codes.csv (the archived globals.do list had off-by-a-digit
# codes -- 4270/4760/etc. -- that sent FR, IT, NL, BE, IE, AT, SE, DK, FI to ROW).
EU_CODES <- c("4330","4231","4870","4791","4910","4351","4099","4470","4050",
              "4279","4280","4840","4370","4190","4759","4490","4510","4239",
              "4730","4210","4550","4710","4850","4359","4792","4700","4010")
PARTNER_LEVELS <- c("China","Canada","Mexico","EU","Japan","S. Korea","UK","ROW")

assign_partner_group <- function(cty) {
  pg <- rep("ROW", length(cty))
  pg[cty == CTY_CHINA]  <- "China";    pg[cty == CTY_CANADA] <- "Canada"
  pg[cty == CTY_MEXICO] <- "Mexico";   pg[cty == CTY_JAPAN]  <- "Japan"
  pg[cty == CTY_SKOREA] <- "S. Korea"; pg[cty == CTY_UK]     <- "UK"
  pg[cty %in% EU_CODES] <- "EU"
  factor(pg, levels = PARTNER_LEVELS)
}

PRODUCT_LEVELS <- c("Steel & Aluminum","Autos & Auto Parts",
                    "Electronics & Machinery","Pharmaceuticals",
                    "Energy & Minerals","Chemicals & Plastics",
                    "Apparel & Textiles","Food & Agriculture",
                    "Other Manufactured")

# --- Wong colorblind-safe palette (Nature Methods 8, 441; 2011) --------------
COL_ACTUAL <- "#D55E00"; COL_STATUTORY <- "#0072B2"
COL_GAP    <- "#009E73"; COL_GRAY      <- "#999999"
PARTNER_COLS <- c("China"="#D55E00","Canada"="#0072B2","Mexico"="#009E73",
                  "EU"="#F0E442","Japan"="#CC79A7","S. Korea"="#E69F00",
                  "UK"="#56B4E9","ROW"="#999999")
PRODUCT_COLS <- c("Steel & Aluminum"="#D55E00","Autos & Auto Parts"="#E69F00",
                  "Electronics & Machinery"="#0072B2","Pharmaceuticals"="#56B4E9",
                  "Energy & Minerals"="#CC79A7","Chemicals & Plastics"="#999999",
                  "Apparel & Textiles"="#F0E442","Food & Agriculture"="#009E73",
                  "Other Manufactured"="#C8C8C8")

# --- Policy event dates (figure reference lines) ------------------------------
POLICY_EVENTS <- tibble::tribble(
  ~date,                ~label,
  as.Date("2025-02-04"), "Fentanyl",
  as.Date("2025-03-12"), "232 Autos",
  as.Date("2025-04-02"), "Liberation Day",
  as.Date("2025-04-09"), "Phase 1 Pause",
  as.Date("2025-07-01"), "Phase 2",
  as.Date("2025-08-07"), "Phase 2 Recip.",
  as.Date("2026-02-24"), "SCOTUS / S.122")

# --- Small numeric helpers ----------------------------------------------------
#' Coerce any integer64 columns (from data.table::fread on >2^31 values) to
#' double, in place. integer64 silently corrupts double arithmetic in dplyr
#' pipelines, so every fread in this pipeline passes through this sweep.
fix_int64 <- function(dt) {
  if (!requireNamespace("bit64", quietly = TRUE)) return(dt)
  for (j in names(dt))
    if (inherits(dt[[j]], "integer64"))
      data.table::set(dt, j = j, value = as.numeric(dt[[j]]))
  dt
}

safe_divide <- function(num, den, default = NA_real_) {
  out <- ifelse(!is.na(den) & den != 0, num / den, default)
  ifelse(is.na(out), default, out)
}

# --- Tier aggregation (ports programs.do::compute_tier) -----------------------
#' Value-weighted aggregate ETR tier, in percent, by month (x optional group).
#' sum(rate * weight) / sum(weight) * 100 over the panel rows.
compute_tier <- function(df, rate, weight, out, by = NULL) {
  df %>%
    group_by(across(all_of(c("year_month", by)))) %>%
    summarise(num = sum(.data[[rate]] * .data[[weight]], na.rm = TRUE),
              den = sum(.data[[weight]], na.rm = TRUE), .groups = "drop") %>%
    mutate(!!out := 100 * safe_divide(num, den, 0)) %>%
    select(all_of(c("year_month", by, out)))
}

# --- Shapley two-way decomposition (ports compute_diversion_decomp) -----------
#' Fixed-rate, weights-shift gap split into between- and within-group parts.
#'
#' For the S1 -> S2 channel: rates held at `rate`, weights shift from the 2024
#' annual basket (`w24`, the `imports` column) to actual monthly value (`wmo`,
#' `con_val_mo`). With R_g the group value-weighted rate and s_g the group
#' weight share,
#'   gap = sum_g 0.5*(R_g_24 + R_g_mw)*(s_g_24 - s_g_mw)   <- between
#'       + sum_g 0.5*(s_g_24 + s_g_mw)*(R_g_24 - R_g_mw)   <- within
#' Output in pp; the two parts sum to the ladder's gap_diversion each month.
shapley_decomp <- function(df, rate, by, w24 = "imports", wmo = "con_val_mo") {
  df %>%
    group_by(across(all_of(c("year_month", by)))) %>%
    summarise(num_24 = sum(.data[[rate]] * .data[[w24]], na.rm = TRUE),
              num_mw = sum(.data[[rate]] * .data[[wmo]], na.rm = TRUE),
              w24    = sum(.data[[w24]], na.rm = TRUE),
              wmo    = sum(.data[[wmo]], na.rm = TRUE), .groups = "drop") %>%
    group_by(year_month) %>%
    mutate(tot_24 = sum(w24), tot_mw = sum(wmo)) %>%
    ungroup() %>%
    mutate(R_24 = safe_divide(num_24, w24, 0),
           R_mw = safe_divide(num_mw, wmo, 0),
           s_24 = safe_divide(w24, tot_24, 0),
           s_mw = safe_divide(wmo, tot_mw, 0),
           between = 100 * 0.5 * (R_24 + R_mw) * (s_24 - s_mw),
           within  = 100 * 0.5 * (s_24 + s_mw) * (R_24 - R_mw),
           total   = between + within) %>%
    select(all_of(c("year_month", by)), between, within, total)
}

# --- Per-group attribution (ports compute_per_group_attribution) --------------
#' Group contribution to a (left - right) rate gap at a common weight, in pp.
#' With weights fixed the Shapley between term is zero; what remains is this
#' per-group dollar attribution: (sum_g l*w - sum_g r*w) / sum_total(w).
per_group_attribution <- function(df, left, right, weight, by, out) {
  df %>%
    group_by(across(all_of(c("year_month", by)))) %>%
    summarise(num_l = sum(.data[[left]]  * .data[[weight]], na.rm = TRUE),
              num_r = sum(.data[[right]] * .data[[weight]], na.rm = TRUE),
              den   = sum(.data[[weight]], na.rm = TRUE), .groups = "drop") %>%
    group_by(year_month) %>%
    mutate(total_den = sum(den)) %>%
    ungroup() %>%
    mutate(!!out := 100 * (num_l - num_r) / total_den) %>%
    select(all_of(c("year_month", by, out)))
}

# --- Tracker vintage (port of tariff-etr-adj vintage stamping) ----------------
#' Resolve the tracker rate vintage powering data/raw. Resolution order:
#'   1. data/raw/statutory_rates_meta.csv sidecar (written by the pull)
#'   2. manifest.json in tracker_data_dir from config/local_paths.yaml
#'   3. "unknown"
tracker_vintage <- function() {
  meta <- file.path(DIR_RAW, "statutory_rates_meta.csv")
  if (file.exists(meta)) {
    v <- tryCatch(read_csv(meta, show_col_types = FALSE)$vintage[1],
                  error = function(e) NA_character_)
    if (!is.na(v) && nzchar(v)) return(v)
  }
  lp <- "config/local_paths.yaml"
  if (file.exists(lp) && requireNamespace("yaml", quietly = TRUE)) {
    td <- tryCatch(yaml::read_yaml(lp)$tracker_data_dir, error = function(e) NULL)
    if (!is.null(td)) {
      mf <- file.path(td, "manifest.json")
      if (file.exists(mf) && requireNamespace("jsonlite", quietly = TRUE)) {
        j <- tryCatch(jsonlite::read_json(mf), error = function(e) NULL)
        for (k in c("vintage", "published_at", "build_date", "date"))
          if (!is.null(j[[k]])) return(as.character(j[[k]]))
        # fall back to the manifest file's own mtime
        return(format(file.info(mf)$mtime, "%Y-%m-%d-%H"))
      }
    }
  }
  "unknown"
}

#' Append/refresh one step's row in results/tables/run_meta.csv: when each
#' step last ran, against which tracker vintage and analysis window.
write_run_meta <- function(step, notes = "") {
  meta_path <- file.path(DIR_TABLES, "run_meta.csv")
  row <- tibble(step = step,
                run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                tracker_vintage = tracker_vintage(),
                window_lo = ANALYSIS_LO, window_hi = ANALYSIS_HI,
                notes = notes)
  old <- if (file.exists(meta_path))
    read_csv(meta_path, col_types = cols(.default = col_character())) %>%
      filter(step != .env$step)
  else NULL
  write_csv(bind_rows(old, row) %>% arrange(step), meta_path)
}

# --- Figure export (titled + clean pairs; ports the export_fig convention) ----
#' Save <stub>_titled.png (title+subtitle, paper draft) and <stub>.png
#' (no titles, slides default). ~2400 px wide at dpi 240.
save_fig <- function(p, stub, title = NULL, subtitle = NULL,
                     width = 10, height = 6) {
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("ggplot2 required for save_fig")
  ggplot2::ggsave(file.path(DIR_FIGURES, paste0(stub, "_titled.png")),
                  p + ggplot2::labs(title = title, subtitle = subtitle),
                  width = width, height = height, dpi = 240)
  ggplot2::ggsave(file.path(DIR_FIGURES, paste0(stub, ".png")),
                  p + ggplot2::labs(title = NULL, subtitle = NULL),
                  width = width, height = height, dpi = 240)
  msg("    fig: %s[.png|_titled.png]", stub)
}

# Shared minimal theme for pipeline figures.
theme_etr <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(legend.position = "bottom",
                   panel.grid.minor = ggplot2::element_blank())
}
