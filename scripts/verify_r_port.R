# =============================================================================
# verify_r_port.R — compare the R pipeline against the Stata golden reference
# =============================================================================
# Usage:
#   1. Run the Stata pipeline (archive/stata/, via slurm/run_stata.sbatch in
#      the pre-archive tree) -- it writes results/tables/*.csv.
#   2. Snapshot those outputs:  cp -a results results_stata_golden
#   3. Run the R pipeline (00_run_all.R) -- it overwrites results/tables/.
#   4. Rscript scripts/verify_r_port.R
#
# Compares the shared tables on their common numeric columns after key
# harmonization (Stata exports ym as "2025m1"; R uses "2025-01"). Reports the
# max absolute difference per table and flags anything above TOL.
# =============================================================================

here::i_am("scripts/verify_r_port.R")
setwd(here::here())
source("code/utils.R")

GOLDEN <- "results_stata_golden/tables"
TOL    <- 1e-6   # pp; tier math is identical so agreement should be exact-ish

if (!dir.exists(GOLDEN))
  stop("No golden snapshot at ", GOLDEN,
       " -- copy the Stata results/ there before running the R pipeline.")

norm_keys <- function(df) {
  if ("ym" %in% names(df) && !"year_month" %in% names(df))
    df <- df %>% mutate(year_month = stata_ym(ym), ym = NULL)
  df
}

compare_table <- function(file, keys) {
  gp <- file.path(GOLDEN, file); rp <- file.path(DIR_TABLES, file)
  if (!file.exists(gp)) { msg("  %-35s SKIP (no golden)", file); return(NA) }
  if (!file.exists(rp)) { msg("  %-35s MISSING in R output", file); return(Inf) }
  g <- norm_keys(read_csv(gp, show_col_types = FALSE))
  r <- norm_keys(read_csv(rp, show_col_types = FALSE))
  num_cols <- intersect(names(g)[sapply(g, is.numeric)],
                        names(r)[sapply(r, is.numeric)])
  num_cols <- setdiff(num_cols, keys)
  j <- inner_join(g %>% select(all_of(c(keys, num_cols))),
                  r %>% select(all_of(c(keys, num_cols))),
                  by = keys, suffix = c("_stata", "_r"))
  if (nrow(j) == 0) { msg("  %-35s NO KEY OVERLAP", file); return(Inf) }
  diffs <- sapply(num_cols, function(cn)
    max(abs(j[[paste0(cn, "_stata")]] - j[[paste0(cn, "_r")]]), na.rm = TRUE))
  worst <- max(diffs, na.rm = TRUE)
  status <- ifelse(worst <= TOL, "OK", "DIFFERS")
  msg("  %-35s %s  (rows matched: %d/%d, max |diff| = %.2e in %s)",
      file, status, nrow(j), nrow(g), worst, names(which.max(diffs)))
  worst
}

msg("Comparing R pipeline output to Stata golden (%s)...", GOLDEN)
results <- c(
  compare_table("counterfactual_ladder.csv",      "year_month"),
  compare_table("counterfactual_by_country.csv",  c("year_month", "partner_group")),
  compare_table("counterfactual_by_country_avg.csv", "partner_group"),
  compare_table("decomp_monthly.csv",             "year_month"),
  compare_table("diversion_by_country_avg.csv",   "partner_group"),
  compare_table("diversion_by_product_avg.csv",   "product_group"),
  compare_table("attribution_by_country.csv",     c("year_month", "partner_group")),
  compare_table("attribution_by_product.csv",     c("year_month", "product_group")),
  compare_table("baseline_etr.csv",               "year_month"))

worst <- suppressWarnings(max(results, na.rm = TRUE))
if (is.finite(worst) && worst <= TOL) {
  msg("\nPORT VERIFIED: all compared tables agree within %.0e pp.", TOL)
} else {
  msg("\nDIFFERENCES FOUND (worst %.3e). Investigate before retiring the golden.",
      worst)
  quit(status = 1)
}
