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

# Golden-reference run of the RETIRED Stata pipeline (archive/stata/), used to
# validate the R port (scripts/verify_r_port.R). The Stata code expects to run
# from a repo root that still has 00_etr_eval.do at the top level, so this
# script materializes the `stata-final` tag into a worktree and symlinks the
# data directories into it. Results land in the worktree's results/tables.
#
#   sbatch slurm/run_stata.sbatch
#   cp -a <worktree>/results results_stata_golden   # then snapshot + verify

set -euo pipefail

REPO=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-etr-eval
WT=$REPO/../tariff-etr-eval-stata-golden
cd "$REPO"
mkdir -p slurm/logs

if [ ! -d "$WT" ]; then
  git worktree add "$WT" stata-final
fi
cd "$WT"
for d in raw working imdb weights; do
  [ -L "data/$d" ] || { rm -rf "data/$d"; ln -s "$REPO/data/$d" "data/$d"; }
done
mkdir -p results/figures results/tables logs slurm/logs

module purge
module load Stata/19
module load R/4.4.1-foss-2022b   # orchestrator step 7 shells out to Rscript

echo "[stata] start $(date) in $WT"
stata-mp -b do 00_etr_eval.do
echo "[stata] done $(date)"
ls -1 results/tables/*.csv 2>/dev/null | sed 's#.*/##'
