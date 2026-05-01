# Response — Dense Rate Export Plan (revised)

**Date:** 2026-04-17
**Re:** `tariff-rate-tracker/docs/dense_rate_export_plan.md`

## Summary

The revised plan drops Option A and commits fully to Option B (post-hoc grid expansion). Three material changes from the original draft, all aimed at reusing machinery that already exists in the tracker rather than introducing parallel code paths.

## Changes to the plan

### 1. Option A removed. Grid expansion reuses existing helper logic.

The original plan recommended relaxing the `n_ch99_refs > 0` filter in `calculate_rates_fast()` as a ~1-line change, with Option B as a fallback. On inspection this doesn't work:

- The filter the plan targeted (`06_calculate_rates.R:62`) populates a local `products_expanded` that is **never used downstream inside the function**. Dropping it has no effect on the output.
- The filter that actually gates MFN-only products is at line 76 (`product_refs`), which exists because downstream joins unnest `ch99_refs`. MFN-only products have an empty list there — threading them through the `left_join` → `pivot_wider` path would either drop them or produce NA-filled junk columns that then need a coalesce pass anyway.
- Adding the dense grid post-hoc is strictly cleaner.

More importantly, the tracker *already* has the exact densification step we need: `06_calculate_rates.R:909-943` implements "expand to all products × all countries, fill authority columns with zeros, keep `base_rate`." It is currently gated on `ieepa_was_invalidated` (a separate concern about SCOTUS invalidation stabilizing the grid).

The revised plan:
- Extracts that block into a named helper `ensure_dense_grid(rates, products, countries)`.
- Keeps the existing invalidation branch (now a single call to the helper, same behavior).
- Calls the helper unconditionally between step 6d (floor recomputation) and step 7 (USMCA exemptions), so MFN-only pairs enter the dense grid *before* USMCA applies. That placement means CA/MX USMCA-eligible products get their exemption applied on the full grid, which is what we want.

This is a genuinely small change (new helper + one call site), shares code with the existing invalidation path, and preserves current behavior on all footnote-matched rows.

### 2. Scenario runner reuses `build_alternative_timeseries()` instead of a new wrapper.

The original plan proposed a new `src/build_usmca_scenarios.R` driver that would "temporarily override the usmca_shares block in policy_params.yaml." The tracker already has a better mechanism:

- `09_daily_series.R:799 build_alternative_timeseries(pp_override, variant_name, ...)` accepts a modified `policy_params` list in memory — no yaml edits. It loops all revisions, calls `calculate_rates_for_revision()`, and produces per-scenario outputs.
- Lines 986–1034 already invoke it four times for `usmca_annual`, `usmca_monthly`, `usmca_2024`, `usmca_dec2025`.

The four scenarios this project needs (`usmca_none`, `usmca_2024`, `usmca_monthly`, `usmca_h2avg`) map directly onto that harness. The revised plan therefore:
- Drops the new-wrapper proposal.
- Asks for one small modification: `build_alternative_timeseries()` currently writes per-revision snapshots to a tempdir and deletes on exit. Adding an optional `snapshot_out_dir` argument that, when set, persists snapshots to a permanent path and skips the cleanup is a ~5-line change.
- Treats scenario invocation as four calls in the same style as the existing usmca_* blocks, writing to `data/timeseries/<scenario>/`.

This matters because the yaml-override approach would have:
- Required filesystem writes in the middle of a pipeline run (fragile if the run is interrupted).
- Created a divergent pattern from the three USMCA scenarios the tracker already computes.

### 3. `usmca_none` mode: extend `load_usmca_product_shares()` (preferred) instead of short-circuiting USMCA.

Unchanged from the original recommendation, but re-stated explicitly: adding `mode == 'none'` to `load_usmca_product_shares()` that returns 0% utilization for every (hts10, country) keeps the stacking path identical across all four scenarios. The alternative (a scenario yaml via `apply_scenario()`) is listed as a fallback.

## Minor corrections folded into the revised plan

- Row-count estimate for the basic revision adjusted from ~2.5M to ~2.4M (10k HS10 × ~240 Census codes, matching the actual `census_codes$Code` universe).
- Validation check on `n_distinct(hts10)` relaxed to "post-parse HS10 count" (the original check would fail because `04_parse_products.R` drops Ch98 and invalid HS10s, and some parses leave `base_rate = NA`).
- Added a TPC match-rate regression check (rev_6, rev_10, rev_17, rev_18, rev_32) to catch any stacking rule that implicitly assumes every row has a ch99 ref.

## Net effect on the eval side

None. The handoff section of the plan is unchanged:

1. `code/R/00_pull_raw_data.R` pulls from `data/timeseries/<scenario>/` in the tracker and writes `data/raw/snapshot_rates/{scenario}/snapshot_*.csv`.
2. Stata Tier 1 / Tier 2 construction uses the dense per-scenario rate tables directly.
3. `counterfactual_usmca*.csv` reconstructions are retired.

The output files the eval project consumes have the same schema, same filenames, same CSV format — only denser (more rows) and organized under scenario subdirectories.

## Open items left for the tracker maintainer

Three questions passed along, unchanged in substance from the original:

1. Are there any pre-Liberation-Day revisions where `04_parse_products.R` has known HS10 gaps? The dense export will surface these as apparent MFN-coverage holes in the eval denominator.
2. Preference between extending `load_usmca_product_shares()` with `mode == 'none'` vs. adding a `usmca_none` entry to `config/scenarios.yaml`.
3. Layout: `data/timeseries/<scenario>/` vs. `data/timeseries/scenarios/<scenario>/`.

No blocking dependencies on the eval side while these get resolved.
