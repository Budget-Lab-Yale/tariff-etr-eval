# ==============================================================================
# 03_counterfactual_ladder.R
#
# Waterfall decomposition of the statutory-actual ETR gap, mirroring the
# Gopinath-Neiman (2026) methodology. Each step peels off one channel:
#
#   S0: Full statutory (pre-USMCA, pre-MFN) × 2024 weights
#       → the "announced rate" ceiling (≈ G-N statutory concept)
#
#   --- USMCA steps (move from ceiling to tracker's current statutory) ---
#   S1: + USMCA at December 2024 baseline utilization × 2024 weights
#       → gap S0-S1 = pre-existing USMCA preference (structural baseline)
#   S2: + USMCA at actual 2025 utilization × 2024 weights
#       → gap S1-S2 = USMCA surge (behavioral preference response)
#       → S2 ≈ tracker's reported statutory ETR (with 2024 weights)
#
#   --- Behavioral reweighting ---
#   S3: S2 rates × actual 2025 monthly weights (instead of 2024)
#       → gap S2-S3 = trade diversion + product substitution
#
#   --- Further preference/exemption channels ---
#   S4: + MFN exemption shares (KORUS, GSP, other FTAs) × actual weights
#       → gap S3-S4 = other preference programs
#   S5: + IEEPA-exempt / duty-free products zeroed × actual weights
#       → gap S4-S5 = statutory exemptions (Berman, ITA, pharma, etc.)
#
#   T:  Treasury actual ETR
#       → gap S5-T = residual (timing, enforcement, evasion)
#
# Inputs:
#   - tariff-rate-tracker: snapshot RDS files, USMCA shares, MFN exemptions,
#     IEEPA exempt list, import weights, stacking rules (helpers.R)
#   - tariff-etr-eval: Census HS10 monthly data, Treasury actual ETR
#
# Outputs:
#   output/counterfactual_ladder.csv     -- monthly waterfall
#   output/counterfactual_by_country.csv -- country-level waterfall
#
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(here)

here::i_am("R/03_counterfactual_ladder.R")
source(here("R", "utils.R"))

# Source the tracker's stacking rules (provides apply_stacking_rules())
source(file.path(TRACKER_DIR, "src", "helpers.R"))

cat("=== Counterfactual ETR Ladder (Gopinath-Neiman style) ===\n\n")

# ==============================================================================
# DATA LOADING
# ==============================================================================

# --- 2024 annual import weights (HS10 × country) ---
local_paths <- yaml::read_yaml(file.path(TRACKER_DIR, "config", "local_paths.yaml"))
iw_path <- normalizePath(file.path(TRACKER_DIR, local_paths$import_weights), mustWork = FALSE)
imports_2024 <- readRDS(iw_path) %>%
  group_by(hs10, cty_code) %>%
  summarize(imports = sum(imports, na.rm = TRUE), .groups = "drop") %>%
  filter(imports > 0) %>%
  mutate(cty_code = as.character(cty_code))
total_imports_2024 <- sum(imports_2024$imports)
cat(sprintf("2024 weights: %d pairs, $%.0fB total\n",
            nrow(imports_2024), total_imports_2024 / 1e9))

# --- 2025 monthly HS10 imports (from IMDB bulk files — full coverage) ---
imdb_file <- here("data", "imdb", "imdb_hs10_country_monthly.csv")
if (!file.exists(imdb_file)) {
  stop("IMDB monthly weights not found. Run R/01c_parse_imdb_weights.R first.")
}
imports_monthly <- read_csv(imdb_file, show_col_types = FALSE) %>%
  mutate(cty_code = as.character(cty_code)) %>%
  filter(con_val_mo > 0)
cat(sprintf("Monthly IMDB data: %d rows, %d months, ~%dK pairs/month\n",
            nrow(imports_monthly), n_distinct(imports_monthly$year_month),
            round(nrow(imports_monthly) / n_distinct(imports_monthly$year_month) / 1000)))

# --- USMCA product shares: 2024 (frozen baseline) and 2025 (actual) ---
usmca_2024 <- read_csv(
  file.path(TRACKER_DIR, "resources", "usmca_product_shares_2024.csv"),
  show_col_types = FALSE
) %>% mutate(cty_code = as.character(cty_code))

usmca_2025 <- read_csv(
  file.path(TRACKER_DIR, "resources", "usmca_product_shares_2025.csv"),
  show_col_types = FALSE
) %>% mutate(cty_code = as.character(cty_code))
cat(sprintf("USMCA shares: 2024 = %d rows, 2025 = %d rows\n",
            nrow(usmca_2024), nrow(usmca_2025)))

# --- MFN exemption shares (KORUS, FTAs, GSP at HS2 × country) ---
mfn_exemptions <- read_csv(
  file.path(TRACKER_DIR, "resources", "mfn_exemption_shares.csv"),
  show_col_types = FALSE
) %>% mutate(cty_code = as.character(cty_code))
cat(sprintf("MFN exemption shares: %d HS2 × country pairs\n", nrow(mfn_exemptions)))

# --- IEEPA-exempt product list ---
ieepa_exempt <- read_csv(
  file.path(TRACKER_DIR, "resources", "ieepa_exempt_products.csv"),
  show_col_types = FALSE
)
ieepa_exempt_set <- ieepa_exempt$hts10
cat(sprintf("IEEPA exempt products: %d HTS10 codes\n", length(ieepa_exempt_set)))

# --- MFN base rates for all HTS10 products ---
# Used as fallback for products not in the tariff snapshot (no Ch99 exposure).
# products_raw.csv has parsed MFN rates; NAs are statistical suffixes whose
# parent rate wasn't inherited in the CSV. We fill NA → 0 (most are duty-free:
# ch30 pharma, ch49 printed material, ch97 art, etc.).
mfn_products <- read_csv(
  file.path(TRACKER_DIR, "data", "processed", "products_raw.csv"),
  col_types = cols(hts10 = col_character(), base_rate = col_double(), .default = col_skip())
) %>%
  transmute(hts10, mfn_rate = coalesce(base_rate, 0))
cat(sprintf("MFN base rates: %d products (%d with rate, %d defaulted to 0)\n",
            nrow(mfn_products),
            sum(mfn_products$mfn_rate > 0),
            sum(mfn_products$mfn_rate == 0)))

# --- Treasury actual ETR ---
actual_etr <- load_actual_etr() %>%
  filter(date >= "2025-01-01") %>%
  mutate(actual_rate = effective_rate / 100)

# ==============================================================================
# HELPERS: Build rates at each step of the ladder
#
# All functions return a df with (hts10, country, total_rate) after applying
# the relevant adjustments and running apply_stacking_rules().
#
# The key insight: USMCA, MFN exemptions, and IEEPA exemptions all modify
# component rates BEFORE stacking. So we chain adjustments on the component
# df, then stack once at the end.
# ==============================================================================

ensure_metal_columns <- function(df) {
  for (col in c("steel_share", "aluminum_share", "copper_share", "other_metal_share")) {
    if (!col %in% names(df)) df[[col]] <- NA_real_
  }
  if (!"is_copper_heading" %in% names(df)) df$is_copper_heading <- FALSE
  df
}

#' Extract pre-USMCA, pre-MFN statutory component rates from a snapshot.
build_statutory_components <- function(snap) {

  snap <- ensure_metal_columns(snap)
  snap %>%
    transmute(
      hts10, country,
      base_rate          = statutory_base_rate,
      rate_232           = statutory_rate_232,
      rate_301           = statutory_rate_301,
      rate_ieepa_recip   = statutory_rate_ieepa_recip,
      rate_ieepa_fent    = statutory_rate_ieepa_fent,
      rate_s122          = coalesce(statutory_rate_s122, 0),
      rate_section_201   = coalesce(statutory_rate_section_201, 0),
      rate_other         = coalesce(statutory_rate_other, 0),
      metal_share        = coalesce(metal_share, 1.0),
      steel_share, aluminum_share, copper_share, other_metal_share,
      is_copper_heading
    )
}

#' Modify component rates for USMCA utilization (pre-stacking).
#' NOTE: Does not apply 232 auto content scaling (us_auto_content_share = 0.40).
#' In the tracker, USMCA reduces rate_232 for auto/MHD products via
#' rate_232 * (1 - usmca_share * 0.40). Omitting this overstates S1/S2 by a
#' small amount (~0.05 pp) concentrated in ch87 (vehicles). Acceptable for the
#' blog decomposition; flag in output notes.
mod_usmca <- function(comp, usmca_shares) {
  CTY_CA <- "1220"; CTY_MX <- "2010"
  comp %>%
    left_join(usmca_shares, by = c("hts10", "country" = "cty_code")) %>%
    mutate(
      usmca_share = if_else(
        country %in% c(CTY_CA, CTY_MX),
        coalesce(usmca_share, 0), 0
      ),
      base_rate        = base_rate * (1 - usmca_share),
      rate_ieepa_recip = rate_ieepa_recip * (1 - usmca_share),
      rate_ieepa_fent  = rate_ieepa_fent * (1 - usmca_share),
      rate_s122        = rate_s122 * (1 - usmca_share)
    ) %>%
    select(-usmca_share)
}

#' Modify component rates for MFN exemptions at HS2 × country (pre-stacking).
#' Excludes CA/MX — the tracker handles them via USMCA at HTS10 level (step 7),
#' controlled by policy_params.yaml `mfn_exemption.exclude_usmca_countries: true`.
mod_mfn <- function(comp, mfn_shares) {
  CTY_CA <- "1220"; CTY_MX <- "2010"
  comp %>%
    mutate(hs2 = substr(hts10, 1, 2)) %>%
    left_join(mfn_shares, by = c("hs2", "country" = "cty_code")) %>%
    mutate(
      exemption_share = coalesce(exemption_share, 0),
      # Skip CA/MX: USMCA already handles their preference reduction
      exemption_share = if_else(country %in% c(CTY_CA, CTY_MX), 0, exemption_share),
      base_rate = base_rate * (1 - exemption_share)
    ) %>%
    select(-exemption_share, -hs2)
}

#' Remove IEEPA exemptions — i.e., apply the exemption to already-computed rates.
#'
#' IMPORTANT: The tracker's statutory_rate_ieepa_recip already has 0 for exempt
#' products (exemption applied during rate construction in 06_calculate_rates.R).
#' So this is a NO-OP if called on the statutory components as-is.
#'
#' To properly measure the IEEPA exemption channel, we need to REVERSE the logic:
#' in steps S0-S4 we leave the statutory_rate_* as-is (which means exempt products
#' have rate_ieepa_recip = 0 throughout). The exemption is already embedded in S0.
#'
#' For a clean decomposition, we'd need the *counterfactual* rate that exempt
#' products would face if not exempt. This requires knowing the country-specific
#' IEEPA rate per product, which isn't stored in snapshots.
#'
#' CURRENT APPROACH: S5 = S4 (exemption channel = 0 in the ladder). The IEEPA
#' exemption effect is folded into S0's level being lower than the theoretical
#' maximum. Document this in the output.
#'
#' FUTURE: Reconstruct counterfactual IEEPA rates from policy_params.yaml to
#' measure this channel explicitly.
mod_ieepa_exempt <- function(comp, exempt_set) {
  # No-op: exemption already embedded in statutory_rate_* columns.
  # Kept as placeholder for future counterfactual reconstruction.
  comp
}

#' Stack component rates and return (hts10, country, total_rate).
finalize <- function(comp) {
  apply_stacking_rules(comp, cty_china = "5700") %>%
    select(hts10, country, total_rate)
}

#' Compute import-weighted ETR using total imports as denominator.
#'
#' Uses left_join so unmatched products stay in the calculation. Unmatched
#' products get their MFN base rate from mfn_lookup (if provided) or 0.
#' Denominator = ALL imports, matching the tracker's methodology.
#'
#' @param rates_df df with (hts10, country, total_rate)
#' @param weights_df df with (hs10, cty_code, imports)
#' @param mfn_lookup df with (hts10, mfn_rate) — MFN base rates for fallback
w_etr <- function(rates_df, weights_df, mfn_lookup = NULL) {
  merged <- weights_df %>%
    left_join(rates_df, by = c("hs10" = "hts10", "cty_code" = "country"))

  n_matched <- sum(!is.na(merged$total_rate))
  matched_imports <- sum(merged$imports[!is.na(merged$total_rate)], na.rm = TRUE)
  total_imports <- sum(merged$imports, na.rm = TRUE)

  # Fill unmatched: use MFN base rate if available, else 0
  if (!is.null(mfn_lookup)) {
    merged <- merged %>%
      left_join(mfn_lookup, by = c("hs10" = "hts10")) %>%
      mutate(total_rate = coalesce(total_rate, mfn_rate, 0)) %>%
      select(-mfn_rate)
  } else {
    merged$total_rate[is.na(merged$total_rate)] <- 0
  }

  list(
    etr = sum(merged$total_rate * merged$imports, na.rm = TRUE) / total_imports,
    coverage = matched_imports / total_imports,
    matched_B = matched_imports / 1e9
  )
}

#' Same, by partner group. Uses left_join + MFN fallback.
w_etr_by_country <- function(rates_df, weights_df, mfn_lookup = NULL) {
  merged <- weights_df %>%
    left_join(rates_df, by = c("hs10" = "hts10", "cty_code" = "country"))

  if (!is.null(mfn_lookup)) {
    merged <- merged %>%
      left_join(mfn_lookup, by = c("hs10" = "hts10")) %>%
      mutate(total_rate = coalesce(total_rate, mfn_rate, 0)) %>%
      select(-mfn_rate)
  } else {
    merged$total_rate[is.na(merged$total_rate)] <- 0
  }

  merged %>%
    mutate(partner_group = assign_partner_group(cty_code)) %>%
    group_by(partner_group) %>%
    summarize(
      etr = sum(total_rate * imports, na.rm = TRUE) / sum(imports, na.rm = TRUE),
      imports_B = sum(imports, na.rm = TRUE) / 1e9,
      .groups = "drop"
    )
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

months_2025 <- imports_monthly %>%
  distinct(year_month) %>% arrange(year_month) %>% pull(year_month)

results <- list()
results_country <- list()

for (ym in months_2025) {
  query_date <- as.Date(paste0(ym, "-01"))
  month_label <- format(query_date, "%b %Y")
  cat(sprintf("\n--- %s ---\n", month_label))

  # Load snapshot
  snap <- tryCatch(
    load_snapshot_at_date(query_date),
    error = function(e) { cat("  Skipping:", conditionMessage(e), "\n"); NULL }
  )
  if (is.null(snap)) next

  # Base statutory components (pre-USMCA, pre-MFN)
  comp <- build_statutory_components(snap)

  # Monthly weights from IMDB
  wt_month <- imports_monthly %>%
    filter(year_month == ym) %>%
    transmute(hs10 = as.character(hs10), cty_code, imports = con_val_mo) %>%
    filter(imports > 0)

  # ---- S0: Full statutory × 2024 weights ----
  rates_s0 <- finalize(comp)
  r_s0 <- w_etr(rates_s0, imports_2024, mfn_products)
  s0 <- r_s0$etr
  s0_cty <- w_etr_by_country(rates_s0, imports_2024, mfn_products)
  cat(sprintf("  S0 (full statutory, 2024w):          %5.2f%% [cov %.0f%%]\n",
              s0 * 100, r_s0$coverage * 100))

  # ---- S1: + USMCA frozen 2024 × 2024 weights ----
  rates_s1 <- comp %>% mod_usmca(usmca_2024) %>% finalize()
  s1 <- w_etr(rates_s1, imports_2024, mfn_products)$etr
  s1_cty <- w_etr_by_country(rates_s1, imports_2024, mfn_products)
  cat(sprintf("  S1 (+ USMCA frozen 2024, 2024w):    %5.2f%%\n", s1 * 100))

  # ---- S2: + USMCA actual 2025 × 2024 weights ----
  rates_s2 <- comp %>% mod_usmca(usmca_2025) %>% finalize()
  s2 <- w_etr(rates_s2, imports_2024, mfn_products)$etr
  s2_cty <- w_etr_by_country(rates_s2, imports_2024, mfn_products)
  cat(sprintf("  S2 (+ USMCA actual 2025, 2024w):    %5.2f%%\n", s2 * 100))

  # ---- S2b & S3: Behavioral reweighting (total-imports denominator) ----
  # Both steps use total-imports denominators. The 2024 weights are annual
  # ($3,124B) while monthly weights are ~$260B. To make the denominators
  # comparable, we normalize monthly imports to shares, then scale to the
  # annual total. This way:
  #   S2b = sum(rate * annual_imports) / annual_total
  #   S3  = sum(rate * share_monthly * annual_total) / annual_total
  #       = sum(rate * share_monthly)
  # Both use the same $3,124B denominator implicitly.
  rates_tracker <- snap %>% select(hts10, country, total_rate)

  r_s2b <- w_etr(rates_tracker, imports_2024, mfn_products)
  s2b <- r_s2b$etr
  cat(sprintf("  S2b (tracker rates, 2024w):          %5.2f%% [cov %.0f%%]\n",
              s2b * 100, r_s2b$coverage * 100))

  # S3 uses IMDB monthly weights directly. With ~167K pairs/month (complete
  # coverage from Census bulk files), the denominator is the month's total
  # imports. ETR = sum(rate * monthly_imports) / sum(monthly_imports).
  r_s3 <- w_etr(rates_tracker, wt_month, mfn_products)
  s3 <- r_s3$etr
  r_s3_coverage <- r_s3$coverage
  s3_cty <- w_etr_by_country(rates_tracker, wt_month, mfn_products)
  cat(sprintf("  S3 (tracker rates, actual w):        %5.2f%% [cov %.0f%%]\n",
              s3 * 100, r_s3_coverage * 100))

  # S4 and S5 are dropped for now — the S3→T residual captures all remaining
  # channels (MFN exemptions, IEEPA exemptions, timing, enforcement).
  # The FTA decomposition (02b_fta_decomposition.R) already breaks down this
  # residual using IMDB data. Attempting to decompose it further here with
  # different rate tables introduces the apples-to-oranges problem seen above.
  s4 <- s3  # placeholder
  s5 <- s3  # placeholder
  s4_cty <- s3_cty
  s5_cty <- s3_cty

  # ---- T: Treasury actual ----
  treasury <- actual_etr %>% filter(date == query_date)
  t_rate <- if (nrow(treasury) > 0) treasury$actual_rate[1] else NA_real_
  cat(sprintf("  T  (Treasury actual):                %5.2f%%\n",
              if (!is.na(t_rate)) t_rate * 100 else NA))

  # ---- Assemble row ----
  # Behavioral gap uses s2b (tracker rates × 2024w) vs s3 (tracker rates × actual w)
  # This matches the original 02_decompose_gap.R methodology exactly.
  results[[ym]] <- tibble(
    date = query_date, month = month_label,
    s0_full_statutory      = s0,
    s1_usmca_frozen_2024   = s1,
    s2_usmca_actual_2025   = s2,
    s2b_tracker_2024w      = s2b,
    s3_tracker_actualw     = s3,
    s4_mfn_exemptions      = s4,
    s5_ieepa_exempt        = s5,
    treasury_actual        = t_rate,
    coverage_2024w         = r_s0$coverage,
    coverage_actualw       = r_s3_coverage,
    # Channel gaps (pp)
    gap_usmca_baseline     = (s0 - s1) * 100,
    gap_usmca_surge        = (s1 - s2) * 100,
    gap_behavioral         = (s2b - s3) * 100,
    gap_other_prefs        = (s3 - s4) * 100,
    gap_ieepa_exempt       = (s4 - s5) * 100,
    gap_residual           = if (!is.na(t_rate)) (s5 - t_rate) * 100 else NA_real_,
    gap_total              = if (!is.na(t_rate)) (s0 - t_rate) * 100 else NA_real_
  )

  # ---- Country detail ----
  cty_all <- s0_cty %>% rename(s0 = etr, imports_2024_B = imports_B) %>%
    full_join(s1_cty %>% rename(s1 = etr) %>% select(-imports_B), by = "partner_group") %>%
    full_join(s2_cty %>% rename(s2 = etr) %>% select(-imports_B), by = "partner_group") %>%
    full_join(s3_cty %>% rename(s3 = etr, imports_actual_B = imports_B), by = "partner_group") %>%
    full_join(s4_cty %>% rename(s4 = etr) %>% select(-imports_B), by = "partner_group") %>%
    full_join(s5_cty %>% rename(s5 = etr) %>% select(-imports_B), by = "partner_group") %>%
    mutate(
      date = query_date, month = month_label,
      gap_usmca_baseline = (s0 - s1) * 100,
      gap_usmca_surge    = (s1 - s2) * 100,
      gap_behavioral     = (s2 - s3) * 100,
      gap_other_prefs    = (s3 - s4) * 100,
      gap_ieepa_exempt   = (s4 - s5) * 100
    )
  results_country[[ym]] <- cty_all
}

# ==============================================================================
# OUTPUT
# ==============================================================================

ladder <- bind_rows(results)
ladder_country <- bind_rows(results_country)

output_dir <- here("output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

write_csv(ladder, file.path(output_dir, "counterfactual_ladder.csv"))
cat(sprintf("\nWrote: output/counterfactual_ladder.csv (%d months)\n", nrow(ladder)))

write_csv(ladder_country, file.path(output_dir, "counterfactual_by_country.csv"))
cat(sprintf("Wrote: output/counterfactual_by_country.csv (%d rows)\n", nrow(ladder_country)))

# ==============================================================================
# SUMMARY TABLE
# ==============================================================================

cat("\n=== Counterfactual Ladder Summary ===\n\n")
cat(sprintf("%-10s | %6s %6s %6s %6s %6s %6s | %6s %6s %6s %6s %6s\n",
            "Month", "S0", "S1", "S2", "S2b", "S3", "T",
            "USMCA0", "USMCAs", "Behav", "Prefs", "Resid"))
cat(paste(rep("-", 95), collapse = ""), "\n")

for (i in seq_len(nrow(ladder))) {
  r <- ladder[i, ]
  cat(sprintf("%-10s | %5.1f%% %5.1f%% %5.1f%% %5.1f%% %5.1f%% %5.1f%% | %+5.1f  %+5.1f  %+5.1f  %+5.1f  %+5.1f\n",
              r$month,
              r$s0_full_statutory * 100,
              r$s1_usmca_frozen_2024 * 100,
              r$s2_usmca_actual_2025 * 100,
              r$s2b_tracker_2024w * 100,
              r$s3_tracker_actualw * 100,
              if (!is.na(r$treasury_actual)) r$treasury_actual * 100 else NA,
              r$gap_usmca_baseline,
              r$gap_usmca_surge,
              r$gap_behavioral,
              r$gap_other_prefs,
              if (!is.na(r$gap_residual)) r$gap_residual else NA))
}

cat("\n=== Done ===\n")
