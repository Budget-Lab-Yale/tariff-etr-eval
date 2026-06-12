# Final drills for the residual deep dive
suppressPackageStartupMessages(library(data.table))
setwd("/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval")
p <- as.data.table(readRDS("data/processed/panel.rds"))
p[, res_usd := rate_all_pref * con_val_mo - cal_dut_mo]
nm <- unique(fread("data/raw/daily_by_country.csv",
                   select = c("country", "country_name")))[
  , .(cty_code = sprintf("%04d", country), country_name)]
LATE <- p[year_month >= "2025-09"]

cat("== 8. VMR overlap with LATE residual ==\n")
vmr <- fread("results/tables/vmr_flow_classified.csv",
             select = c("hs10","cty_code","bucket","suspect"),
             colClasses = list(character = c("hs10","cty_code")))
lt <- merge(LATE, unique(vmr, by = c("hs10","cty_code")),
            by = c("hs10","cty_code"), all.x = TRUE)
print(lt[, .(res_busd = round(sum(res_usd)/1e9, 2)),
         by = .(bucket = fifelse(is.na(bucket), "(no event)", bucket))][order(-res_busd)])

cat("\n== 9. ROW 'Other Manufactured' composition (LATE, by hs2 x top country) ==\n")
om <- LATE[partner_group == "ROW" & product_group == "Other Manufactured",
           .(res_musd = sum(res_usd)/1e6,
             stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
             cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
           by = .(hs2, cty_code)]
om <- merge(om, nm, by = "cty_code", all.x = TRUE)[order(-res_musd)]
print(om[1:15, .(hs2, country_name, res_musd = round(res_musd,0),
                 stat = round(stat,1), cens = round(cens,1))])

cat("\n== 10. Nov-14 food exemption retroactivity: coffee/cocoa/bananas/beef ==\n")
fd <- p[substr(hs10,1,4) %chin% c("0901","1801","0803","0201","0202") &
        year_month >= "2025-10",
        .(res_musd = sum(res_usd)/1e6,
          stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
          cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
        by = .(hs4 = substr(hs10,1,4), year_month)][order(hs4, year_month)]
print(fd, digits = 3, nrows = 40)

cat("\n== 11. 2026Q1 monthly run-rate by candidate pattern ==\n")
q1 <- p[year_month >= "2026-01"]
n_q1 <- uniqueN(q1$year_month)
pat <- function(d, lab) data.table(pattern = lab,
  run_musd_mo = round(sum(d$res_usd)/1e6/n_q1, 0),
  stat = round(100*sum(d$rate_all_pref*d$con_val_mo)/sum(d$con_val_mo), 1),
  cens = round(100*sum(as.numeric(d$cal_dut_mo))/sum(d$con_val_mo), 1))
rb <- rbind(
  pat(q1[hs2 == "30"], "Pharma ch30"),
  pat(q1[substr(hs10,1,4) %chin% c("9018","9019","9021","9022")], "Medical devices 9018-9022"),
  pat(q1[substr(hs10,1,4) %chin% c("7201","7202","7204","7602")], "Steel/alu upstream+scrap"),
  pat(q1[hs10 %chin% c("2711210000","2716000000") & partner_group=="Canada"], "Canada gas+electricity"),
  pat(q1[hs10 %chin% c("2709001000","2709002000") & partner_group=="Mexico"], "Mexico crude"),
  pat(q1[hs2 == "98"], "Chapter 98"),
  pat(q1[substr(hs10,1,4)=="8703" & partner_group=="S. Korea"], "Korea autos 8703 (neg)"),
  pat(q1[substr(hs10,1,4)=="8703" & partner_group=="Japan"], "Japan autos 8703"),
  pat(q1[hs2 %chin% c("84","85") & partner_group=="China"], "China 84/85 stacking"),
  pat(q1[hs2 == "71"], "Precious metals ch71"))
print(rb)

cat("\n== 12. medical devices: is 9817 Nairobi visible? ch98 9817 lines ==\n")
n98 <- p[substr(hs10,1,4) == "9817" & year_month >= "2025-09",
         .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
           stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
           cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
         by = .(hs10)][order(-res_musd)]
print(n98[1:8], digits = 3)

cat("\n== 13. Singapore: what drives it (hs4, LATE) ==\n")
sg <- LATE[cty_code == "5590",
           .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
             stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
             cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
           by = .(hs4 = substr(hs10,1,4))][order(-res_musd)]
print(sg[1:10], digits = 3)

cat("\n== 14. India non-pharma: top hs4 (LATE) ==\n")
ind <- LATE[cty_code == "5330" & hs2 != "30",
            .(res_musd = sum(res_usd)/1e6, val_busd = sum(con_val_mo)/1e9,
              stat = 100*sum(rate_all_pref*con_val_mo)/sum(con_val_mo),
              cens = 100*sum(as.numeric(cal_dut_mo))/sum(con_val_mo)),
            by = .(hs4 = substr(hs10,1,4))][order(-res_musd)]
print(ind[1:10], digits = 3)
