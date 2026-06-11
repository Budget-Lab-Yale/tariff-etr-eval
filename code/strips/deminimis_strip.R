# =============================================================================
# strips/deminimis_strip.R — de-minimis postal-channel share of S4 -> T
# =============================================================================
# Ported from tariff-etr-adj (code/deminimis_strip.R), adapted: there the
# carrier-remitted postal duty is stripped from Treasury before calibrating
# eta; here it is ESTIMATED so 02a can decompose the ladder's
# gap_timing = S4 - T into channel components.
#
# The channel: when duty-free de-minimis treatment ended (China/HK 2025-05-02,
# globally 2025-08-29 under EO 14324), small-parcel POSTAL shipments started
# paying duty by monthly carrier remittance. CBP prepares no entry summaries
# for them, so the dollars reach Treasury customs_duties with no Census
# cal_dut_mo counterpart — the same collection-channel class as AD/CVD.
#
# Estimator (unchanged from adj): the step in the monthly (Treasury - Census)
# duty gap, mean over months >= DEMINIMIS_ONSET minus mean over the post-ramp
# pre-break baseline [DEMINIMIS_PRE_LO, DEMINIMIS_ONSET). Differencing removes
# what is common to both segments (AD/CVD structural gap, average payment
# timing). Known coarseness: monthly ratios are timing-noisy; the channel is
# growing so a flat step lags it. adj excludes its held-out test month from
# the estimate; this repo has no held-out month, so all window months enter.
#
# In-memory only: never edits data/ or the panel. Sourced by 02a_ladder.R.
# =============================================================================

DEMINIMIS_STRIP_ENABLED <- TRUE
DEMINIMIS_ONSET  <- "2025-09"   # first full month of the global postal channel
DEMINIMIS_PRE_LO <- "2025-06"   # post-IEEPA-ramp baseline starts here

#' Estimate the carrier-remitted de-minimis duty step, $/month.
#'
#' @param census_duty tibble(year_month, cen_duty): Census cal_dut_mo sums ($).
#' @param treasury    tibble(year_month, customs_duties): Treasury, $M.
#' @return list(step_usd, pre_gap, post_gap, n_pre, n_post); step_usd NA if
#'   either segment has < 2 usable months.
estimate_deminimis_step <- function(census_duty, treasury) {
  gaps <- treasury %>%
    inner_join(census_duty, by = "year_month") %>%
    mutate(gap = customs_duties * 1e6 - cen_duty)
  pre  <- gaps %>% filter(year_month >= DEMINIMIS_PRE_LO,
                          year_month <  DEMINIMIS_ONSET)
  post <- gaps %>% filter(year_month >= DEMINIMIS_ONSET)
  if (nrow(pre) < 2 || nrow(post) < 2)
    return(list(step_usd = NA_real_, pre_gap = NA_real_, post_gap = NA_real_,
                n_pre = nrow(pre), n_post = nrow(post)))
  list(step_usd = mean(post$gap) - mean(pre$gap),
       pre_gap  = mean(pre$gap), post_gap = mean(post$gap),
       n_pre = nrow(pre), n_post = nrow(post))
}

#' De-minimis postal-channel duty by month, $: the estimated step for months
#' >= onset, 0 before. Returns all-zero (with a message) when not estimable.
deminimis_monthly_usd <- function(census_duty, treasury) {
  zero <- tibble(year_month = treasury$year_month, deminimis_usd = 0)
  if (!DEMINIMIS_STRIP_ENABLED) {
    msg("    De-minimis strip: DISABLED -- component zeroed.")
    return(zero)
  }
  est <- estimate_deminimis_step(census_duty, treasury)
  if (!is.finite(est$step_usd) || est$step_usd <= 0) {
    msg("    De-minimis component: not estimable (step=%s, %d pre / %d post) -- zeroed.",
        format(est$step_usd), est$n_pre, est$n_post)
    return(zero)
  }
  msg("    De-minimis component: $%.3fB/mo for months >= %s", est$step_usd / 1e9,
      DEMINIMIS_ONSET)
  msg("      (gap step: $%.3fB/mo pre [%d mo] -> $%.3fB/mo post [%d mo])",
      est$pre_gap / 1e9, est$n_pre, est$post_gap / 1e9, est$n_post)
  zero %>%
    mutate(deminimis_usd = ifelse(year_month >= DEMINIMIS_ONSET,
                                  est$step_usd, 0))
}
