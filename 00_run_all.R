# =============================================================================
# 00_run_all.R — tariff-etr-eval pipeline orchestrator
# =============================================================================
# Runs the R pipeline end to end (structure mirrors tariff-etr-adj):
#
#   step 01a  code/01a_pull_raw_data.R      raw data pull (off by default --
#                                           hours; run on demand, see README)
#   step 01b  code/01b_build_panel.R        data/raw CSVs -> data/processed/panel.rds
#   step 02a  code/02a_ladder.R             tiers S0-S4 + T, channel gaps, strips
#   step 02b  code/02b_decomposition.R      Shapley diversion + attributions + cmp_*
#   step 02c  code/02c_vmr.R                value-misreporting decomposition
#   step 03a  code/03a_figures_framework.R  framework + VMR figures (CSV-only inputs)
#   step 03b  code/03b_figures_baseline.R   paper baseline figures
#
# Usage:
#   Rscript 00_run_all.R                  # 01b -> 03b (the default)
#   Rscript 00_run_all.R --with-pull      # also run the raw pull first
#   Rscript 00_run_all.R --skip-data      # 02a -> 03b (reuse panel.rds)
#   Rscript 00_run_all.R --figures-only   # 03a + 03b only
#
# Memory: 01b freads a 73M-row rate panel and 02c a 4.5M-row IMDB table --
# run via slurm/run_r.sbatch on a compute node (see slurm/RUNBOOK.md).
# The Stata predecessor of this pipeline is preserved in archive/stata/.
# =============================================================================

here::i_am("00_run_all.R")
setwd(here::here())

args <- commandArgs(trailingOnly = TRUE)
with_pull    <- "--with-pull"    %in% args
skip_data    <- "--skip-data"    %in% args
figures_only <- "--figures-only" %in% args

dir.create("logs", showWarnings = FALSE)
log_path <- file.path("logs",
                      sprintf("run_all_%s.log", format(Sys.Date(), "%Y-%m-%d")))
log_con <- file(log_path, open = "at")
say <- function(...) {
  line <- sprintf(...)
  cat(line, "\n")
  writeLines(paste(format(Sys.time(), "%H:%M:%S"), line), log_con)
  flush(log_con)
}

run_step <- function(script) {
  say("=== %s ===", script)
  t0 <- Sys.time()
  status <- system2("Rscript", script)
  if (status != 0) stop(script, " failed with exit status ", status)
  say("=== %s done (%.1f min) ===", script,
      as.numeric(difftime(Sys.time(), t0, units = "mins")))
}

say("tariff-etr-eval pipeline start (%s)",
    paste(c("default", args), collapse = " "))

steps <- c(
  if (with_pull) "code/01a_pull_raw_data.R",
  if (!skip_data && !figures_only) "code/01b_build_panel.R",
  if (!figures_only) c("code/02a_ladder.R", "code/02b_decomposition.R",
                       "code/02c_vmr.R"),
  "code/03a_figures_framework.R",
  "code/03b_figures_baseline.R")
for (s in steps) run_step(s)

say("pipeline complete. Tables: results/tables/  Figures: results/figures/")
close(log_con)
