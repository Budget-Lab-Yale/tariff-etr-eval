# =============================================================================
# strips/adcvd_strip.R — AD/CVD share of the S4 -> T timing gap
# =============================================================================
# Ported from tariff-etr-adj (code/adcvd_strip.R), adapted to this repo's job:
# there the AD/CVD dollars are STRIPPED from Treasury before calibrating eta;
# here they are MEASURED so the ladder's gap_timing (S4 - T) can be decomposed
# into known collection-channel components and a true residual.
#
# Why AD/CVD sits in this gap: the tracker statutory rates carry no
# antidumping/countervailing duty, and Census cal_dut_mo structurally EXCLUDES
# Type-03 AD/CVD deposits (settled empirically in tariff-etr-adj, 2026-06-10:
# Canada softwood lumber HTS 4407 collected $0 in Census against 8-14.5%
# deposits in force; see that repo's adcvd_spot_check.R). The deposits reach
# Treasury customs_duties only, so they appear as S4 < |T| pressure inside
# gap_timing = S4 - T.
#
# Input: resources/adcvd_collected.csv — interim curated level (FY19 Appendix A
# partner shares x $2.0B/yr, prorated to a 10-month window by its builder;
# provenance in the file header; upgrade path = case-level Appendix A from CBP
# Office of Trade). We use only the implied monthly run-rate; the partner
# split becomes relevant if/when a by-country T exists.
#
# In-memory only: never edits data/ or the panel. Sourced by 02a_ladder.R.
# =============================================================================

ADCVD_STRIP_ENABLED <- TRUE
# Months the curated total was prorated over (file header: Jun-2025..Mar-2026).
ADCVD_INPUT_MONTHS  <- 10

#' Monthly AD/CVD deposits reaching Treasury, in dollars.
#' @return scalar $/month (NA if disabled or input file absent)
adcvd_monthly_usd <- function() {
  if (!ADCVD_STRIP_ENABLED) return(NA_real_)
  path <- "resources/adcvd_collected.csv"
  if (!file.exists(path)) {
    msg("    AD/CVD strip: %s absent -- component not measured.", path)
    return(NA_real_)
  }
  cur <- readr::read_csv(path, comment = "#", show_col_types = FALSE)
  total <- sum(cur$adcvd_usd, na.rm = TRUE)
  out <- total / ADCVD_INPUT_MONTHS
  msg("    AD/CVD component: $%.0fM/mo (curated $%.2fB over %d months)",
      out / 1e6, total / 1e9, ADCVD_INPUT_MONTHS)
  out
}
