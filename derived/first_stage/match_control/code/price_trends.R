# ---------------------------
# Script 1: Debug Market Price Trends (Modified to save plots and calculate variation)
#
# Purpose: This script loads the raw panel data, creates a separate
# plot for each market, and also calculates the coefficient of
# variation (CV) to identify markets with high price volatility.
# ---------------------------

# Load necessary libraries
library(tidyverse)
library(haven)
library(ggplot2)
library(stringr) # Added for cleaning filenames

# Set working directory (relative to your original script's location)
# You may need to adjust this path.
setwd("~/sci_eq/derived/first_stage/match_control/code")
output_dir <- "../output/debug_plots_individual" # New directory
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
cat("Saving individual plots to:", output_dir, "\n")


cat("Loading raw panel data...\n")
# Load data
panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

cat("Data loaded. Preparing data for plotting...\n")

# Prepare the data for faceting
# 1. Select only the columns we need
# 2. Pivot data to be "long" on the price metric
#    This lets us plot both raw_price and avg_log_price on the same grid
plot_data_long <- panel %>%
  select(category, year, treated, avg_log_price, raw_price) %>%
  pivot_longer(
    cols = c("avg_log_price", "raw_price"),
    names_to = "price_metric",
    values_to = "price_value"
  ) %>%
  # Convert `treated` to a factor for clearer plot labels
  mutate(
    treated_label = if_else(treated == 1, "Treated", "Control")
  )

cat("Data prepared. Looping through each market to generate plots...\n")

# Get list of unique markets
all_markets <- unique(plot_data_long$category)
total_markets <- length(all_markets)

cat("Found", total_markets, "markets to plot.\n")

# --- NEW: Initialize a list to store variation results ---
variation_results_list <- list()

# --- Loop through each market and save its plot ---
for (i in 1:total_markets) {
  market_id <- all_markets[i]
  
  # A simple way to clean filenames (replace special chars)
  safe_market_id <- str_replace_all(market_id, "[^a-zA-Z0-9_]", "-")
  
  if (i %% 50 == 0) { # Print progress update every 50 markets
    cat("...Processing market", i, "of", total_markets, ":", market_id, "\n")
  }
  
  # Filter data for just this one market
  market_data <- plot_data_long %>%
    filter(category == market_id)
  
  # Create the plot for this single market
  # We now facet by price_metric only
  debug_plot_single <- ggplot(market_data, aes(x = year, y = price_value, color = treated_label, group = 1)) +
    geom_line() +
    geom_point(size = 1) +
    # Create a separate plot panel for each price type
    facet_wrap(~ price_metric, scales = "free_y") +
    labs(
      title = paste("Debug Plot: Price Trends for Market:", market_id),
      subtitle = "Treated vs. Control status shown. 'free_y' scale used for each panel.",
      x = "Year",
      y = "Price Value",
      color = "Treatment Status"
    ) +
    theme_bw(base_size = 12) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(face = "bold")
    )
  
  # Save the plot to a PDF
  output_filename <- file.path(output_dir, paste0("market_trend_", safe_market_id, ".pdf"))
  
  ggsave(
    filename = output_filename,
    plot = debug_plot_single,
    width = 10,
    height = 6,
    units = "in"
    # quiet = TRUE # <-- REMOVED this line as it was causing the error
  )
  
  # --- NEW: Calculate Coefficient of Variation (CV) for raw_price ---
  raw_price_data <- market_data %>%
    filter(price_metric == "raw_price" & !is.na(price_value) & price_value > 0)
  
  cv_raw_price <- NA
  is_treated <- first(market_data$treated_label)
  
  # Need at least 2 data points to calculate sd()
  if (nrow(raw_price_data) > 1) {
    market_sd <- sd(raw_price_data$price_value, na.rm = TRUE)
    market_mean <- mean(raw_price_data$price_value, na.rm = TRUE)
    
    if (market_mean > 0) {
      cv_raw_price <- market_sd / market_mean
    }
  }
  
  # Store the result
  variation_results_list[[market_id]] <- data.frame(
    market_id = market_id,
    cv_raw_price = cv_raw_price,
    treated_status = is_treated
  )
  
}

cat("\nSuccessfully generated and saved all", total_markets, "market plots to:", output_dir, "\n")

# --- NEW: Report on market variation ---
cat("\n\n--- Analysis of Market Price Variation (Raw Price) ---\n")

if (length(variation_results_list) > 0) {
  # Combine all results into a single data frame
  variation_results_df <- do.call(rbind, variation_results_list)
  rownames(variation_results_df) <- NULL # Clean up row names
  
  # Sort by CV in descending order and get top 10
  top_10_variable_markets <- variation_results_df %>%
    filter(!is.na(cv_raw_price)) %>%
    arrange(desc(cv_raw_price)) %>%
    head(30)
  
  cat("Top 10 Most Variable Markets (by Coefficient of Variation on Raw Price):\n")
  print(top_10_variable_markets)
  
} else {
  cat("Could not calculate variation results.\n")
}

cat("-----------------------------------------------------------\n\n")

