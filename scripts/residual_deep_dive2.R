# Follow-up drills for the residual deep dive (see residual_deep_dive.R)
suppressPackageStartupMessages(library(data.table))
setwd("/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval")
p <- as.data.table(readRDS("data/processed/panel.rds"))
p[, res_usd := rate_all_pref * con_val_mo - cal_dut_mo]
nm <- unique(fread("data/raw/daily_by_country.csv",
                   select = c("country", "country_name")))[
  , .(cty_code = sprintf("%04d", country), country_name)]

show <- function(dt, n = 30) print(dt[1:min(n, .N)], digits = 3)

cat("== 1. PHARMA ch30: monthly stat vs census, total + top countries ==\n")
ph <- p[hs2 == "30", .(res_busd = sum(res_usd)/1e9,
        stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
        cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)), by = year_month][order(year_month)]
show(ph, 15)
cat("\n-- ch30 LATE top countries, max statutory rate seen --\n")
ph2 <- p[hs2 == "30" & year_month >= "2025-09",
         .(res_busd = sum(res_usd)/1e9, val_busd = sum(con_val_mo)/1e9,
           stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
           cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo),
           max_rate = 100*max(rate_all_pref)), by = cty_code]
ph2 <- merge(ph2, nm, by = "cty_code", all.x = TRUE)[order(-res_busd)]
show(ph2[, .(country_name, res_busd, val_busd, stat, cens, max_rate)], 12)

cat("\n== 2. CANADA/MEXICO ENERGY: 2711/2716/2709 monthly ==\n")
en <- p[hs10 %chin% c("2711210000","2716000000","2709001000","2709002000") &
        partner_group %in% c("Canada","Mexico"),
        .(res_musd = sum(res_usd)/1e6,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = .(hs10, partner_group, year_month)][order(hs10, partner_group, year_month)]
show(en[year_month >= "2025-11"], 30)

cat("\n== 3. STEEL/ALU SCRAP + ch72/73/76 structure ==\n")
sc <- p[hs2 %chin% c("72","73","76") & year_month >= "2025-09",
        .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = .(hs4 = substr(hs10,1,4))][order(-res_musd)]
show(sc, 15)
cat("\n-- scrap headings 7204/7602 by country (LATE) --\n")
sc2 <- p[substr(hs10,1,4) %chin% c("7204","7602") & year_month >= "2025-09",
         .(res_musd = sum(res_usd)/1e6, val_musd = sum(con_val_mo)/1e6,
           stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
           cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)), by = cty_code]
sc2 <- merge(sc2, nm, by = "cty_code", all.x = TRUE)[order(-res_musd)]
show(sc2[, .(country_name, res_musd, val_musd, stat, cens)], 8)

cat("\n== 4. AUTOS 8703 negative cells: monthly trace ==\n")
au <- p[substr(hs10,1,4) == "8703" &
        partner_group %in% c("Mexico","Canada","S. Korea","Japan"),
        .(res_musd = sum(res_usd)/1e6,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = .(partner_group, year_month)][order(partner_group, year_month)]
show(au[year_month >= "2025-08"], 35)

cat("\n== 5. CH98 LATE: top HS10 x country ==\n")
c98 <- p[hs2 == "98" & year_month >= "2025-09",
         .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
           stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
           cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
         by = .(hs10, cty_code)]
c98 <- merge(c98, nm, by = "cty_code", all.x = TRUE)[order(-res_musd)]
show(c98[, .(hs10, country_name, res_musd, val_busd, stat, cens)], 12)

cat("\n== 6. AUSTRALIA BEEF 0202: monthly ==\n")
bf <- p[substr(hs10,1,4) %chin% c("0201","0202") & cty_code == "6021",
        .(res_musd = sum(res_usd)/1e6,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = year_month][order(year_month)]
show(bf, 15)

cat("\n== 7. CH90 medical devices (9021/9018/9019) EU+CH LATE ==\n")
md <- p[substr(hs10,1,4) %chin% c("9018","9019","9021","9022") & year_month >= "2025-09",
        .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = .(hs4 = substr(hs10,1,4), cty_code)]
md <- merge(md, nm, by = "cty_code", all.x = TRUE)[order(-res_musd)]
show(md[, .(hs4, country_name, res_musd, val_busd, stat, cens)], 12)

cat("\n== 8. VMR overlap: how much LATE residual sits in B2-suspect flows ==\n")
vmr <- fread("results/tables/vmr_flow_classified.csv",
             select = c("hs10","cty_code","bucket","suspect"))
LATE <- p[year_month >= "2025-09"]
lt <- merge(LATE, unique(vmr, by = c("hs10","cty_code")),
            by = c("hs10","cty_code"), all.x = TRUE)
ov <- lt[, .(res_busd = sum(res_usd)/1e9), by = .(bucket = fifelse(is.na(bucket), "(no event)", bucket))][order(-res_busd)]
show(ov, 10)

cat("\n== 9. Ireland/Singapore/Costa Rica non-pharma residual (LATE) ==\n")
ir <- p[cty_code %chin% c("4190","5590","2230") & hs2 != "30" & year_month >= "2025-09",
        .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = .(cty_code, hs2)]
ir <- merge(ir, nm, by = "cty_code", all.x = TRUE)[order(-res_musd)]
show(ir[, .(country_name, hs2, res_musd, val_busd, stat, cens)], 12)
