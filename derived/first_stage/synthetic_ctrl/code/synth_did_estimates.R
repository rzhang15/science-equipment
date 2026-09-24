library(tidyverse)
library(Synth)
library(haven)
library(fixest)
library(broom)
library(ggplot2)
library(parallel)
set.seed(8975)
N_CORES <- max(1, min(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", detectCores())), 16))

OUTPUT_DIR <- "../output/"
FIG_DIR    <- "../output/figures/"

TREAT_YEAR <- 2014
PRE_YEARS  <- 2010:2013
ALL_YEARS  <- 2010:2019
REF_PERIOD <- -1

OUTCOMES <- c(price = "avg_log_price", qty = "log_raw_qty", spend = "log_raw_spend")
YLABS    <- c(price = "Log Price", qty = "Log Quantity", spend = "Log Spending")

args <- commandArgs(trailingOnly = TRUE)
tags <- if (any(args %in% names(OUTCOMES))) intersect(args, names(OUTCOMES)) else names(OUTCOMES)
SUFFIX <- if ("all3" %in% args) "_all3" else ""
DATA_INPUT <- paste0("../external/samp/category_yr_tfidf", SUFFIX, ".dta")

panel <- read_dta(DATA_INPUT) %>%
  mutate(category = as.character(category),
         treated = as.numeric(treated)) %>%
  filter(year %in% ALL_YEARS) %>%
  group_by(category) %>%
  filter(n() == length(ALL_YEARS), !any(if_any(all_of(unname(OUTCOMES)), is.na))) %>%
  ungroup() %>%
  mutate(category_num = as.numeric(as.factor(category)))

treated_categories <- unique(panel$category[panel$treated == 1])
control_ids <- unique(panel$category_num[panel$treated == 0])
cat_lookup <- panel %>% distinct(category_num, category)

cat("Sample:", DATA_INPUT, "\n")
cat("Panel:", n_distinct(panel$category), "categories,",
    length(treated_categories), "treated,", length(control_ids), "controls\n")
cat("Cores:", N_CORES, "\n")

get_plot_data <- function(model, model_name) {
  broom::tidy(model, conf.int = TRUE, conf.level = 0.95) %>%
    filter(str_detect(term, "rel_year")) %>%
    mutate(rel = as.numeric(str_extract(term, "(?<=rel_year::)-?\\d+")),
           b = estimate, se = std.error, lb = conf.low, ub = conf.high,
           year = rel + TREAT_YEAR, model_label = model_name) %>%
    filter(!is.na(rel)) %>%
    select(model_label, rel, year, b, se, lb, ub)
}

fit_scm <- function(yvar, curr_id) {
  dp_out <- tryCatch(
    dataprep(
      foo = as.data.frame(panel),
      predictors = c("spend_2013"),
      predictors.op = "mean",
      time.predictors.prior = PRE_YEARS,
      special.predictors = lapply(PRE_YEARS, function(y) list(yvar, y, "mean")),
      dependent = yvar,
      unit.variable = "category_num",
      unit.names.variable = "category",
      time.variable = "year",
      treatment.identifier = curr_id,
      controls.identifier = control_ids,
      time.optimize.ssr = PRE_YEARS,
      time.plot = ALL_YEARS),
    error = function(e) NULL)
  if (is.null(dp_out)) return(NULL)
  s_out <- tryCatch(synth(dp_out), error = function(e) NULL)
  if (is.null(s_out)) return(NULL)
  list(dp = dp_out, s = s_out)
}

run_outcome <- function(tag) {
  yvar <- OUTCOMES[[tag]]
  ylab <- YLABS[[tag]]
  fig_dir <- paste0(FIG_DIR, tag, SUFFIX, "/")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  cat("\n==== Outcome:", yvar, "====\n")

  fit_one <- function(mkt) {
    curr_id <- cat_lookup$category_num[cat_lookup$category == mkt]
    fit <- fit_scm(yvar, curr_id)
    if (is.null(fit)) return(NULL)
    w <- pmax(as.numeric(fit$s$solution.w), 0)
    control_weights <- data.frame(category_num = as.numeric(rownames(fit$s$solution.w)),
                                  weight = w / sum(w))
    observed  <- fit$dp$Y1plot
    synthetic <- fit$dp$Y0plot %*% control_weights$weight
    pre <- as.character(PRE_YEARS)
    list(
      stack = bind_rows(data.frame(category_num = curr_id, weight = 1), control_weights) %>%
        mutate(stack_id = curr_id),
      fit = data.frame(treated_market = mkt,
                       pre_rmspe = sqrt(mean((observed[pre, ] - synthetic[pre, ])^2)),
                       n_donors = sum(control_weights$weight > 0.001)),
      plot_df = data.frame(year = as.numeric(rownames(observed)),
                           observed = as.numeric(observed),
                           synthetic = as.numeric(synthetic)))
  }

  results <- mclapply(treated_categories, fit_one, mc.cores = N_CORES, mc.set.seed = FALSE)
  names(results) <- treated_categories
  failed <- treated_categories[sapply(results, is.null)]
  if (length(failed) > 0) cat("  SCM failed:", paste(failed, collapse = ", "), "\n")
  results <- results[!sapply(results, is.null)]

  stack_list <- lapply(results, `[[`, "stack")
  fit_list   <- lapply(results, `[[`, "fit")

  for (mkt in names(results)) {
    clean_mkt <- gsub("[^[:alnum:]]", "_", mkt)
    plot_df <- results[[mkt]]$plot_df %>%
      pivot_longer(cols = c(observed, synthetic), names_to = "group", values_to = "y")
    p_trend <- ggplot(plot_df, aes(x = year, y = y, color = group, linetype = group)) +
      geom_line(linewidth = 1.2) + geom_point() +
      geom_vline(xintercept = TREAT_YEAR - 0.5, linetype = "dashed", color = "darkred") +
      scale_color_manual(values = c("observed" = "black", "synthetic" = "blue")) +
      scale_x_continuous(breaks = ALL_YEARS) +
      labs(title = paste("SCM Fit:", mkt), x = "Year", y = ylab) +
      theme_minimal() + theme(legend.position = "bottom", legend.title = element_blank())
    ggsave(paste0(fig_dir, "trend_", clean_mkt, ".pdf"), p_trend, width = 8, height = 5)
  }

  if (length(stack_list) == 0) stop(paste("No successful SCM fits for", yvar))

  write_csv(bind_rows(fit_list), paste0(OUTPUT_DIR, "scm_fit_summary_", tag, SUFFIX, ".csv"))
  weights_df <- bind_rows(stack_list)
  write_csv(weights_df %>% left_join(cat_lookup, by = "category_num") %>% filter(weight > 0.001),
            paste0(OUTPUT_DIR, "scm_weights_", tag, SUFFIX, ".csv"))

  synth_panel <- inner_join(panel, weights_df, by = "category_num", relationship = "many-to-many") %>%
    group_by(stack_id) %>%
    mutate(treated_spend_2013 = max(spend_2013[category_num == stack_id], na.rm = TRUE),
           composite_weight = weight * treated_spend_2013,
           is_treated_in_stack = (category_num == stack_id),
           rel_year = year - TREAT_YEAR) %>%
    ungroup() %>%
    filter(composite_weight > 0)
  write_dta(synth_panel, paste0(OUTPUT_DIR, "synth_stacked_panel_", tag, SUFFIX, ".dta"))

  est_pooled <- feols(as.formula(paste0(yvar, " ~ i(rel_year, is_treated_in_stack, ref = ", REF_PERIOD, ") | year + category_num")),
                      data = synth_panel, weights = ~composite_weight, cluster = ~stack_id)
  print(summary(est_pooled))

  stats_pooled <- get_plot_data(est_pooled, "Pooled")
  write_dta(stats_pooled, paste0(OUTPUT_DIR, "est_pooled_", tag, SUFFIX, ".dta"))

  p_pooled <- ggplot(stats_pooled, aes(x = rel, y = b)) +
    geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
    geom_vline(xintercept = REF_PERIOD, linetype = "dashed", color = "gray50") +
    geom_errorbar(aes(ymin = lb, ymax = ub), width = 0.2, linewidth = 0.8, color = "navy") +
    geom_point(size = 3, color = "navy") +
    labs(title = paste("Pooled Synthetic DiD:", ylab),
         subtitle = "Weighted by SCM weight x treated market 2013 spend",
         x = "Years Relative to Treatment", y = paste("Effect on", ylab)) +
    theme_minimal()
  ggsave(paste0(FIG_DIR, "plot_pooled_", tag, SUFFIX, ".pdf"), p_pooled, width = 10, height = 6)

  stats_pooled %>% mutate(outcome = ylab)
}

all_pooled <- bind_rows(lapply(tags, run_outcome))
write_dta(all_pooled, paste0(OUTPUT_DIR, "est_pooled_", paste(tags, collapse = "_"), SUFFIX, ".dta"))

p_all <- ggplot(all_pooled, aes(x = rel, y = b, color = outcome, group = outcome)) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
  geom_vline(xintercept = REF_PERIOD, linetype = "dashed", color = "gray50") +
  geom_point(size = 3, position = position_dodge(width = 0.5)) +
  geom_errorbar(aes(ymin = lb, ymax = ub), width = 0.2, linewidth = 0.8, position = position_dodge(width = 0.5)) +
  scale_color_manual(values = c("Log Price" = "#1f77b4", "Log Quantity" = "#e6550d", "Log Spending" = "#756bb1")) +
  labs(title = "Pooled Synthetic DiD Event Studies", x = "Years Relative to Treatment", y = "Estimate", color = NULL) +
  theme_minimal() + theme(legend.position = "bottom")
ggsave(paste0(FIG_DIR, "plot_pooled_", paste(tags, collapse = "_"), SUFFIX, ".pdf"), p_all, width = 10, height = 6)

cat("\nPipeline complete.\n")
