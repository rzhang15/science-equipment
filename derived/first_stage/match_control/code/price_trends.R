library(tidyverse)
library(haven)
library(ggplot2)
library(stringr)

setwd("~/sci_eq/derived/first_stage/match_control/code")
output_dir <- "../output/debug_plots_individual"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
cat("Saving individual plots to:", output_dir, "\n")

cat("Loading raw panel data...\n")
panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

cat("Data loaded. Preparing data for plotting...\n")

plot_data_long <- panel %>%
  select(category, year, treated, avg_log_price, raw_price) %>%
  pivot_longer(
    cols = c("avg_log_price", "raw_price"),
    names_to = "price_metric",
    values_to = "price_value"
  ) %>%
  mutate(
    treated_label = if_else(treated == 1, "Treated", "Control")
  )

cat("Data prepared. Looping through each market to generate plots...\n")

all_markets <- unique(plot_data_long$category)
total_markets <- length(all_markets)

cat("Found", total_markets, "markets to plot.\n")

variation_results_list <- list()

for (i in 1:total_markets) {
  market_id <- all_markets[i]
  
  safe_market_id <- str_replace_all(market_id, "[^a-zA-Z0-9_]", "-")
  
  if (i %% 50 == 0) {
    cat("...Processing market", i, "of", total_markets, ":", market_id, "\n")
  }
  
  market_data <- plot_data_long %>%
    filter(category == market_id)
  
  debug_plot_single <- ggplot(market_data, aes(x = year, y = price_value, color = treated_label, group = 1)) +
    geom_line() +
    geom_point(size = 1) +
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
  
  output_filename <- file.path(output_dir, paste0("market_trend_", safe_market_id, ".pdf"))
  
  ggsave(
    filename = output_filename,
    plot = debug_plot_single,
    width = 10,
    height = 6,
    units = "in"
    # quiet = TRUE
  )
  
  raw_price_data <- market_data %>%
    filter(price_metric == "raw_price" & !is.na(price_value) & price_value > 0)
  
  cv_raw_price <- NA
  is_treated <- first(market_data$treated_label)
  
  if (nrow(raw_price_data) > 1) {
    market_sd <- sd(raw_price_data$price_value, na.rm = TRUE)
    market_mean <- mean(raw_price_data$price_value, na.rm = TRUE)
    
    if (market_mean > 0) {
      cv_raw_price <- market_sd / market_mean
    }
  }
  
  variation_results_list[[market_id]] <- data.frame(
    market_id = market_id,
    cv_raw_price = cv_raw_price,
    treated_status = is_treated
  )
  
}

cat("\nSuccessfully generated and saved all", total_markets, "market plots to:", output_dir, "\n")

cat("\n\n--- Analysis of Market Price Variation (Raw Price) ---\n")

if (length(variation_results_list) > 0) {
  variation_results_df <- do.call(rbind, variation_results_list)
  rownames(variation_results_df) <- NULL
  
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

