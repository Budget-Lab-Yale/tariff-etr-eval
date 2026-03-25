# ==============================================================================
# utils.R -- Shared utilities for tariff-etr-eval
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(lubridate)
library(ggplot2)
library(scales)
library(here)

# --- Safe arithmetic ---
safe_divide <- function(numerator, denominator, default = NA_real_) {
  ifelse(is.na(denominator) | denominator == 0, default, numerator / denominator)
}

# --- Sibling repo paths ---
# Resolve paths to sister repos relative to this project
resolve_sibling <- function(repo_name) {
  file.path(dirname(here()), repo_name)
}

TRACKER_DIR  <- resolve_sibling("tariff-rate-tracker")
IMPACTS_DIR  <- resolve_sibling("tariff-impact-tracker")

# --- ggplot theme (consistent with tariff-impact-tracker) ---
theme_etr <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray40"),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
}

# Colors
tbl_gray <- "#6C757D"
color_actual   <- "#C8102E"  # Red for actual
color_statutory <- "#0055A4" # Navy for statutory
color_gap      <- "#28A745"  # Green for gap

AUTHORITY_COLORS <- c(
  "Section 232"       = "#0055A4",
  "Section 301"       = "#C8102E",
  "IEEPA Reciprocal"  = "#28A745",
  "IEEPA Fentanyl"    = "#FFC107",
  "Section 122"       = "#6C757D"
)

PARTNER_COLORS <- c(
  "China"   = "#C8102E",
  "Canada"  = "#0055A4",
  "Mexico"  = "#28A745",
  "EU"      = "#FFC107",
  "Japan"   = "#9B59B6",
  "S. Korea" = "#E67E22",
  "UK"      = "#1ABC9C",
  "ROW"     = "#95A5A6"
)

# --- Load statutory rates (from tariff-rate-tracker RDS) ---
load_timeseries <- function() {
  rds_path <- file.path(TRACKER_DIR, "data", "timeseries", "rate_timeseries.rds")
  if (!file.exists(rds_path)) {
    stop("rate_timeseries.rds not found at: ", rds_path,
         "\nRun the tariff-rate-tracker pipeline first.")
  }
  readRDS(rds_path)
}

# --- Load import weights (from tariff-rate-tracker) ---
load_import_weights <- function() {
  # Try the processed RDS first, fall back to CSV
  rds_path <- file.path(TRACKER_DIR, "data", "imports", "census_imports_2024.rds")
  csv_path <- file.path(TRACKER_DIR, "data", "imports", "census_imports_2024.csv")
  if (file.exists(rds_path)) {
    return(readRDS(rds_path))
  } else if (file.exists(csv_path)) {
    return(read_csv(csv_path, show_col_types = FALSE))
  }
  warning("Import weights not found. Country/product decomposition will be unavailable.")
  NULL
}

# --- Load actual tariff revenue (from tariff-impact-tracker CSV) ---
load_actual_etr <- function() {
  csv_path <- file.path(IMPACTS_DIR, "output", "tariff_revenue.csv")
  if (!file.exists(csv_path)) {
    stop("tariff_revenue.csv not found at: ", csv_path,
         "\nRun the tariff-impact-tracker pipeline first.")
  }
  read_csv(csv_path, show_col_types = FALSE) %>%
    mutate(date = as.Date(date))
}

# --- Load daily statutory ETR (from tariff-rate-tracker) ---
load_daily_etr <- function() {
  csv_path <- file.path(TRACKER_DIR, "output", "daily", "daily_overall.csv")
  if (!file.exists(csv_path)) {
    stop("daily_overall.csv not found at: ", csv_path)
  }
  read_csv(csv_path, show_col_types = FALSE) %>%
    mutate(date = as.Date(date))
}

# --- Load daily ETR by authority ---
load_daily_authority <- function() {
  csv_path <- file.path(TRACKER_DIR, "output", "daily", "daily_by_authority.csv")
  if (!file.exists(csv_path)) return(NULL)
  read_csv(csv_path, show_col_types = FALSE) %>%
    mutate(date = as.Date(date))
}

# --- Load revision dates ---
load_revision_dates <- function() {
  csv_path <- file.path(TRACKER_DIR, "config", "revision_dates.csv")
  if (!file.exists(csv_path)) return(NULL)
  read_csv(csv_path, show_col_types = FALSE) %>%
    mutate(effective_date = as.Date(effective_date))
}

# --- Snapshot statutory ETR at first-of-month ---
#' Collapse the daily statutory ETR to monthly by taking the rate on the 1st
#' of each month. This preserves the step-function nature of tariff policy
#' (rates change only at revision boundaries, not gradually).
#'
#' Alternative approaches considered:
#'   - Monthly average: blurs timing of policy changes within a month
#'   - End-of-month: lags the signal; a tariff announced on the 2nd wouldn't
#'     show until next month's end
#'   - Trade-day weighted average: theoretically ideal but requires daily
#'     import flow data we don't have
#'
#' First-of-month is cleanest because:
#'   1. Most tariff revisions take effect on or near the 1st
#'   2. Aligns with how Census reports monthly import values
#'   3. Simple to interpret: "what was the tariff schedule at month start?"
collapse_statutory_monthly <- function(daily_etr) {
  daily_etr %>%
    filter(day(date) == 1) %>%
    select(date, revision, weighted_etr, weighted_etr_additional,
           matched_imports_b, total_imports_b)
}

# --- Get rates at date from timeseries (wrapper around tariff-rate-tracker logic) ---
get_rates_at_date <- function(ts, query_date) {
  query_date <- as.Date(query_date)
  ts %>%
    filter(valid_from <= query_date, valid_until >= query_date)
}

# --- Load Census HS2 x country x month data (from 01_pull_census_trade.R) ---
load_census_trade <- function() {
  csv_path <- here("data", "census_hs2_country_monthly.csv")
  if (!file.exists(csv_path)) {
    stop("Census trade data not found. Run R/01_pull_census_trade.R first.")
  }
  read_csv(csv_path, show_col_types = FALSE) %>%
    mutate(date = as.Date(date))
}

# --- Census country code to partner group mapping ---
assign_partner_group <- function(cty_code) {
  # EU27 census codes
  eu27 <- c("4280", "4220", "4230", "4240", "4253", "4254", "4270",
            "4350", "4360", "4380", "4390", "4550", "4560", "4570",
            "4590", "4610", "4690", "4700", "4720", "4740", "4810",
            "4760", "4770", "4780", "4840", "4850", "4870")
  case_when(
    cty_code == "5700" ~ "China",
    cty_code == "1220" ~ "Canada",
    cty_code == "2010" ~ "Mexico",
    cty_code == "5880" ~ "Japan",
    cty_code == "5800" ~ "S. Korea",
    cty_code == "4120" ~ "UK",
    cty_code %in% eu27 ~ "EU",
    TRUE ~ "ROW"
  )
}

# --- Policy period markers ---
POLICY_EVENTS <- tibble::tribble(
  ~date,              ~label,
  "2025-02-04",       "Fentanyl",
  "2025-03-12",       "232 Autos",
  "2025-04-02",       "Liberation Day",
  "2025-04-09",       "Phase 1 Pause",
  "2025-07-01",       "Phase 2",
  "2025-08-07",       "Phase 2 Recip.",
  "2026-02-24",       "SCOTUS / S.122"
) %>% mutate(date = as.Date(date))
