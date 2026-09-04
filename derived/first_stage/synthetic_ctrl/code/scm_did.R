library(tidyverse)
library(haven)
library(fixest)
library(broom)
library(ggplot2)
library(stringr)
set.seed(8975)

setwd("~/sci_eq/derived/first_stage/synthetic_ctrl/code")
OUTPUT_DIR <- "../output/figures/"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

TREAT_YEAR <- 2014
REF_PERIOD <- -1

get_plot_data <- function(model, model_name = "Model") {
  df <- broom::tidy(model, conf.int = TRUE, conf.level = 0.95)
  
  df <- df %>%
    filter(str_detect(term, "rel_year")) %>%
    mutate(
      rel = as.numeric(str_extract(term, "(?<=rel_year::)-?\\d+")),
      b   = estimate,
      se  = std.error,
      ub  = conf.high,
      lb  = conf.low,
      year = rel + TREAT_YEAR,
      model_label = model_name
    ) %>%
    filter(!is.na(rel)) %>%
    select(model_label, rel, year, b, se, lb, ub)
  
  return(df)
}

cat("Loading stacked panel...\n")
synth_panel <- read_dta("../output/synth_stacked_panel.dta") %>%
  mutate(category = as.character(category))

cat("Stacked panel dimensions:", dim(synth_panel), "\n")
cat("Unique stacks:", n_distinct(synth_panel$stack_id), "\n\n")

synth_panel <- synth_panel %>%
  mutate(composite_weight = weight * treated_spend_2013) %>%
  filter(composite_weight > 0)

cat("After dropping zero-weight rows:", nrow(synth_panel), "\n\n")

cat("=== Per-Market Event Studies ===\n\n")

stack_ids <- unique(synth_panel$stack_id)

cat_lookup <- synth_panel %>% distinct(category_num, category)

local_results <- list()

for (sid in stack_ids) {
  mkt_name <- cat_lookup$category[cat_lookup$category_num == sid]
  if (length(mkt_name) == 0) mkt_name <- paste0("stack_", sid)
  mkt_name <- mkt_name[1]
  clean_name <- str_replace_all(mkt_name, "[^a-zA-Z0-9_-]", "_")
  
  cat("Event study for:", mkt_name, "... ")
  
  local_panel <- synth_panel %>%
    filter(stack_id == sid)
  
  est <- tryCatch({
    feols(
      avg_log_price ~ i(rel_year, is_treated_in_stack, ref = REF_PERIOD) |
        year + category_num,
      data = local_panel,
      weights = ~weight,
      cluster = ~category_num
    )
  }, error = function(e) {
    message("FAILED: ", e$message)
    return(NULL)
  })
  
  if (is.null(est)) next
  
  stats_df <- tryCatch({
    get_plot_data(est, model_name = mkt_name)
  }, error = function(e) {
    message("Coefficient extraction failed: ", e$message)
    return(NULL)
  })
  
  if (is.null(stats_df) || nrow(stats_df) == 0) {
    cat("no coefficients extracted\n")
    next
  }
  
  local_results[[mkt_name]] <- stats_df
  
  tryCatch({
    write_dta(stats_df, paste0(OUTPUT_DIR, "est_", clean_name, ".dta"))
  }, error = function(e) {
    message("Could not save .dta: ", e$message)
  })
  
  tryCatch({
    p <- ggplot(stats_df, aes(x = rel, y = b)) +
      geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
      geom_vline(xintercept = REF_PERIOD, linetype = "dashed", color = "gray50") +
      geom_errorbar(aes(ymin = lb, ymax = ub),
                    width = 0.2, linewidth = 0.8, color = "navy") +
      geom_point(size = 3, color = "navy") +
      labs(
        title = paste("Event Study:", mkt_name),
        subtitle = paste("Ref period:", REF_PERIOD, "| Clustered by category"),
        x = "Years Relative to Treatment",
        y = "Effect on Log Price"
      ) +
      theme_minimal(base_size = 12) +
      theme(plot.title = element_text(face = "bold"))
    
    ggsave(paste0(OUTPUT_DIR, "coef_", clean_name, ".pdf"),
           plot = p, width = 8, height = 5)
    print(p)
  }, error = function(e) {
    message("Plot failed: ", e$message)
  })
  
  cat("OK\n")
}

cat("\nLocal event studies completed:", length(local_results), "/", length(stack_ids), "\n\n")

cat("=== Global Event Studies ===\n\n")

cat("Running pooled model...\n")
est_pooled <- tryCatch({
  feols(
    avg_log_price ~ i(rel_year, is_treated_in_stack, ref = REF_PERIOD) |
      year + category_num,
    data = synth_panel,
    weights = ~composite_weight,
    cluster = ~stack_id
  )
}, error = function(e) {
  message("Pooled model failed: ", e$message)
  NULL
})

cat("Running stacked model...\n")
est_stacked <- tryCatch({
  feols(
    avg_log_price ~ i(rel_year, is_treated_in_stack, ref = REF_PERIOD) |
      stack_id^year + stack_id^category_num,
    data = synth_panel,
    weights = ~composite_weight,
    cluster = ~stack_id
  )
}, error = function(e) {
  message("Stacked model failed: ", e$message)
  NULL
})

compare_list <- list()

if (!is.null(est_pooled)) {
  cat("Pooled model summary:\n")
  print(summary(est_pooled))
  stats_pooled <- get_plot_data(est_pooled, "Pooled")
  write_dta(stats_pooled, "../output/est_pooled.dta")
  compare_list[["Pooled"]] <- stats_pooled
  cat("\n")
}

if (!is.null(est_stacked)) {
  cat("Stacked model summary:\n")
  print(summary(est_stacked))
  stats_stacked <- get_plot_data(est_stacked, "Stacked")
  write_dta(stats_stacked, "../output/est_stacked.dta")
  compare_list[["Stacked"]] <- stats_stacked
  cat("\n")
}

if (length(compare_list) > 0) {
  compare_df <- bind_rows(compare_list)
  
  p_compare <- ggplot(compare_df, aes(x = rel, y = b, color = model_label,
                                      group = model_label)) +
    geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
    geom_vline(xintercept = REF_PERIOD, linetype = "dashed", color = "gray50") +
    geom_point(size = 3, position = position_dodge(width = 0.4)) +
    geom_line(position = position_dodge(width = 0.4), alpha = 0.3) +
    geom_errorbar(aes(ymin = lb, ymax = ub),
                  width = 0.2, linewidth = 0.8,
                  position = position_dodge(width = 0.4)) +
    scale_color_manual(values = c("Pooled" = "firebrick", "Stacked" = "navy")) +
    labs(
      title = "DiD Event Study: Pooled vs. Stacked",
      subtitle = "Weighted by SCM weights * treated market spend",
      x = "Years Relative to Treatment",
      y = "Effect on Log Price",
      color = "Specification"
    ) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold"))
  
  ggsave(paste0(OUTPUT_DIR, "plot_pooled_vs_stacked.pdf"),
         plot = p_compare, width = 10, height = 6)
  print(p_compare)
  
  cat("Saved pooled vs. stacked comparison plot.\n")
}

if (length(local_results) > 0) {
  cat("\n=== Treatment Effect Summary (Post-Treatment Average) ===\n")
  
  effect_summary <- map_dfr(local_results, function(df) {
    post_df <- df %>% filter(rel >= 0)
    data.frame(
      market = df$model_label[1],
      avg_effect = mean(post_df$b, na.rm = TRUE),
      min_effect = min(post_df$b, na.rm = TRUE),
      max_effect = max(post_df$b, na.rm = TRUE),
      n_post_periods = nrow(post_df)
    )
  }) %>%
    arrange(avg_effect)
  
  print(effect_summary)
  write_csv(effect_summary, "../output/treatment_effect_summary.csv")
}

cat("\n02_scm_did.R complete.\n")
