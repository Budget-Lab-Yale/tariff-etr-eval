#!/usr/bin/env bash
#SBATCH --job-name=etr-full
#SBATCH --partition=day
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=slurm/logs/full-%j.log
#SBATCH --mail-type=END,FAIL

# Single-job full update: Rscript 00_run_all.R --with-pull
# (01a pull -> 01b panel -> 02a/02b/02c -> 03a/03b figures).
#
# Equivalent to run_pull.sbatch + run_r.sbatch chained, but in one allocation.
# Uses the 2024a R stack throughout: 01a's publish-reading sections need
# arrow (the 2022b arrow-R/16.1.0 module is broken -- see slurm/RUNBOOK.md),
# and the analysis steps' packages (data.table/bit64/ggplot2/...) are all
# present there too (verified 2026-06-12).
#
# Time/mem sized for the pull (IMDB download/parse dominates; cached reruns
# much faster). Progress:
#   tail -f logs/pull_raw_data_<date>.log   (01a's own log)
#   tail -f logs/run_all_<date>.log         (orchestrator log)

set -euo pipefail

REPO=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval
cd "$REPO"
mkdir -p slurm/logs

module purge
module load R/4.4.2-gfbf-2024a
module load arrow-R/17.0.0.1-foss-2024a-R-4.4.2

echo "[full] start $(date)"
Rscript 00_run_all.R --with-pull "$@"
echo "[full] done $(date)"
