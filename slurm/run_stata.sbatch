#!/usr/bin/env bash
#SBATCH --job-name=etr-stata
#SBATCH --partition=day
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=slurm/logs/stata-%j.log
#SBATCH --mail-type=END,FAIL

# Stage 2 -- Stata analysis pipeline (00_etr_eval.do).
#
# Runs with run_pull = 0 (default in globals.do): consumes the data/raw/ that
# Stage 1 (run_pull.sbatch) produced. In publish mode S0 / usmca_monthly are
# absent, so the six-tier ladder degrades to S1-S4 + T: Steps 1-3/3b run with
# S0-dependent figures skipped, Step 6 self-skips, Steps 4-5 run normally.
#
# Outputs (the golden reference for the R port): results/tables/*.csv,
# results/figures/*.png, data/working/*.dta.
#
# Run Stage 1 first and confirm data/raw/ is populated:
#   ls data/raw/{imdb_hs10_country_monthly,counterfactual_h2avg,tariff_revenue}.csv

set -euo pipefail

REPO=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval
cd "$REPO"
mkdir -p slurm/logs

module purge
module load Stata/19
# R for orchestrator Step 7 (value-misreporting) -- Rscript must be on PATH
module load R/4.4.1-foss-2022b

# Sanity: MP license core cap (expect 16) and visible cores.
stata-mp -q -b -e 'di c(processors_max)' >/dev/null 2>&1 || true

echo "[stata] start $(date)"
# Batch mode: writes 00_etr_eval.log in the repo root (plus the script's own
# log under logs/). Non-zero exit on Stata error.
stata-mp -b do 00_etr_eval.do
echo "[stata] done $(date)"

echo "[stata] tables produced:"
ls -1 results/tables/*.csv 2>/dev/null | sed 's#.*/##'
