library(tidyverse)
library(haven)
library(synthdid)
library(parallel)
BASE_SEED <- 8975L
RNGkind("L'Ecuyer-CMRG")
set.seed(BASE_SEED)
N_CORES <- max(1, min(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", detectCores())), 16))

OUTPUT_DIR <- "../output/"
FIG_DIR    <- "../output/figures/"

TREAT_YEAR <- 2014
PRE_YEARS  <- 2010:2013
ALL_YEARS  <- 2010:2019
T0 <- length(PRE_YEARS)
REF_PERIOD <- -1

OUTCOMES <- c(price = "avg_log_price", qty = "log_raw_qty", spend = "log_raw_spend")
YLABS    <- c(price = "Log Price", qty = "Log Quantity", spend = "Log Spending")
VERSIONS <- c(spend_weighted = "Spend-weighted treated", equal_weighted = "Equal-weighted treated")
N_PLACEBO <- 200
N_BOOT    <- 200

args <- commandArgs(trailingOnly = TRUE)
tags <- if (any(args %in% names(OUTCOMES))) intersect(args, names(OUTCOMES)) else names(OUTCOMES)
SUFFIXES <- if ("all3" %in% args) "_all3" else c("", "_all3")

load_panel <- function(suffix) {
  data_input <- paste0("../external/samp/category_yr_tfidf", suffix, ".dta")
  eligible_categories <- read_dta(paste0("../external/samp/category_hhi_tfidf", suffix, ".dta")) %>%
    filter(first_stage_sample == 1) %>% select(category)
  panel <- read_dta(data_input) %>%
    mutate(category = as.character(category),
           treated = as.numeric(treated)) %>%
    semi_join(eligible_categories, by = "category") %>%
    filter(year %in% ALL_YEARS) %>%
    group_by(category) %>%
    filter(n() == length(ALL_YEARS), !any(if_any(all_of(unname(OUTCOMES)), is.na))) %>%
    ungroup()
  cat("Sample:", data_input, "\n")
  cat("Panel:", n_distinct(panel$category), "categories,",
      sum(panel$treated == 1 & panel$year == TREAT_YEAR), "treated,",
      sum(panel$treated == 0 & panel$year == TREAT_YEAR), "controls\n")
  panel
}
cat("Cores:", N_CORES, "\n")

outcome_matrix <- function(panel, yvar, units) {
  wide <- panel %>%
    select(category, year, all_of(yvar)) %>%
    pivot_wider(names_from = year, values_from = all_of(yvar))
  Y <- as.matrix(wide[match(units, wide$category), as.character(ALL_YEARS)])
  rownames(Y) <- units
  Y
}

sdid_fit <- function(Y, N0) {
  est <- synthdid_estimate(Y, N0, T0)
  w <- attr(est, "weights")
  y_tr <- colMeans(Y[(N0 + 1):nrow(Y), , drop = FALSE])
  gap <- y_tr - as.numeric(t(Y[1:N0, , drop = FALSE]) %*% w$omega)
  list(tau = as.numeric(est), est = est, omega = setNames(w$omega, rownames(Y)[1:N0]),
       lambda = setNames(w$lambda, PRE_YEARS), effect = gap - sum(w$lambda * gap[1:T0]))
}

aggregate_treated <- function(Y_tr, shares) rbind(as.numeric(t(Y_tr) %*% shares))

placebo_draws <- function(Y0, n_tr, shares, seed) {
  N0 <- nrow(Y0)
  mclapply(seq_len(N_PLACEBO), function(b) {
    set.seed(seed + b)
    idx <- sample(N0, n_tr)
    Y_pl <- if (is.null(shares)) rbind(Y0[-idx, , drop = FALSE], Y0[idx, , drop = FALSE])
            else rbind(Y0[-idx, , drop = FALSE], aggregate_treated(Y0[idx, , drop = FALSE], shares))
    f <- sdid_fit(Y_pl, N0 - n_tr)
    c(tau = f$tau, f$effect)
  }, mc.cores = N_CORES, mc.set.seed = FALSE)
}

run_outcome <- function(tag, smp) {
  # Fix seeds by sample, outcome, method, and draw, independent of core count
  # and whether outcomes/samples are requested together or separately.
  draw_seed <- BASE_SEED + 100000L * match(smp$suffix, c("", "_all3")) +
    10000L * match(tag, names(OUTCOMES))
  set.seed(draw_seed)
  yvar <- OUTCOMES[[tag]]
  ylab <- YLABS[[tag]]
  cat("\n==== Outcome:", yvar, "====\n")
  Y0   <- outcome_matrix(smp$panel, yvar, smp$controls)
  Y_tr <- outcome_matrix(smp$panel, yvar, smp$treated)
  N0 <- nrow(Y0); n_tr <- nrow(Y_tr)

  fits <- list(
    spend_weighted = sdid_fit(rbind(Y0, aggregate_treated(Y_tr, smp$shares)), N0),
    equal_weighted = sdid_fit(rbind(Y0, Y_tr), N0))

  draws <- list(
    spend_weighted = placebo_draws(Y0, n_tr, smp$shares, draw_seed + 1000L),
    equal_weighted = placebo_draws(Y0, n_tr, NULL, draw_seed + 2000L))

  boot_w <- unlist(mclapply(seq_len(N_BOOT), function(b) {
    set.seed(draw_seed + 3000L + b)
    idx <- sample(n_tr, n_tr, replace = TRUE)
    sh <- smp$shares[idx] / sum(smp$shares[idx])
    sdid_fit(rbind(Y0, aggregate_treated(Y_tr[idx, , drop = FALSE], sh)), N0)$tau
  }, mc.cores = N_CORES, mc.set.seed = FALSE))
  set.seed(draw_seed + 4000L)
  se_boot <- c(spend_weighted = sd(boot_w),
               equal_weighted = sqrt(as.numeric(vcov(fits$equal_weighted$est, method = "bootstrap", replications = N_BOOT))))

  summary_df <- bind_rows(lapply(names(VERSIONS), function(v) {
    pl <- do.call(rbind, draws[[v]])
    data.frame(outcome = yvar, version = v, tau = fits[[v]]$tau,
               se_placebo = sd(pl[, "tau"]), se_bootstrap = se_boot[[v]],
               n_treated = n_tr, n_controls = N0, N = (N0 + n_tr) * length(ALL_YEARS),
               n_donors = sum(fits[[v]]$omega > 0.001))
  }))
  print(summary_df, digits = 3)

  stats <- bind_rows(lapply(names(VERSIONS), function(v) {
    pl <- do.call(rbind, draws[[v]])[, -1, drop = FALSE]
    data.frame(model_label = VERSIONS[[v]], version = v, year = ALL_YEARS, rel = ALL_YEARS - TREAT_YEAR,
               b = fits[[v]]$effect, se = apply(pl, 2, sd)) %>%
      mutate(lb = b - 1.96 * se, ub = b + 1.96 * se)
  }))
  write_dta(stats, paste0(OUTPUT_DIR, "est_pooled_", tag, smp$suffix, ".dta"))

  weights_df <- bind_rows(lapply(names(VERSIONS), function(v)
    bind_rows(data.frame(version = v, type = "omega", unit = names(fits[[v]]$omega), weight = as.numeric(fits[[v]]$omega)),
              data.frame(version = v, type = "lambda", unit = names(fits[[v]]$lambda), weight = as.numeric(fits[[v]]$lambda)))))
  write_csv(weights_df %>% filter(weight > 0.001), paste0(OUTPUT_DIR, "sdid_weights_", tag, smp$suffix, ".csv"))

  pdf(paste0(FIG_DIR, "plot_trajectory_", tag, smp$suffix, ".pdf"), width = 10, height = 6)
  print(synthdid_plot(fits$spend_weighted$est, overlay = 1) +
          labs(title = paste("Synthetic DiD:", ylab, "(spend-weighted treated)"), y = ylab))
  print(synthdid_plot(fits$equal_weighted$est, overlay = 1) +
          labs(title = paste("Synthetic DiD:", ylab, "(equal-weighted treated)"), y = ylab))
  dev.off()

  p_pooled <- ggplot(stats, aes(x = rel, y = b, color = model_label, group = model_label)) +
    geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
    geom_vline(xintercept = TREAT_YEAR - 0.5 - TREAT_YEAR, linetype = "dashed", color = "gray50") +
    geom_errorbar(aes(ymin = lb, ymax = ub), width = 0.2, linewidth = 0.8, position = position_dodge(width = 0.4)) +
    geom_point(size = 3, position = position_dodge(width = 0.4)) +
    scale_color_manual(values = c("Spend-weighted treated" = "navy", "Equal-weighted treated" = "#e6550d")) +
    labs(title = paste("Synthetic DiD:", ylab),
         subtitle = paste0("Per-year effects relative to time-weighted pre-period; placebo 95% CI. tau = ",
                           sprintf("%.3f (%.3f)", fits$spend_weighted$tau, summary_df$se_placebo[1]), " spend-weighted, ",
                           sprintf("%.3f (%.3f)", fits$equal_weighted$tau, summary_df$se_placebo[2]), " equal-weighted"),
         x = "Years Relative to Treatment", y = paste("Effect on", ylab), color = NULL) +
    theme_minimal() + theme(legend.position = "bottom")
  ggsave(paste0(FIG_DIR, "plot_pooled_", tag, smp$suffix, ".pdf"), p_pooled, width = 10, height = 6)

  list(summary = summary_df, stats = stats %>% mutate(outcome = ylab))
}

run_sample <- function(suffix) {
  panel <- load_panel(suffix)
  spend <- panel %>% filter(year == 2013) %>% distinct(category, treated, spend_2013)
  treated <- sort(spend$category[spend$treated == 1])
  smp <- list(suffix = suffix, panel = panel,
              treated = treated,
              controls = sort(spend$category[spend$treated == 0]),
              shares = with(spend[match(treated, spend$category), ], spend_2013 / sum(spend_2013)))

  res <- lapply(tags, run_outcome, smp = smp)
  write_dta(bind_rows(lapply(res, `[[`, "summary")), paste0(OUTPUT_DIR, "synth_estimates", suffix, ".dta"))
  all_stats <- bind_rows(lapply(res, `[[`, "stats"))
  write_dta(all_stats, paste0(OUTPUT_DIR, "est_pooled_", paste(tags, collapse = "_"), suffix, ".dta"))

  p_all <- ggplot(all_stats %>% filter(version == "spend_weighted"), aes(x = rel, y = b, color = outcome, group = outcome)) +
    geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
    geom_point(size = 3, position = position_dodge(width = 0.5)) +
    geom_errorbar(aes(ymin = lb, ymax = ub), width = 0.2, linewidth = 0.8, position = position_dodge(width = 0.5)) +
    scale_color_manual(values = c("Log Price" = "#1f77b4", "Log Quantity" = "#e6550d", "Log Spending" = "#756bb1")) +
    labs(title = "Synthetic DiD event studies (spend-weighted treated, placebo 95% CI)",
         x = "Years Relative to Treatment", y = "Estimate", color = NULL) +
    theme_minimal() + theme(legend.position = "bottom")
  ggsave(paste0(FIG_DIR, "plot_pooled_", paste(tags, collapse = "_"), suffix, ".pdf"), p_all, width = 10, height = 6)
}

for (suffix in SUFFIXES) run_sample(suffix)

cat("\nPipeline complete.\n")
