# SLURM runbook — tariff-etr-eval golden-reference run

Two-stage flow on the BL cluster (mirrors `multnomah-county-tax`):

1. **Stage 1 — R data assembly** (`slurm/run_pull.sbatch`)
2. **Stage 2 — Stata analysis** (`slurm/run_stata.sbatch`)

Stage 2 consumes Stage 1's `data/raw/`. The Stata outputs are the **golden
reference** the R port is validated against.

Cluster facts:
- R module:     `R/4.4.2-gfbf-2024a` + `arrow-R/17.0.0.1-foss-2024a-R-4.4.2`
                (matches the publish's build stack; the 2022b arrow-R/16.1.0
                module is broken — missing libarrow_dataset.so.1601)
- Stata module: `Stata/19` (MP/16), binary `stata-mp`
- Partition:    `day`
- Repo root:    `/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval`

## Mode: publish-mode S1–S4 + T

No DataWeb token is available, so the USMCA scenario snapshots (S0 `rate_2024`,
the `usmca_monthly` diagnostic) cannot be built. The pipeline runs the ladder
as **S1–S4 + T**; S0-dependent figures and Step 6 self-skip. To produce the
full six-tier (S0) reference later, set `DATAWEB_API_TOKEN` and add
`--refresh-tracker` to Stage 1 (rebuilds the scenarios; ~60–90 min).

## One-time setup

R packages: all required packages (`arrow httr jsonlite dplyr readr here
stringi yaml tidyverse`) are present in the `R/4.4.2-gfbf-2024a` +
`arrow-R/17.0.0.1-foss-2024a-R-4.4.2` stack that `run_pull.sbatch` loads — no
manual install needed.

Stata packages (see `00_etr_eval.do` header): `ftools reghdfe gtools estout
coefplot plotplainblind heatplot palettes colrspace`.

Confirm `config/local_paths.yaml` points `tracker_data_dir` at the publish
(default already set for ji252).

## Run

```bash
cd /nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval

# Stage 1 (R pull). Several hours first pass (IMDB download/parse).
pull_id=$(sbatch --parsable slurm/run_pull.sbatch)

# Stage 2 (Stata), chained to start only if Stage 1 succeeds.
sbatch --dependency=afterok:$pull_id slurm/run_stata.sbatch

squeue -u $USER
tail -f slurm/logs/pull-*.log     # Stage 1
tail -f logs/pull_raw_data_*.log  # the R script's own progress log
tail -f slurm/logs/stata-*.log    # Stage 2
```

## Hand-off checks

After Stage 1:
```bash
ls data/raw/{imdb_hs10_country_monthly,counterfactual_h2avg,counterfactual_other_pref_delta_monthly,tariff_revenue}.csv
```
After Stage 2 (the golden reference):
```bash
ls results/tables/*.csv        # counterfactual_ladder.csv, decomp_monthly.csv, ...
ls results/figures/*.png
```

## Notes

- Stata changes for publish mode (S0 optional) are **untested in CI** — this
  run is their first real test; expect a possible debug iteration.
- The R port is validated by diffing its outputs against `results/tables/*.csv`
  from this run.
