# Open questions / design-debt tracker

Practice ported from `tariff-etr-adj/docs/open_questions.md`: every unresolved
design decision, deferred port, or external dependency gets a numbered entry
with a date; resolutions stay in place (struck through or marked RESOLVED)
so decisions remain auditable. Update this file in the same commit as the
change that opens or closes an item.

---

## Open

**1. Stata→R port: deferred steps** *(opened 2026-06-10, with the R cutover)*
The R pipeline (00_run_all.R → 01b/02a/02b/02c/03a/03b) covers the primary
analysis: panel build, six-tier ladder, channel decompositions, baseline
figures, VMR. Not yet ported from `archive/stata/`:
  - `04_fta_decomposition.do` — S2→S3 preference-channel split (needs the 10M+
    row `imdb_detail.csv` and `classify_pref_channel`); port when the S2→S3
    channel write-up needs channel-level numbers again.
  - `05_max_district_crosscheck.do`, `05a/05b` tracker diagnostics — operator
    handoffs to the tracker maintainer; port on the next tracker audit round.
  - `06_baseline_etr_diagnostic.do` — also the only consumer of the
    per-revision `tracker_snapshots` merge (`total_rate`), which 01b therefore
    does not build. Port both together if the reconstruction-methodology
    diagnostic is needed again.
  - `07_cumulative_duty_gap.do` — superseded in spirit by the strip-based
    gap_timing decomposition in 02a; port only if the cumulative-dollars view
    is wanted for the paper.
  - 03/03b long-tail figures: 2x2 occupancy tables (`cmp_2x2_*`),
    `monthly_summary` workbook, gap-quantile table, S2S4/S1S2 facet figures.

**2. USMCA adjustment explainer + S0 rung need full (DataWeb) mode**
*(carried over from the publish-mode work, 2026-06-08)*
The shared tracker publish lacks the USMCA scenario snapshots, so S0
(`rate_2024`), `rate_usmca_monthly`, and 03b's adjustment-explainer figure are
absent in publish mode. Request to the tracker maintainer:
`docs/shared_publish_extensions.md`. The R pipeline auto-detects and degrades
to S1–S4 + T (`have_s0` attribute on `panel.rds`).

**3. De-minimis component and the Tariff Model** *(opened 2026-06-10)*
02a's gap_timing decomposition estimates the postal-channel duty with the
step estimator ported from adj (`code/strips/deminimis_strip.R`). The same
double-count guard applies here as there: if any downstream revenue use takes
the de-minimis component out of the residual, postal-channel revenue must be
accounted separately, not also inside an eta-style compliance parameter.

**4. AD/CVD interim input** *(opened 2026-06-10, mirrors adj #1)*
`resources/adcvd_collected.csv` is copied from tariff-etr-adj (FY19 Appendix A
partner shares × $2.0B/yr). Upgrade path: case-level FY2021+ Appendix A from
CBP Office of Trade (ADCVDISSUES-HQ@cbp.dhs.gov / FOIA). When adj updates its
curated file, re-copy (single source of truth lives in adj).

**5. VMR v2 implementation** *(opened 2026-06-10)*
`docs/vmr_v2_proposal.md`: placebo noise floor, dose-response regression,
duty-at-stake weights + implied dollars, related-party split, Laspeyres
control. Gate: check the IMP_DETL bulk layout for the related-party field
before scoping §4.

**6. Eta methodology doc home** *(opened 2026-06-10)*
All eta-calibration *work* now lives in tariff-etr-adj (this repo's
`08_eta_calibration.R` is archived to avoid drift), but the methodology
derivation `docs/eta_calibration_methodology.md` is still here and adj links
to it. Decide: move the doc to adj (preferred) or leave with a pointer.

**7. Tracker vintage sidecar from the pull** *(opened 2026-06-10)*
`utils.R::tracker_vintage()` falls back to reading the publish manifest
directly because Step 0 does not yet write `data/raw/statutory_rates_meta.csv`.
Add the sidecar write to `code/01a_pull_raw_data.R` (port the ~15 lines from
adj's `01_data.R`) on its next touch.

## Resolved

**R-0. Stata r(109) abort in publish mode** *(resolved 2026-06-10)*
`01_etr_clean.do` imported counterfactual CSVs with positional
`stringcols(1 2 3)`; the R pull writes `total_rate` in column 3 of
`counterfactual_h2avg.csv`, so the rate arrived as string and
`replace rate_h2avg = 0 if missing(...)` died with a type mismatch. Fixed
(name-based destring at all four sites) in commit 1ed7635; the golden
reference run validates the fix.
