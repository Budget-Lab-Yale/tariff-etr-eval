#!/usr/bin/env bash
#SBATCH --job-name=etr-pull
#SBATCH --partition=day
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=slurm/logs/pull-%j.log
#SBATCH --mail-type=END,FAIL

# Stage 1 -- R data assembly (code/R/00_pull_raw_data.R).
#
# Publish mode (default): snapshots + daily ETRs + h2avg counterfactual come
# from the shared tracker publish (config/local_paths.yaml tracker_data_dir);
# IMDB HS10 bulk is downloaded/parsed from Census; Treasury revenue from the
# vendored resources/treasury_revenue.csv. Produces the publish-mode S1-S4+T
# inputs in data/raw/ (S0 / usmca_monthly need a DataWeb token and are skipped).
#
# Time/mem: IMDB download+parse for ~17 months dominates (memory-heavy, ~10-20GB
# peak); the 2024 import-weight self-build adds ~10-30 min if no RDS is cached.
# Network-bound otherwise. First pass can be several hours; cached reruns faster.
#
# Progress: tail -f logs/pull_raw_data_<date>.log   (the R script's own log)

set -euo pipefail

REPO=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval
cd "$REPO"
mkdir -p slurm/logs

module purge
# R 4.4.2 / foss-2024a -- matches the tracker publish's own build stack
# (arrow 17.0.0.1, R 4.4.2). The 2022b arrow-R/16.1.0 module is broken
# (missing libarrow_dataset.so.1601); this 2024a stack loads arrow cleanly
# and has all required packages (httr/jsonlite/dplyr/readr/here/stringi/yaml/
# tidyverse). Verified on a1130u05n02, 2026-06-08.
module load R/4.4.2-gfbf-2024a
module load arrow-R/17.0.0.1-foss-2024a-R-4.4.2

echo "[pull] $(Rscript --version 2>&1 | head -1)"
echo "[pull] arrow check:"
Rscript -e 'q(status = !requireNamespace("arrow", quietly=TRUE))' \
  && echo "  arrow OK" || { echo "  ERROR: arrow not loadable"; exit 1; }
echo "[pull] start $(date)"

# Default flags = publish mode + IMDB + counterfactual + Treasury.
# Add --refresh-tracker only with a DataWeb token (rebuilds USMCA scenarios / S0).
Rscript code/R/00_pull_raw_data.R

echo "[pull] done $(date)"
echo "[pull] data/raw contents:"
ls -1 data/raw/*.csv 2>/dev/null | sed 's#.*/##'
