library(tidyverse)
library(fixest)
library(MatchIt)
library(cobalt)
library(ggplot2)
library(here)
library(haven)
library(stringr)

setwd("~/sci_eq/derived/first_stage/match_control/code")
dir.create("../output/figures_optimal", recursive = TRUE, showWarnings = FALSE)
dir.create("../output/balance_plots_optimal", recursive = TRUE, showWarnings = FALSE)

COVARIATES_TO_USE <- c("coef_log_spend")
VARS_TO_CHECK <- c(COVARIATES_TO_USE)

OUTCOME_VARS <- c("avg_log_price")

OPTIMAL_RATIO <- 2
cat("Running optimal matching with a fixed ratio of:", OPTIMAL_RATIO, "\n")

panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

all_data_pre <- panel %>%
  filter(year <= 2013)

trends_pre <- all_data_pre %>%
  group_by(category, treated) %>%
  summarise(
    coef_price = possibly(~coef(lm(raw_price ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    coef_log_price = possibly(~coef(lm(avg_log_price ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    coef_spend = possibly(~coef(lm(raw_spend ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    coef_log_spend = possibly(~coef(lm(avg_log_spend ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    .groups = "drop"
  )

data_wide_raw <- all_data_pre %>%
  pivot_wider(
    names_from = year,
    names_sep = "_",
    id_cols = c(category, treated, spend_2013 ),
    values_from = c(avg_log_price, avg_log_spend, num_suppliers, obs_cnt, raw_spend, raw_price, raw_qty)
  ) %>%
  mutate(
    w_avg_log_price_2013 = avg_log_price_2013 * spend_2013,
    w_avg_log_price_2012 = avg_log_price_2012 * spend_2013,
    w_avg_log_price_2011 = avg_log_price_2011 * spend_2013,
    w_avg_log_price_2010 = avg_log_price_2010 * spend_2013,
    w_avg_log_spend_2013 = avg_log_spend_2013 * spend_2013,
    w_avg_log_spend_2012 = avg_log_spend_2012 * spend_2013,
    w_avg_log_spend_2011 = avg_log_spend_2011 * spend_2013,
    w_avg_log_spend_2010 = avg_log_spend_2010 * spend_2013
  )

data_wide_raw <- left_join(data_wide_raw, trends_pre, by = c("category", "treated"))

data_wide <- data_wide_raw %>%
  drop_na(all_of(VARS_TO_CHECK))

cat("Dimensions of raw wide data:", dim(data_wide_raw), "\n")
cat("Dimensions after targeted NA removal:", dim(data_wide), "\n")

covariates_formula <- as.formula(paste("treated ~", paste(COVARIATES_TO_USE, collapse = " + ")))
treated_markets <- unique(data_wide$category[data_wide$treated == 1])

cat("\n\n====================================================\n")
cat("Found", length(treated_markets), "treated markets to process after cleaning.\n")
cat("====================================================\n\n")

match_pairs_list <- list()

for (category_id in treated_markets) {
  cat("\nProcessing treated market:", category_id, "\n")
  
  temp_data <- data_wide %>%
    filter(category == category_id | treated == 0)
  
  cat("--- Diagnostic summary for market:", category_id, "---\n")
  print(
    temp_data %>%
      group_by(treated) %>%
      summarise(count = n(), across(all_of(COVARIATES_TO_USE), list(mean = mean, sd = sd))) %>%
      as.data.frame()
  )
  cat("--------------------------------------------------\n")
  
  cat("--- Performing Optimal Matching for", category_id,
      "with ratio =", OPTIMAL_RATIO, "---\n")
  
  current_model <- tryCatch({
    matchit(
      formula = covariates_formula,
      method = "optimal",
      data = temp_data,
      ratio = OPTIMAL_RATIO,
      replace = TRUE,
      s.weights = "obs_cnt"
    )
  }, error = function(e) { message("Optimal matching failed: ", e$message); return(NULL) })
  
  if (is.null(current_model)) {
    cat("Matching failed for market", category_id, ". Skipping.\n")
    next
  }
  
  match_summary <- summary(current_model, un = FALSE)
  num_controls_matched <- match_summary$nn["Control", "Matched"]
  
  if (num_controls_matched == 0) {
    message("Optimal matching found NO valid controls for market ", category_id)
    next
  }
  
  mean_smd <- mean(abs(match_summary$sum.matched[, "Std. Mean Diff."]), na.rm = TRUE)
  cat("--- Match successful for", category_id, ": Mean SMD =", round(mean_smd, 4), "---\n")
  
  balance_plot_title <- paste("Covariate Balance (Optimal Match) for Market:", category_id,
                              "\n(Ratio=", OPTIMAL_RATIO, ")")
  
  balance_plot <- love.plot(current_model, binary = "std", thresholds = c(m = .1),
                            title = balance_plot_title)
  
  ggsave(filename = paste0("../output/balance_plots_optimal/balance_", category_id, ".pdf"),
         plot = balance_plot, width = 7, height = 6)
  
  print(balance_plot)
  
  match_data <- match.data(current_model)
  if (nrow(match_data) <= 1) {
    message("No valid control data found for market ", category_id)
    next
  }
  
  treated_category <- unique(match_data$category[match_data$treated == 1])
  matched_control_categories <- unique(match_data$category[match_data$treated == 0])
  
  match_pairs_list[[category_id]] <- data.frame(
    treated_market = treated_category,
    control_market = matched_control_categories
  )
  
  for (outcome_var in OUTCOME_VARS) {
    cat("--- Generating plot for outcome:", outcome_var, "\n")
    
    outcome_trends <- panel %>%
      select(category, year, treated, spend_2013, all_of(outcome_var)) %>%
      group_by(category) %>%
      mutate(outcome_adj = .data[[outcome_var]] - .data[[outcome_var]][year == 2013]) %>%
      ungroup()
    
    treated_plot_data <- outcome_trends %>%
      filter(category == treated_category) %>%
      mutate(group_label = paste("Treated:", treated_category))
    
    avg_control_plot_data <- outcome_trends %>%
      filter(category %in% matched_control_categories) %>%
      group_by(year) %>%
      summarise(outcome_adj = weighted.mean(outcome_adj, w = spend_2013, na.rm = TRUE), .groups = "drop") %>%
      mutate(group_label = paste("Avg. Control (Weighted):", paste(matched_control_categories, collapse = ", ")))
    
    plot_data_final <- bind_rows(treated_plot_data, avg_control_plot_data)
    
    plot_y_label <- str_to_title(str_replace_all(outcome_var, "_", " "))
    plot_title <- paste(plot_y_label, "Trend (Optimal Match):", treated_category)
    
    p <- ggplot(plot_data_final, aes(x = year, y = outcome_adj, color = group_label)) +
      geom_line(linewidth = 1) +
      geom_point() +
      geom_vline(xintercept = 2013.5, linetype = "dashed", color = "gray40") +
      labs(
        title = plot_title,
        subtitle = "Treated vs. Weighted Average of Matched Control Markets",
        x = "Year",
        y = paste(plot_y_label, "(Adjusted to 2013)"),
        color = "Market Group"
      ) +
      theme_minimal(base_size = 12) +
      scale_x_continuous(breaks = seq(2010, 2019, 1)) +
      theme(legend.position = "bottom",
            plot.title = element_text(face = "bold"),
            legend.text = element_text(size = 8))
    
    ggsave(paste0("../output/figures_optimal/", outcome_var, "_trends_", treated_category, ".pdf"), plot = p, width = 10, height = 7)
    
    print(p)
    
    cat("Saved and displayed", outcome_var, "trend plot for", category_id, "\n")
  }
}

if (length(match_pairs_list) > 0) {
  match_pairs <- do.call(rbind, match_pairs_list)
  cat("\nSuccessfully matched pairs (using Optimal Match):\n")
  print(match_pairs)
  write_csv(match_pairs, "../output/match_pairs_optimal.csv")
} else {
  cat("\nNo successful matches were made.\n")
}
