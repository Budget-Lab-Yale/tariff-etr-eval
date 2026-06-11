# Retired Stata pipeline

This is the original Stata implementation (00_etr_eval.do orchestrator,
steps 01–07 + utils, plus its R step-7 script `09_value_misreporting.R`),
retired on 2026-06-11 in favor of the pure-R pipeline at the repo root
(`00_run_all.R` → `code/`). It is preserved as the **golden reference** for
the port: `scripts/verify_r_port.R` compares the two implementations'
tables numerically.

To re-run it, use `sbatch slurm/run_stata.sbatch`, which materializes the
`stata-final` git tag (the last commit with this code at the repo root) into
a worktree with the data directories symlinked — the code expects
`00_etr_eval.do` at the repo root and resolves all paths from there.

Last golden run: 2026-06-11 (SLURM job 14658668, publish mode, 64 min).
Steps 1–5 completed and wrote all core tables; step 6
(`06_baseline_etr_diagnostic.do`) aborted with r(601) because its
publish-mode guard checks the wrong artifact — it imports
`counterfactual_usmca2024.csv` directly even when the S0 panel is absent.
Known bug, intentionally left unfixed here (the diagnostic's R port is
tracked in `docs/open_questions.md` #1); step 7 (VMR) did not run in that
job, but its successor `code/02c_vmr.R` reproduces the documented v1 build
exactly (identity residual 4.6e-15, 0.9% no-quantity share).
