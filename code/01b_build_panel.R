# =============================================================================
# 01b_build_panel.R — build the master analysis panel from data/raw CSVs
# =============================================================================
# R port of the retired Stata step 1 (archive/stata/code/01_etr_clean.do),
# restricted to what the primary analysis consumes. Reads the Step-0 pull
# outputs and assembles one row per (hs10, cty_code, year_month) over the
# analysis window, carrying:
#
#   con_val_mo, cal_dut_mo, census_etr           Census IMDB trade + S4 input
#   con_qy1_mo, ship_wgt_mo                      physical anchors (VMR, 02c)
#   rate_h2avg                                   S1/S2 statutory panel (day-wtd)
#   rate_all_pref                                S3 panel (h2avg - pref delta)
#   rate_2024, rate_usmca_monthly                S0 / explainer panels (NA in
#                                                publish mode -- CSVs absent)
#   imports, w_2024, w_monthly                   2024 + monthly weights
#   partner_group, product_group, hs2            partitions
#
# Deliberately NOT ported from the Stata step (see docs/open_questions.md):
#   - the per-revision tracker_snapshots merge (`total_rate`, ~200M rows).
#     Only the 06 baseline diagnostic consumed it; rate_h2avg is the framework
#     rate panel and is day-weighted, which total_rate was not.
#   - census_hs2 API import (already retired in Stata).
#
# Output: data/processed/panel.rds (+ alongside it, panel_summary.csv with
# per-month totals for quick eyeballing/validation).
#
# Memory note: counterfactual_h2avg.csv is ~73M rows (full tracker universe x
# month); we fread only its 4 columns and inner-join to the Census universe
# immediately. Run via slurm/run_r.sbatch on a compute node; the login node
# is too small for the full build.
# =============================================================================

here::i_am("code/01b_build_panel.R")
setwd(here::here())
source("code/utils.R")
suppressPackageStartupMessages(library(data.table))

t0 <- Sys.time()
msg("[01b] Building analysis panel (%s .. %s)...", ANALYSIS_LO, ANALYSIS_HI)

# --- 1. Census IMDB HS10 x country x month -----------------------------------
msg("  [1] Census IMDB aggregate...")
cen <- fread(file.path(DIR_RAW, "imdb_hs10_country_monthly.csv"),
             colClasses = list(character = c("hs10", "cty_code", "year_month")),
             showProgress = FALSE, integer64 = "double")
cen <- cen[year_month >= ANALYSIS_LO & year_month <= ANALYSIS_HI]
msg("      %s rows in window", format(nrow(cen), big.mark = ","))

# --- 2. Statutory rate panels -------------------------------------------------
# S1/S2: day-weighted h2avg-USMCA panel. fread the 73M-row file with only the
# needed columns, then keep the Census universe (left join semantics: Census
# rows with no rate row get rate 0, matching the Stata merge + zero-fill).
msg("  [2] Rate panels...")
cf <- fread(file.path(DIR_RAW, "counterfactual_h2avg.csv"),
            select = c("hts10", "cty_code", "total_rate", "year_month"),
            colClasses = list(character = c("hts10", "cty_code", "year_month")),
            showProgress = FALSE, integer64 = "double")
setnames(cf, c("hts10", "total_rate"), c("hs10", "rate_h2avg"))
cf <- cf[year_month >= ANALYSIS_LO & year_month <= ANALYSIS_HI]
setkey(cf, hs10, cty_code, year_month)
setkey(cen, hs10, cty_code, year_month)
cen <- cf[cen]                                  # right join == left join onto cen
match_pct <- 100 * mean(!is.na(cen$rate_h2avg))
msg("      h2avg rate matched: %.1f%% of Census rows", match_pct)
if (match_pct < 95)
  warning("cf_h2avg match rate below 95% -- investigate upstream pull")
cen[is.na(rate_h2avg), rate_h2avg := 0]
rm(cf); invisible(gc(FALSE))

# S3: sparse non-USMCA preference delta; absent cells get delta 0.
pref <- fread(file.path(DIR_RAW, "counterfactual_other_pref_delta_monthly.csv"),
              colClasses = list(character = c("hs10", "cty_code", "year_month")),
              showProgress = FALSE, integer64 = "double")
setkey(pref, hs10, cty_code, year_month)
cen <- pref[cen]
cen[is.na(delta_base),  delta_base  := 0]
cen[is.na(delta_recip), delta_recip := 0]
cen[, rate_all_pref := pmax(0, rate_h2avg - delta_base - delta_recip)]
cen[, c("delta_base", "delta_recip") := NULL]

# S0 + USMCA-monthly explainer panels: only present in full (DataWeb) mode.
optional_panel <- function(dt, file, rate_name) {
  path <- file.path(DIR_RAW, file)
  if (!file.exists(path)) {
    msg("      %s absent (publish mode) -- %s = NA", file, rate_name)
    dt[, (rate_name) := NA_real_]
    return(dt)
  }
  p <- fread(path, colClasses = "character", showProgress = FALSE, integer64 = "double")
  if ("hts10" %in% names(p)) setnames(p, "hts10", "hs10")
  p[, total_rate := as.numeric(total_rate)]
  p <- p[year_month >= ANALYSIS_LO & year_month <= ANALYSIS_HI,
         .(hs10, cty_code, year_month, total_rate)]
  setnames(p, "total_rate", rate_name)
  setkey(p, hs10, cty_code, year_month)
  dt <- p[dt]
  dt[is.na(get(rate_name)), (rate_name) := 0]
  msg("      %s merged", file)
  dt
}
cen <- optional_panel(cen, "counterfactual_usmca2024.csv",    "rate_2024")
cen <- optional_panel(cen, "counterfactual_usmca_monthly.csv","rate_usmca_monthly")
HAVE_S0 <- !all(is.na(cen$rate_2024))

# --- 3. Weights ----------------------------------------------------------------
msg("  [3] Weights...")
w24 <- fread(file.path(DIR_RAW, "import_weights_2024.csv"),
             colClasses = list(character = c("hs10", "cty_code")),
             showProgress = FALSE, integer64 = "double")
w24[, w_2024 := imports / sum(imports)]
setkey(w24, hs10, cty_code)
setkey(cen, hs10, cty_code)
cen <- w24[cen]
cen[is.na(imports), imports := 0]
cen[is.na(w_2024),  w_2024  := 0]
cen[, w_monthly := con_val_mo / sum(con_val_mo), by = year_month]

# --- 4. Partitions + derived columns -------------------------------------------
msg("  [4] Partitions...")
cen[, hs2 := substr(hs10, 1, 2)]
cen[, partner_group := assign_partner_group(cty_code)]
pg <- fread("resources/product_groups.csv", colClasses = "character",
            showProgress = FALSE, integer64 = "double")
cen <- merge(cen, pg, by = "hs2", all.x = TRUE)
n_nopg <- cen[is.na(product_group), .N]
if (n_nopg > 0)
  stop(n_nopg, " rows have hs2 not in resources/product_groups.csv")
cen[, census_etr := fifelse(con_val_mo > 0, cal_dut_mo / con_val_mo, NA_real_)]

# --- 5. Integrity checks (ports Stata section F) --------------------------------
msg("  [5] Integrity checks...")
stopifnot(
  "duplicate (hs10, cty_code, year_month) keys" =
    !anyDuplicated(cen, by = c("hs10", "cty_code", "year_month")),
  "negative rate_h2avg"    = cen[rate_h2avg    < 0, .N] == 0,
  "negative rate_all_pref" = cen[rate_all_pref < 0, .N] == 0,
  "negative con_val_mo"    = cen[con_val_mo    < 0, .N] == 0,
  "negative cal_dut_mo"    = cen[cal_dut_mo    < 0, .N] == 0,
  "S3 rate exceeds S2 rate" =
    cen[rate_all_pref - rate_h2avg > 1e-9, .N] == 0)
n_badhs <- cen[!grepl("^[0-9]{10}$", hs10), .N]
if (n_badhs > 0) warning(n_badhs, " rows have malformed hs10 (not 10 digits)")
msg("      all checks passed (%s rows)", format(nrow(cen), big.mark = ","))

# --- 6. Save --------------------------------------------------------------------
panel <- as_tibble(cen) %>%
  select(year_month, hs2, product_group, hs10, cty_code, partner_group,
         con_val_mo, cal_dut_mo, census_etr, con_qy1_mo, ship_wgt_mo,
         rate_h2avg, rate_all_pref, rate_2024, rate_usmca_monthly,
         imports, w_2024, w_monthly) %>%
  arrange(year_month, hs10, cty_code)
attr(panel, "tracker_vintage") <- tracker_vintage()
attr(panel, "have_s0")         <- HAVE_S0
saveRDS(panel, file.path(DIR_PROCESSED, "panel.rds"))

panel %>%
  group_by(year_month) %>%
  summarise(n = n(),
            con_val_b = sum(con_val_mo) / 1e9,
            cal_dut_b = sum(cal_dut_mo) / 1e9,
            s2_pct = 100 * sum(rate_h2avg * con_val_mo) / sum(con_val_mo),
            s4_pct = 100 * sum(cal_dut_mo) / sum(con_val_mo)) %>%
  write_csv(file.path(DIR_PROCESSED, "panel_summary.csv"))

write_run_meta("01b_build_panel",
               notes = sprintf("have_s0=%s; rows=%d", HAVE_S0, nrow(panel)))
msg("[01b] panel.rds saved (%s rows; S0 %s) in %.1f min",
    format(nrow(panel), big.mark = ","),
    ifelse(HAVE_S0, "present", "absent (publish mode)"),
    as.numeric(difftime(Sys.time(), t0, units = "mins")))
