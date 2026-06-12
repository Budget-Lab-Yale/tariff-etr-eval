# =============================================================================
# residual_deep_dive.R — one-off diagnostic: where is the S3-S4 residual gap
# large and unexplained? (2026-06-12, against panel vintage 2026-06-11-17)
# Run: Rscript scripts/residual_deep_dive.R   (from repo root)
# Outputs: results/diagnostics/residual_*.csv + console summary
# =============================================================================
suppressPackageStartupMessages(library(data.table))
setwd("/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval")

p <- as.data.table(readRDS("data/processed/panel.rds"))
p[, res_usd := rate_all_pref * con_val_mo - cal_dut_mo]

cat("== sanity: monthly residual pp vs ladder ==\n")
m <- p[, .(res_usd = sum(res_usd), val = sum(con_val_mo)), by = year_month]
m[, res_pp := 100 * res_usd / val]
lad <- fread("results/tables/counterfactual_ladder.csv")
chk <- merge(m, lad[, .(year_month, gap_residual)], by = "year_month")
chk[, diff := res_pp - gap_residual]
print(chk[, .(year_month, res_pp = round(res_pp, 3),
              ladder = round(gap_residual, 3),
              res_busd = round(res_usd / 1e9, 2))], nrows = 20)

# Windows: SPIKE = Apr-May 2025 (documented); LATE = steady state after
LATE <- p[year_month >= "2025-09"]
n_mo <- uniqueN(LATE$year_month)
cat(sprintf("\n== LATE window: 2025-09 .. 2026-03 (%d months) ==\n", n_mo))
cat(sprintf("LATE residual total: $%.2fB on $%.0fB imports (%.2f pp)\n",
            sum(LATE$res_usd) / 1e9, sum(LATE$con_val_mo) / 1e9,
            100 * sum(LATE$res_usd) / sum(LATE$con_val_mo)))

# --- country detail (census code level, with names) --------------------------
nm <- unique(fread("data/raw/daily_by_country.csv",
                   select = c("country", "country_name")))[
  , .(cty_code = sprintf("%04d", country), country_name)]
by_cty <- LATE[, .(res_busd = sum(res_usd) / 1e9,
                   val_busd = sum(con_val_mo) / 1e9,
                   stat = 100 * sum(rate_all_pref * con_val_mo) / sum(con_val_mo),
                   cens = 100 * sum(cal_dut_mo) / sum(con_val_mo)),
               by = .(cty_code, partner_group)]
by_cty <- merge(by_cty, nm, by = "cty_code", all.x = TRUE)
setorder(by_cty, -res_busd)
cat("\n== LATE residual by country (top 20) ==\n")
print(by_cty[1:20, .(country_name, partner_group,
                     res_busd = round(res_busd, 2), val_busd = round(val_busd, 1),
                     stat = round(stat, 1), cens = round(cens, 1))])
fwrite(by_cty, "results/diagnostics/residual_late_by_country.csv")

# --- HS2 ----------------------------------------------------------------------
by_hs2 <- LATE[, .(res_busd = sum(res_usd) / 1e9,
                   val_busd = sum(con_val_mo) / 1e9,
                   stat = 100 * sum(rate_all_pref * con_val_mo) / sum(con_val_mo),
                   cens = 100 * sum(cal_dut_mo) / sum(con_val_mo)), by = hs2]
setorder(by_hs2, -res_busd)
cat("\n== LATE residual by HS2 (top 15) ==\n")
print(by_hs2[1:15, .(hs2, res_busd = round(res_busd, 2), val_busd = round(val_busd, 1),
                     stat = round(stat, 1), cens = round(cens, 1))])
fwrite(by_hs2, "results/diagnostics/residual_late_by_hs2.csv")

# --- partner x product grid (LATE) --------------------------------------------
grid <- LATE[, .(res_busd = sum(res_usd) / 1e9), by = .(partner_group, product_group)]
gw <- dcast(grid, product_group ~ partner_group, value.var = "res_busd")
cat("\n== LATE residual $B: product x partner ==\n")
print(gw[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 2) else x)])
fwrite(gw, "results/diagnostics/residual_late_product_x_partner.csv")

# --- HS10 x country cells: persistence + size ----------------------------------
cells <- LATE[, .(res_usd = sum(res_usd), val = sum(con_val_mo),
                  stat_usd = sum(rate_all_pref * con_val_mo),
                  cens_usd = sum(as.numeric(cal_dut_mo)),
                  mo_pos = sum(res_usd > 1e6), mo_n = .N),
              by = .(hs10, cty_code, partner_group, product_group)]
cells[, `:=`(stat = 100 * stat_usd / val, cens = 100 * cens_usd / val)]
cells <- merge(cells, nm, by = "cty_code", all.x = TRUE)
setorder(cells, -res_usd)
fwrite(cells[abs(res_usd) > 5e6],
       "results/diagnostics/residual_late_cells_over5m.csv")
cat("\n== LATE top 40 HS10 x country cells by residual $ ==\n")
print(cells[1:40, .(hs10, country_name, val_busd = round(val / 1e9, 2),
                    res_musd = round(res_usd / 1e6, 0),
                    stat = round(stat, 1), cens = round(cens, 1), mo_pos)])

cat("\n== LATE top 15 NEGATIVE cells (census > statutory; trackermiss dir) ==\n")
neg <- cells[order(res_usd)][1:15]
print(neg[, .(hs10, country_name, val_busd = round(val / 1e9, 2),
              res_musd = round(res_usd / 1e6, 0),
              stat = round(stat, 1), cens = round(cens, 1))])

# --- monthly trend by product group (is it growing?) ---------------------------
tr <- p[year_month >= "2025-06",
        .(res_busd = sum(res_usd) / 1e9), by = .(year_month, product_group)]
trw <- dcast(tr, year_month ~ product_group, value.var = "res_busd")
cat("\n== monthly residual $B by product group (2025-06+) ==\n")
print(trw[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 2) else x)])
fwrite(trw, "results/diagnostics/residual_monthly_by_product.csv")
