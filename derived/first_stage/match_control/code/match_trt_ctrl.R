# Load necessary libraries
library(tidyverse)
library(fixest)
library(MatchIt)
library(cobalt)
library(ggplot2)
library(here)
library(haven)
library(stringr) 

# Set working directory and create output folders
setwd("~/sci_eq/derived/first_stage/match_control/code")
dir.create("../output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("../output/balance_plots", recursive = TRUE, showWarnings = FALSE)
dir.create("../output/grid_search_logs", recursive = TRUE, showWarnings = FALSE) 

# ---------------------------
# Define Covariates, Weights, & Outcomes
# ---------------------------
COVARIATES_TO_USE <- c("coef_log_spend" )
VARS_TO_CHECK <- c(COVARIATES_TO_USE)

# DEFINE a vector of outcome variables to loop through
OUTCOME_VARS <- c("avg_log_price")

# ---------------------------
# Define Grid Search Parameters
# ---------------------------
# Define the range of values to test
CALIPER_GRID <- seq(0.01, 0.25, by = 0.01) 
RATIO_GRID <- seq(1, 5, by = 1) 

cat("Starting grid search with:\n")
cat("Caliper values:", paste(CALIPER_GRID, collapse = ", "), "\n")
cat("Ratio values:", paste(RATIO_GRID, collapse = ", "), "\n\n")

# ---------------------------
# Data Preparation
# ---------------------------
# Load data
panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

# Filter for a balanced panel
panel <- panel %>%
  filter(year >= 2010) %>%
  group_by(category) %>%
  filter(n() == 10) %>%
  ungroup()

# Create pre-treatment dataset
all_data_pre <- panel %>%
  filter(year <= 2013)

# Compute linear time trend coefficients
trends_pre <- all_data_pre %>%
  group_by(category, treated) %>%
  summarise(
    coef_log_price = possibly(~coef(lm(avg_log_price ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    coef_log_spend = possibly(~coef(lm(avg_log_spend ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    .groups = "drop"
  )

# Pivot data to wide format
data_wide_raw <- all_data_pre %>%
  pivot_wider(
    names_from = year,
    names_sep = "_",
    id_cols = c(category, treated, spend_2013 ),
    values_from = c(avg_log_price, avg_log_spend) # Ensure both outcomes are pivoted
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

# Join pre-treatment trends
data_wide_raw <- left_join(data_wide_raw, trends_pre, by = c("category", "treated"))

# KEY FIX: Safely remove rows with NAs in covariates OR the weighting variable
data_wide <- data_wide_raw %>%
  drop_na(all_of(VARS_TO_CHECK))

# CRITICAL DIAGNOSTIC: Check if data remains after cleaning
cat("Dimensions of raw wide data:", dim(data_wide_raw), "\n")
cat("Dimensions after targeted NA removal:", dim(data_wide), "\n")

# ---------------------------
# Robust Matching Loop (UPDATED FOR MULTIPLE OUTCOMES)
# ---------------------------
covariates_formula <- as.formula(paste("treated ~", paste(COVARIATES_TO_USE, collapse = " + ")))
treated_markets <- unique(data_wide$category[data_wide$treated == 1])

cat("\n\n====================================================\n")
cat("Found", length(treated_markets), "treated markets to process after cleaning.\n")
cat("====================================================\n\n")

match_pairs_list <- list()
optimal_params_list <- list() # List to store optimal params for each market

# --- Main loop over each treated market ---
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
  
  # -----------------------------------------------------------------
  # START: Grid Search for Optimal Caliper and Ratio
  # -----------------------------------------------------------------
  
  grid_results_list <- list()
  cat("--- Starting Grid Search for market:", category_id, "---\n")
  
  for (cal in CALIPER_GRID) {
    for (rat in RATIO_GRID) {
      
      model_attempt <- tryCatch({
        matchit(
          formula = covariates_formula, method = "nearest", data = temp_data,
          ratio = rat, caliper = cal, replace = TRUE
        )
      }, error = function(e) { NULL })
      
      mean_smd <- Inf
      num_controls <- 0
      
      if (!is.null(model_attempt)) {
        
        # --- ROBUSTNESS FIX ---
        # Instead of calling summary() (which errors on no-match),
        # we check the model's weights directly.
        # We count control units (treat == 0) that have a weight > 0.
        num_controls_matched <- sum(model_attempt$weights[model_attempt$treat == 0] > 0)
        
        if (num_controls_matched > 0) {
          # If we found controls, *now* it's safe to get the balance summary
          match_summary <- summary(model_attempt, un = FALSE)
          
          # Calculate the mean absolute SMD for the matched group
          mean_smd <- mean(abs(match_summary$sum.matched[, "Std. Mean Diff."]), na.rm = TRUE)
          num_controls <- num_controls_matched
        }
        # If num_controls_matched is 0, mean_smd stays Inf and num_controls stays 0,
        # which correctly penalizes this parameter set.
        # --- END FIX ---
      }
      
      # Store the result
      grid_results_list[[paste0("c", cal, "_r", rat)]] <- data.frame(
        caliper = cal,
        ratio = rat,
        mean_smd = mean_smd,
        num_controls = num_controls
      )
    }
  }
  
  
  # Combine results and find the best
  grid_results_df <- do.call(rbind, grid_results_list)
  
  # Find best parameters: min SMD, but MUST have at least 1 control
  best_params <- grid_results_df %>%
    filter(is.finite(mean_smd) & num_controls > 0) %>%
    arrange(mean_smd) %>%
    slice(1)
  
  # Save the log of the grid search for this market
  write_csv(grid_results_df, paste0("../output/grid_search_logs/grid_log_", category_id, ".csv"))
  
  if (nrow(best_params) == 0) {
    message("Grid search found NO valid match configuration for market ", category_id)
    next # Skip to the next market
  }
  
  cat("--- Optimal params found for", category_id, ": Caliper =", best_params$caliper, 
      ", Ratio =", best_params$ratio, ", Mean SMD =", round(best_params$mean_smd, 4), "---\n")
  
  # Store for final summary
  optimal_params_list[[category_id]] <- data.frame(
    treated_market = category_id,
    best_caliper = best_params$caliper,
    best_ratio = best_params$ratio,
    best_mean_smd = best_params$mean_smd
  )
  
  # -----------------------------------------------------------------
  # END: Grid Search
  # -----------------------------------------------------------------
  
  # --- Perform matching ONCE using OPTIMAL parameters ---
  current_model <- tryCatch({
    matchit(
      formula = covariates_formula, method = "nearest", data = temp_data,
      ratio = best_params$ratio, # Use best ratio
      caliper = best_params$caliper, # Use best caliper
      replace = TRUE
    )
  }, error = function(e) { message("Matching failed (on optimal run): ", e$message); return(NULL) })
  
  if (is.null(current_model)) next
  
  # Assess and save balance plot
  balance_plot <- love.plot(current_model, binary = "std", thresholds = c(m = .1), 
                            title = paste("Covariate Balance for Market:", category_id, 
                                          "\n(Caliper=", best_params$caliper, ", Ratio=", best_params$ratio, ")"))
  ggsave(filename = paste0("../output/balance_plots/balance_", category_id, ".pdf"), plot = balance_plot, width = 7, height = 6)
  
  # ✅ ADDED: Print the plot to the RStudio GUI (Plots pane)
  print(balance_plot) 
  
  match_data <- match.data(current_model)
  if (nrow(match_data) <= 1) {
    message("No valid control found for market ", category_id)
    next
  }
  
  treated_category <- unique(match_data$category[match_data$treated == 1])
  matched_control_categories <- unique(match_data$category[match_data$treated == 0])
  
  # The match_pairs summary is independent of the outcome, so it stays here
  match_pairs_list[[category_id]] <- data.frame(
    treated_market = treated_category,
    control_market = matched_control_categories
  )
  
  # --- NEW: Loop over each OUTCOME variable to generate plots ---
  for (outcome_var in OUTCOME_VARS) {
    cat("--- Generating plot for outcome:", outcome_var, "\n")
    
    # 1. Prepare trend data for the current outcome variable
    # ✅ MODIFIED: Added spend_2013 to the select() call
    outcome_trends <- panel %>%
      select(category, year, treated, spend_2013, all_of(outcome_var)) %>%
      group_by(category) %>%
      mutate(outcome_adj = .data[[outcome_var]] - .data[[outcome_var]][year == 2013]) %>%
      ungroup()
    
    # 2. Get the trend data for the single treated market
    treated_plot_data <- outcome_trends %>%
      filter(category == treated_category) %>%
      mutate(group_label = paste("Treated:", treated_category))
    
    # 3. Calculate the WEIGHTED AVERAGE trend across all matched control markets
    avg_control_plot_data <- outcome_trends %>%
      filter(category %in% matched_control_categories) %>%
      group_by(year) %>%
      # ✅ MODIFIED: Switched from mean() to weighted.mean() using spend_2013
      summarise(outcome_adj = weighted.mean(outcome_adj, w = spend_2013, na.rm = TRUE), .groups = "drop") %>%
      mutate(group_label = paste("Avg. Control (Weighted):", paste(matched_control_categories, collapse = ", ")))
    
    # 4. Combine the two datasets for plotting
    plot_data_final <- bind_rows(treated_plot_data, avg_control_plot_data)
    
    # 5. Generate a dynamic title for the plot and y-axis
    plot_y_label <- str_to_title(str_replace_all(outcome_var, "_", " "))
    plot_title <- paste(plot_y_label, "Trend:", treated_category)
    
    # 6. Generate the plot
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
    
    # 7. Save the plot with a dynamic filename
    ggsave(paste0("../output/figures/", outcome_var, "_trends_", treated_category, ".pdf"), plot = p, width = 10, height = 7)
    
    # ✅ ADDED: Print the plot to the RStudio GUI (Plots pane)
    print(p) 
    
    # ✅ MODIFIED: Updated cat message
    cat("Saved and displayed", outcome_var, "trend plot for", category_id, "\n")
  }
}

# Final summary
if (length(match_pairs_list) > 0) {
  match_pairs <- do.call(rbind, match_pairs_list)
  cat("\nSuccessfully matched pairs:\n")
  print(match_pairs)
  write_csv(match_pairs, "../output/match_pairs.csv")
  
  # Save the summary of optimal parameters
  optimal_params_df <- do.call(rbind, optimal_params_list)
  cat("\nOptimal parameters chosen per market:\n")
  print(optimal_params_df)
  write_csv(optimal_params_df, "../output/optimal_match_params.csv")
  
} else {
  cat("\nNo successful matches were made.\n")
}