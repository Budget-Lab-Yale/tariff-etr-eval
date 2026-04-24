# Sanity-check the three counterfactual CSVs produced by 00_pull_raw_data.R.
# Expected: at CA/MX pairs, usmca_none >= others (no preference = highest rate).

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(here)
})

RAW <- here("data", "raw")
CA_MX <- c("1220", "2010")
SAMPLE_MONTH <- "2025-07"  # mid-2025, full Liberation-Day context

read_cf <- function(fname) {
  read_csv(file.path(RAW, fname),
           col_types = cols(hts10 = col_character(), cty_code = col_character(),
                            year_month = col_character(),
                            total_rate = col_double()),
           show_col_types = FALSE) |>
    filter(year_month == SAMPLE_MONTH, cty_code %in% CA_MX)
}

none    <- read_cf("counterfactual_usmca_none.csv")
y2024   <- read_cf("counterfactual_usmca2024.csv")
monthly <- read_cf("counterfactual_usmca_monthly.csv")

cat(sprintf("Month %s, CA/MX only\n", SAMPLE_MONTH))
cat(sprintf("  usmca_none:    %d rows, mean total_rate = %.4f\n",
            nrow(none), mean(none$total_rate)))
cat(sprintf("  usmca_2024:    %d rows, mean total_rate = %.4f\n",
            nrow(y2024), mean(y2024$total_rate)))
cat(sprintf("  usmca_monthly: %d rows, mean total_rate = %.4f\n",
            nrow(monthly), mean(monthly$total_rate)))

# Pairwise joins to confirm strict ordering at the pair level
cmp <- none |>
  rename(rate_none = total_rate) |>
  inner_join(y2024 |> rename(rate_2024 = total_rate),
             by = c("hts10", "cty_code", "year_month")) |>
  inner_join(monthly |> rename(rate_monthly = total_rate),
             by = c("hts10", "cty_code", "year_month"))

cat(sprintf("\n  Overlap (CA/MX, %s): %d pairs\n", SAMPLE_MONTH, nrow(cmp)))
cat(sprintf("  usmca_none >= usmca_2024:    %d pairs (%.1f%%)\n",
            sum(cmp$rate_none >= cmp$rate_2024 - 1e-10),
            100 * mean(cmp$rate_none >= cmp$rate_2024 - 1e-10)))
cat(sprintf("  usmca_none >= usmca_monthly: %d pairs (%.1f%%)\n",
            sum(cmp$rate_none >= cmp$rate_monthly - 1e-10),
            100 * mean(cmp$rate_none >= cmp$rate_monthly - 1e-10)))
cat(sprintf("  usmca_2024 vs usmca_monthly (mean diff, 2024-monthly): %.4f\n",
            mean(cmp$rate_2024 - cmp$rate_monthly)))

# Non-CA/MX spot check: scenarios should be IDENTICAL for non-USMCA countries
nonca <- read_csv(file.path(RAW, "counterfactual_usmca_none.csv"),
                   col_types = cols(hts10 = col_character(),
                                    cty_code = col_character(),
                                    year_month = col_character(),
                                    total_rate = col_double()),
                   show_col_types = FALSE) |>
  filter(year_month == SAMPLE_MONTH, cty_code == "5700")  # China

nonca_2024 <- read_csv(file.path(RAW, "counterfactual_usmca2024.csv"),
                        col_types = cols(hts10 = col_character(),
                                         cty_code = col_character(),
                                         year_month = col_character(),
                                         total_rate = col_double()),
                        show_col_types = FALSE) |>
  filter(year_month == SAMPLE_MONTH, cty_code == "5700")

diff_china <- inner_join(
  nonca |> rename(rate_none = total_rate),
  nonca_2024 |> rename(rate_2024 = total_rate),
  by = c("hts10", "cty_code", "year_month")
) |>
  mutate(drift = abs(rate_none - rate_2024))

cat(sprintf("\n  China pair check (usmca_none vs usmca_2024, %s):\n", SAMPLE_MONTH))
cat(sprintf("    %d pairs, max drift = %.2e (should be ~0 for non-USMCA country)\n",
            nrow(diff_china), max(diff_china$drift)))
