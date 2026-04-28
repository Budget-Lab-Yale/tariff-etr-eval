# Section 232 auto effective-date gating (deferred)

**Date**: 2026-04-28
**Triggered by**: `tracker_over_report.md` Round 1 chapter 87 finding (~$7.3 B)
**Status**: bug confirmed, fix deferred (requires parser-level change)

## Finding

Trackerover Round 1 flagged $7.3 B of BUG-LIKELY over-statement in chapter 87 (motor vehicles), concentrated in March 2025 cells from Japan, EU, UK at tracker rate ~17.8 % (rev_3 weighted) and ~26.3 % (rev_6 weighted), against Census collected ~2.5 % (MFN base only).

Tracker-side trace:

- `s232_auto_parts.txt` (130 codes) and `s232_mhd_parts.txt` (182 codes) are correct (verified against CBP PDF + HTSUS Note 33(g) / 34(i)). Lists are not the issue.
- `data/timeseries/snapshot_rev_3.rds` for 8703.23.01.40: `rate_232 = 0` ✓ (rev_3 effective Feb 4, 2025, pre-§232 auto)
- `data/timeseries/snapshot_rev_6.rds` for 8703.23.01.40: `rate_232 = 0.238` (rev_6 effective Mar 12, 2025)
- `data/timeseries/ch99_rev_6.rds` shows 4 entries under 9903.94:

  | ch99_code | rate | description |
  |---|---:|---|
  | 9903.94.01 | 0.25 | "Except for 9903.94.02, 9903.94.03, and 9903.94.04, **effective with respect to entries on or after April 3, 2025**, …" |
  | 9903.94.02 | NA | "**Effective with respect to entries on or after April 3, 2025**, articles as provided…" |
  | 9903.94.03 | 0.25 | "**Effective with respect to entries on or after April 3, 2025**, certain passenger…" |
  | 9903.94.04 | NA | "**Effective with respect to entries on or after April 3, 2025**, certain passenger…" |

The HTS revision 6 (effective March 12, 2025) added the §232 auto Chapter 99 entries with an explicit **April 3, 2025 effective date** in the description. The tracker's `extract_section232_rates()` in `05_parse_policy_params.R` reads the 25% rate but ignores the date footnote.

`grep` of `05_parse_policy_params.R` for `"effective with respect"`, `"effective with"`, `"on or after"`, `"effective_date"` (in extraction scope) returns zero matches — there is no current handling of date-bounded ch99 entries.

This causes the tracker to apply §232 auto rates ~22 days early (March 12 → April 3, 2025), generating ~$7.3 B of chapter 87 trackerover concentrated in March 2025 cells. By the May 2025 onwards, the rate is correctly active and the cells fall out of the trackerover ranking.

## Why this is structural, not a quick fix

The pattern "Effective with respect to entries on or after [DATE]" appears in many §232 and IEEPA chapter-99 entries during 2025:

- §232 auto (9903.94.01–.04): April 3, 2025
- §232 auto parts: May 3, 2025
- §232 copper proclamation entries
- IEEPA Phase 2 country EOs (some bear similar effective-date language)
- §232 annex-restructuring entries (April 6, 2026)

A proper fix needs:

1. **Parser extension** (`05_parse_policy_params.R`): add a `effective_date_offset` column to the parsed ch99 dataframe by regex-extracting "on or after [DATE]" from descriptions.
2. **Rate calculator gate** (`06_calculate_rates.R`): when joining ch99 rates to revisions, zero out rates where `revision_effective_date < ch99_effective_date_offset`.
3. **Test coverage**: a unit test against rev_6 / 9903.94.01 confirming the rate is 0 in revisions effective March 12 – April 2, 2025 and 25 % from April 3 onwards.

Estimated effort: half a day for a careful implementation + tests. Risk: regex parsing of date phrases needs to be tolerant of formatting variations across HTS revisions ("effective with respect to entries on or after April 3, 2025" vs "Effective on or after …" vs date numerals etc.).

## Interim posture

- **Do not patch.** The fix is structural and warrants a focused implementation pass with tests. A rushed regex fix risks under-extracting and silently leaving the bug in place for other entries.
- **Quantify** via the next `tracker_over` refresh — if the chapter 87 BUG-LIKELY footprint stays at ~$7 B, the case for prioritizing the parser change strengthens.
- **Document** in `tracker_audits/` (this file) so the Round 1 chapter 87 finding doesn't re-emerge unflagged in the next refresh cycle without context.

## Related entries that may be affected

When the parser fix lands, also re-validate:

- §232 auto parts (May 3, 2025 effective; HTS revision likely earlier)
- §232 copper proclamation
- §232 wood / softwood entries
- IEEPA Phase 2 country EOs
- §232 annex-restructuring (April 6, 2026)

Each is a candidate for the same March 12-style misalignment, just at different dates.

## Recommended path

1. Open a tracker-side issue / TODO entry referencing this memo.
2. When a focused session is available, port the §232 auto fix:
   - Extract `effective_date_offset` column in chapter 99 parser.
   - Gate rate application in `06_calculate_rates.R`.
   - Add a regression test using the rev_6 9903.94.01 example.
3. Re-run `09_diagnostic_refresh.do`. Expect chapter 87 trackerover to drop by $5–7 B.
4. Update `tracker_over_report.md` with the post-fix Round 2 numbers.
