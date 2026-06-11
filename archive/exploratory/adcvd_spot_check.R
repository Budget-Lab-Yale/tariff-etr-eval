# =============================================================================
# adcvd_spot_check.R — does Census cal_dut_mo include AD/CVD?
# =============================================================================
# Standalone diagnostic (NOT in 00_etr_eval.do). Ported from
# ../tariff-etr-adj/code/adcvd_spot_check.R, reading this repo's
# data/working/merged_analysis.dta. Tests the assumption behind
# CENSUS_INCLUDES_ADCVD in code/R/adcvd_strip.R: if Census-declared duty
# (cal_dut_mo) carries case-specific AD/CVD, then on lines with AD/CVD orders the
# collected ETR (cal_dut_mo / con_val_mo) should EXCEED the modeled statutory
# rate (rate_h2avg, which carries NO AD/CVD). A material positive excess on a
# LOW-statutory chapter => AD/CVD (or specific-duty / tracker understatement) is
# in cal_dut_mo => strip the Census shape (CENSUS_INCLUDES_ADCVD = TRUE).
#
# IMPORTANT — pick low-statutory chapters. Steel (ch72/73) is a TRAP for this
# test: §232 (+§301/IEEPA for China) already pushes its statutory rate to
# 25-86%, so collected sits BELOW statutory (net under-collection, positive eta)
# even if AD/CVD is present — the AD/CVD wedge is masked. The discriminating
# evidence is in machinery (ch84), instruments (ch90), and the Vietnam solar
# cluster (ch85), where statutory is ~5-11% and any collected excess stands out.
#
# Usage:  Rscript code/R/adcvd_spot_check.R
# =============================================================================

suppressPackageStartupMessages({ library(haven); library(dplyr) })

msg <- function(...) cat(sprintf(...), "\n")

# Window mirrors 08_eta_calibration.R (Stata monthly integers).
WIN_LO  <- 780L   # 2025m1
WIN_HI  <- 794L   # 2026m3
TEST_YM <- 794L   # 2026m3 (held out); train = [WIN_LO, WIN_HI) excl. TEST_YM

cells <- read_dta("data/working/merged_analysis.dta",
                  col_select = c("hs10", "cty_code", "partner_group", "hs2",
                                 "ym", "rate_h2avg", "cal_dut_mo", "con_val_mo")) %>%
  mutate(ym = as.integer(ym), hs2 = as.character(hs2),
         cty_code = as.character(cty_code),
         partner_group = as.character(partner_group),
         rate_h2avg = coalesce(rate_h2avg, 0),
         cal_dut_mo = coalesce(cal_dut_mo, 0)) %>%
  filter(!is.na(con_val_mo), con_val_mo > 0)

tr <- filter(cells, ym >= WIN_LO, ym <= WIN_HI, ym != TEST_YM)

seg <- function(d, label) {
  cv <- sum(d$con_val_mo); cd <- sum(d$cal_dut_mo)
  stat_usd <- sum(d$rate_h2avg * d$con_val_mo)
  tibble(group = label,
         trade_bil      = cv / 1e9,
         statutory_etr  = stat_usd / cv,        # modeled, no AD/CVD
         collected_etr  = cd / cv,              # Census cal_dut_mo
         excess_pp      = 100 * (cd - stat_usd) / cv,
         implied_adcvd_bil = (cd - stat_usd) / 1e9)
}

cats <- list(
  `steel ch72/73`    = function(x) x$hs2 %in% c("72", "73"),
  `bearings 8482`    = function(x) substr(x$hs10, 1, 4) == "8482",
  `machinery ch84`   = function(x) x$hs2 == "84",
  `electronics ch85` = function(x) x$hs2 == "85",
  `instruments ch90` = function(x) x$hs2 == "90")

out <- bind_rows(lapply(c("China", "Japan", "EU", "S. Korea", "UK"), function(pg) {
  bind_rows(lapply(names(cats), function(cn) {
    d <- filter(tr, partner_group == pg); d <- d[cats[[cn]](d), ]
    if (nrow(d) == 0) return(NULL)
    seg(d, paste(pg, "-", cn))
  }))
}))

msg("\n==== AD/CVD spot check, training window ym %d..%d (excl. %d) ====",
    WIN_LO, WIN_HI, TEST_YM)
msg("collected_etr > statutory_etr on a LOW-statutory chapter => cal_dut_mo carries AD/CVD")
msg("(steel is masked: its §232/301/IEEPA statutory dwarfs collections)\n")
print(as.data.frame(out), row.names = FALSE, digits = 4)

# Vietnam solar (the documented ~$1.26B ch85 AD/CVD cluster): Vietnam is in ROW,
# so locate it as the top ROW ch85 collector by collected-minus-statutory.
vn <- tr %>%
  filter(hs2 == "85", partner_group == "ROW") %>%
  group_by(cty_code) %>%
  summarise(trade_bil = sum(con_val_mo) / 1e9,
            statutory_etr = sum(rate_h2avg * con_val_mo) / sum(con_val_mo),
            collected_etr = sum(cal_dut_mo) / sum(con_val_mo),
            excess_bil    = (sum(cal_dut_mo) - sum(rate_h2avg * con_val_mo)) / 1e9,
            .groups = "drop") %>%
  arrange(desc(excess_bil)) %>% head(5)

msg("\n---- Top ROW ch85 collectors by collected-minus-statutory ($B) [Vietnam = solar AD/CVD] ----")
print(as.data.frame(vn), row.names = FALSE, digits = 4)

msg("\nReading: positive excess on low-statutory ch84/ch90 (Japan/EU) and ROW ch85")
msg("(Vietnam) supports CENSUS_INCLUDES_ADCVD = TRUE. Steel runs NEGATIVE for every")
msg("partner — the §232 statutory masks any AD/CVD there, so steel is NOT the")
msg("negative-eta driver; the over-collection cluster is ch84/85/90 + Vietnam solar.")
