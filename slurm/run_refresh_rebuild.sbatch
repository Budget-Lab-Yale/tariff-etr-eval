#!/usr/bin/env bash
#SBATCH --job-name=etr-refresh
#SBATCH --partition=day
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=96G
#SBATCH --time=06:00:00
#SBATCH --output=slurm/logs/refresh-%j.log
#SBATCH --mail-type=END,FAIL

# Re-run the eval against a NEW tracker publish without re-pulling IMDB.
#
# Stage A: code/01a_pull_raw_data.R --skip-imdb
#   Re-exports the tracker-derived raw data from the publish that
#   config/local_paths.yaml `tracker_data_dir` points at (default: .../latest):
#     3a snapshots, 3b 2024 weights, 3c daily ETRs + revision_dates,
#     3d-3g counterfactual scenario panels (day-weighted from 3a snapshots),
#     Section 4 Treasury revenue.
#   IMDB (Section 2) is skipped -- the cached data/raw/imdb_*.csv outputs are
#   reused, since IMDB import data is independent of the tracker rates.
#
# Stage B: 00_run_all.R  (01b panel -> 02a ladder -> 02b decomp -> 02c vmr
#   -> 03a/03b figures), rebuilding all tables/figures from the refreshed raw.
#
# Mem/time sized for the counterfactual rebuild + 01b/02c freads (96G; the
# 64G run_full config is tight when the day-weighted scenarios + panel are
# both resident). Progress:
#   tail -f logs/pull_raw_data_<date>.log   (Stage A)
#   tail -f logs/run_all_<date>.log         (Stage B)

set -euo pipefail

REPO=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval
cd "$REPO"
mkdir -p slurm/logs

module purge
module load R/4.4.2-gfbf-2024a
module load arrow-R/17.0.0.1-foss-2024a-R-4.4.2

echo "[refresh] start $(date)"
echo "[refresh] tracker publish -> $(readlink -f "$(awk '/tracker_data_dir:/{print $2}' config/local_paths.yaml)")"

echo "[refresh] Stage A: 01a --skip-imdb (refresh tracker + counterfactual raw)"
Rscript code/01a_pull_raw_data.R --skip-imdb

echo "[refresh] Stage B: 00_run_all.R (panel -> tables -> figures)"
Rscript 00_run_all.R

echo "[refresh] done $(date)"
echo "[refresh] run_meta:"
cat results/tables/run_meta.csv
