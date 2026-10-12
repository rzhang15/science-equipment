# strt_to_end

End-to-end runners. Each subfolder chains an existing sequence of `derived/` and
`analysis/` modules, running each module exactly as its own `make.py` would
(clear output/temp, link externals from `links.txt`, run the scripts), and runs
independent branches concurrently.

`run_module.py` (this folder) is the generic non-interactive module runner every chain uses (see its docstring).

## first_stage/

```
submit_all.sh [FIRST_STAGE]     SLURM: one job per stage, chained with --dependency
run_local.sh  [FIRST_STAGE] [N] no SLURM: same order, branches backgrounded, N placebo_sd chunks
status.sh                       queue + recent job states + tail of any failed stage log
stages/*.sbatch                 one stage each; runnable alone: sbatch stages/07_first_stage.sbatch
env.sh                          modules, PATH, REPO
logs/                           slurm / local logs
```

Pipeline (numbers = stage; letters = run concurrently):

```
01 merge_price_data
02 fuzzy_match_suppliers          match.py + final_clean.do
03 select_categories
04 make_mkt_panel
05a match_control (R)   05b synthetic_ctrl (R, 16 cores)   05c placebo_dist   05d placebo_sd prep (R draws + Stata prep)
06a matched_panel       |                                  06b placebo_first_stage   06c placebo_sd chunks (array 1-10)
07 analysis/first_stage  <- 06a + 05b
08a placebo_overlay <- 07 + 06b      08b placebo_sd combine + figures <- 07 + 06c
```

Upstream inputs assumed already built (not part of this chain):
`derived/process_foias/prdct_classification/output/umich_supplier`,
`derived/govspend/make_panel/output`, `derived/exposure_msr/output`.

`analysis/placebo_sd/code/analysis.do` accepts `prep | chunk <id> <lo> <hi> | combine`
as do-file arguments; with no arguments it behaves as before (`python make.py`).

Shell aliases (in ~/.bashrc): `fs_run` = submit_all.sh, `fs_status` = status.sh, `fs_logs` = cd logs.

Restart from a later stage: `./submit_all.sh 05` skips 01-04 and submits the rest.
Resource requests live in each `stages/*.sbatch` header.

## reduced_form/

```
submit_all.sh [FIRST_STAGE]     SLURM: one job per stage, chained with --dependency
run_local.sh  [FIRST_STAGE]     no SLURM: same order, the 03 stages backgrounded
status.sh                       queue + recent job states + tail of any failed stage log
stages/*.sbatch                 one stage each; runnable alone: sbatch stages/03b_rf_main.sbatch
```

```
01 derived/reduced_form/rf_sample     PI x year panel, exit panels, exposure inputs (output/prepped_samples)
02 derived/reduced_form/rf_groups     PI-level heterogeneity groups + unmasked NIH outcomes      <- 01
03a analysis/rf_descriptives          exposure densities, sumstats, balance, largest unis         <- 02
03b analysis/rf_main                  event studies, pooled DiD, PPML specs, rf_main.tex          <- 01
03c analysis/rf_robustness            placebo years, trimming, exposure variants, functional form <- 01
03d analysis/rf_exit                  exit regressions + exit.tex                                 <- 01
03e analysis/rf_output_loss           predicted output loss by year / cluster / PI                <- 01
03f analysis/rf_het_splits            group-split event studies, horse race, coefplots, het table <- 02
03g analysis/rf_het_career            career-stage descriptives, age gradient, matched comparison <- 02
```

Upstream inputs assumed already built: `derived/openalex/*`, `derived/exposure_msr`, `derived/nih/match_pi_athr`,
`derived/inst_chars`, `analysis/first_stage/output` (betas). Shared settings live in `lib/globals.txt`.
