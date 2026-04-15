# Quick diagnostic: compare 3 stages of ETR computation
library(dplyr)
library(readr)
library(here)
library(yaml)

here::i_am("R/check_etrs.R")
source(here("R", "utils.R"))

cat("Loading timeseries...\n")
ts <- load_timeseries()
cat("  Rows:", nrow(ts), "\n")

cat("Loading census...\n")
census <- load_census_trade() %>% mutate(cty_code = as.character(cty_code))

cat("Loading HTS10 import weights...\n")
local_paths <- read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)
imports_hs10 <- readRDS(iw_path) %>%
  group_by(hs10, cty_code) %>%
  summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
  filter(imports > 0) %>%
  mutate(cty_code = as.character(cty_code))
cat("  Import weight flows:", nrow(imports_hs10), "\n")

# 2024 Census HS2 x country weights
weights_2024 <- census %>%
  filter(year == 2024) %>%
  group_by(hs2, cty_code) %>%
  summarize(imports_2024 = sum(con_val_mo, na.rm = TRUE), .groups = "drop")

available_months <- census %>%
  filter(year == 2025) %>%
  distinct(month) %>%
  arrange(month) %>%
  pull(month)

cat("\nMonth        (1) HTS10 2024w   (2) HS2xCty 2024w   (3) HS2xCty month w\n")
cat(paste(rep("-", 72), collapse = ""), "\n")

for (m in available_months) {
  query_date <- as.Date(sprintf("2025-%02d-01", m))
  label <- format(query_date, "%b %Y")

  # Filter snapshot FIRST (small), then join
  snapshot <- ts %>%
    filter(valid_from <= query_date, valid_until >= query_date) %>%
    select(hts10, country, total_rate)

  sw <- snapshot %>%
    inner_join(imports_hs10, by = c("hts10" = "hs10", "country" = "cty_code"))

  # (1) HTS10-level ETR with 2024 weights
  etr_hts10 <- weighted.mean(sw$total_rate, w = sw$imports, na.rm = TRUE)

  # Collapse to HS2 x country using HTS10 import weights
  hs2_cty <- sw %>%
    mutate(hs2 = substr(hts10, 1, 2)) %>%
    group_by(hs2, country) %>%
    summarize(
      mean_rate = weighted.mean(total_rate, w = imports, na.rm = TRUE),
      imports_hs10 = sum(imports),
      .groups = "drop"
    ) %>%
    rename(cty_code = country)

  # (2) HS2 x country ETR re-aggregated with summed HTS10 weights
  etr_hs2_hs10w <- weighted.mean(hs2_cty$mean_rate, w = hs2_cty$imports_hs10, na.rm = TRUE)

  # (3) HS2 x country ETR reweighted with actual monthly Census imports
  actual_imports <- census %>%
    filter(year == 2025, month == m) %>%
    select(hs2, cty_code, imports_actual = con_val_mo)

  merged <- hs2_cty %>%
    left_join(actual_imports, by = c("hs2", "cty_code")) %>%
    mutate(imports_actual = coalesce(imports_actual, 0))

  merged_pos <- merged %>% filter(imports_actual > 0)

  etr_monthly <- if (nrow(merged_pos) > 0) {
    weighted.mean(merged_pos$mean_rate, w = merged_pos$imports_actual, na.rm = TRUE)
  } else NA_real_

  cat(sprintf("%-10s   %14.2f%%   %17.2f%%   %18.2f%%\n",
              label, etr_hts10 * 100, etr_hs2_hs10w * 100, etr_monthly * 100))

  # Free memory
  rm(snapshot, sw, hs2_cty, actual_imports, merged, merged_pos)
  gc(verbose = FALSE)
}
