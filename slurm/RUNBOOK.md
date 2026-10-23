# SLURM runbook — tariff-etr-eval

Two-stage flow on the BL cluster:

1. **Stage 1 — R data assembly** (`slurm/run_pull.sbatch`)
2. **Stage 2 — R analysis + figures** (`slurm/run_r.sbatch`)

Stage 2 consumes Stage 1's `data/raw/` and produces `results/tables/*.csv` +
`results/figures/*.png`.

Cluster facts:
- R module:     `R/4.4.2-gfbf-2024a` + `arrow-R/17.0.0.1-foss-2024a-R-4.4.2`
                (matches the publish's build stack; the 2022b arrow-R/16.1.0
                module is broken — missing libarrow_dataset.so.1601)
- Partition:    `day`
- Repo root:    `/path/to/repos/tariff-etr-eval`

## Mode: S1–S4 + T

The pipeline runs the ladder as **S1–S4 + T**. (The earlier S0 USMCA-2024
backstory tier and its scenario plumbing were removed.) The default run reads
snapshots, daily ETRs, and 2024 import weights from the shared publish; a
DataWeb token + `--refresh-tracker` is needed only to rebuild tracker data
itself (expects the restructured-tracker sibling layout).

## One-time setup

R packages: all required packages (`arrow httr jsonlite dplyr readr here
stringi yaml tidyverse`) are present in the `R/4.4.2-gfbf-2024a` +
`arrow-R/17.0.0.1-foss-2024a-R-4.4.2` stack that the sbatch runners load — no
manual install needed.

Confirm `config/local_paths.yaml` points `tracker_data_dir` at the publish
(default already set for ji252).

## Run

```bash
cd /path/to/repos/tariff-etr-eval

# Stage 1 (R pull). Several hours first pass (IMDB download/parse).
pull_id=$(sbatch --parsable slurm/run_pull.sbatch)

# Stage 2 (R analysis + figures), chained to start only if Stage 1 succeeds.
sbatch --dependency=afterok:$pull_id slurm/run_r.sbatch

squeue -u $USER
tail -f slurm/logs/pull-*.log     # Stage 1
tail -f logs/pull_raw_data_*.log  # the R script's own progress log
tail -f slurm/logs/r-*.log        # Stage 2
```

To re-run the analysis against an existing `data/raw/` without re-pulling, use
`slurm/run_r.sbatch` (or `slurm/run_refresh_rebuild.sbatch` to re-pull only the
publish-derived inputs first). `slurm/run_full.sbatch` runs both stages in one
job.

## Hand-off checks

After Stage 1:
```bash
ls data/raw/{imdb_hs10_country_monthly,counterfactual_h2avg,counterfactual_other_pref_delta_monthly,tariff_revenue}.csv
```
After Stage 2:
```bash
ls results/tables/*.csv        # counterfactual_ladder.csv, decomp_monthly.csv, ...
ls results/figures/*.png
cat results/tables/run_meta.csv   # tracker vintage + window per step
```
