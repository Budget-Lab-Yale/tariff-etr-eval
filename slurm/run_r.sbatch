#!/usr/bin/env bash
#SBATCH --job-name=etr-r
#SBATCH --partition=day
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=slurm/logs/r-%j.log
#SBATCH --mail-type=END,FAIL

# R analysis pipeline (00_run_all.R): panel build -> ladder/decomposition/VMR
# -> figures. Consumes data/raw/ from the pull (slurm/run_pull.sbatch).
# Extra args pass through to the orchestrator, e.g.:
#   sbatch slurm/run_r.sbatch --skip-data

set -euo pipefail

REPO=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval
cd "$REPO"
mkdir -p slurm/logs

# 2024a stack to match run_full.sbatch (analysis packages verified 2026-06-12;
# the 2022b arrow-R module is broken -- see slurm/RUNBOOK.md)
module purge
module load R/4.4.2-gfbf-2024a
module load arrow-R/17.0.0.1-foss-2024a-R-4.4.2

echo "[r] start $(date)"
Rscript 00_run_all.R "$@"
echo "[r] done $(date)"
