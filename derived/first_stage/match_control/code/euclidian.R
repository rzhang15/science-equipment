# Load necessary libraries
library(tidyverse)
library(fixest)
library(cobalt)
library(ggplot2)
library(here)
library(haven)

# Create output directory
dir.create("../output/figures", recursive = TRUE, showWarnings = FALSE)
setwd("~/sci_eq/derived/first_stage/match_control/code")

# ---------------------------
# Data Preparation
# ---------------------------
# Load your data into a data frame
panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

# Compute number of years per market
panel <- panel %>% 
  filter(year >= 2011) %>% 
  group_by(category) %>%
  mutate(n_years = n()) %>%
  ungroup()

# Keep only markets that have exactly 9 years of data
panel <- panel %>%
  filter(n_years == 9)

# Split treated and control groups
treated <- panel %>% filter(treated == 1)
control <- panel %>% filter(treated == 0)

# Create pre-treatment datasets (years ≤ 2013)
treated_pre <- treated %>%
  filter(year <= 2013) %>%
  select(category, category, year, treated, avg_log_price,
         log_tot_qty, log_tot_spend, raw_price, raw_qty, raw_spend, num_suppliers)

control_pre <- control %>%
  filter(year <= 2013) %>%
  select(category, category, year, treated, avg_log_price,
         log_tot_qty, log_tot_spend, raw_price, raw_qty, raw_spend, num_suppliers)

all_data_pre <- bind_rows(treated_pre, control_pre)

# Compute linear time trend coefficients for several price/quantity measures
all_data_pre <- all_data_pre %>%
  group_by(category) %>%
  mutate(
    coef_log_price = coef(lm(avg_log_price ~ year, data = cur_data()))[2],
    coef_log_spend = coef(lm(log_tot_spend ~ year, data = cur_data()))[2],
    coef_log_qty   = coef(lm(log_tot_qty ~ year, data = cur_data()))[2],
    coef_price     = coef(lm(raw_price ~ year, data = cur_data()))[2],
    coef_spend     = coef(lm(raw_spend ~ year, data = cur_data()))[2],
    coef_qty       = coef(lm(raw_qty ~ year, data = cur_data()))[2]
  ) %>%
  ungroup()

# Pivot data to wide format
data_wide <- all_data_pre %>%
  pivot_wider(names_from = year, names_sep = "_",
              values_from = c(num_suppliers, avg_log_price, raw_price, log_tot_spend, raw_spend, log_tot_qty, raw_qty)) %>%
  rowwise() %>%
  mutate(avg_pre_log_price = mean(c_across(starts_with("avg_log_price_")), na.rm = TRUE)) %>%
  na.omit() %>%
  ungroup()

# Merge product category info
prdct_info <- all_data_pre %>% distinct(category, category)
data_wide <- left_join(data_wide, prdct_info, by = "category")

# Prepare price trends data for plotting
price_trends <- panel %>%
  filter(category %in% unique(data_wide$category)) %>%
  select(category, category, year, avg_log_price, treated) %>%
  group_by(category) %>%
  mutate(price_adj = avg_log_price - avg_log_price[year == 2013]) %>%
  ungroup()

# ---------------------------
# Euclidean Distance Matching and Plot Saving Loop
# ---------------------------

# Define the covariates to be used for Euclidean distance calculation
covs <- c("avg_log_price_2011", "avg_log_price_2012","avg_log_price_2013")
treated_markets <- unique(data_wide$category[data_wide$treated == 1])

# Initialize storage for matched pairs
match_pairs_list <- list()

for (category_id in treated_markets) {
  cat("\nProcessing treated market:", category_id, "\n")
  
  # Subset data: the treated unit and all control units
  temp_data <- data_wide %>% filter(category == category_id | treated == 0)
  
  treated_row <- temp_data %>% filter(category == category_id)
  control_rows <- temp_data %>% filter(treated == 0)
  
  # Skip if no control available
  if (nrow(control_rows) == 0) {
    message("No control units available for market ", category_id)
    next
  }
  
  # Compute Euclidean distances on the specified covariates
  treated_vals <- treated_row %>% select(all_of(covs)) %>% unlist() %>% as.numeric()
  control_rows <- control_rows %>%
    mutate(distance = apply(select(., all_of(covs)), 1, 
                            function(x) sqrt(sum((as.numeric(x) - treated_vals)^2))))
  
  # Select the control with the smallest distance (if ties, the first is chosen)
  matched_control <- control_rows %>% filter(distance == min(distance))
  matched_control_category <- matched_control$category[1]
  
  treated_category <- category_id
  
  # Append match pair to the list
  match_pairs_list[[as.character(category_id)]] <- data.frame(
    category = treated_category, 
    matched_control = matched_control_category,
    stringsAsFactors = FALSE
  )
  
  # ---------------------------
  # Plotting the Price Trends for the Matched Pair
  # ---------------------------
  
  # Since a single control is matched, assign individual labels for treated and control
  pair_data <- price_trends %>%
    filter(category %in% c(treated_category, matched_control_category)) %>%
    mutate(category_label = case_when(
      category == treated_category ~ paste0("Treated Market: ", prdct_info$category[prdct_info$category == treated_category]),
      category == matched_control_category ~ paste0("Control Market: ", prdct_info$category[prdct_info$category == matched_control_category])
    ))
  
  p <- ggplot(pair_data, aes(x = year, y = price_adj, color = category_label)) +
    geom_line(linewidth = 1) +
    geom_point() +
    labs(x = "Year", y = "Avg Log Price") +
    scale_color_discrete(name = NULL) +
    scale_x_continuous(breaks = seq(2011, 2019, 1), limits = c(2011, 2019)) +
    theme_minimal() +
    theme(legend.position = "bottom",
          legend.direction = "horizontal",
          legend.box = "horizontal")
  
  # Display the plot in the console
  print(p)
  
  # Save the plot to a PDF file
  pdf_file <- paste0("../output/figures/log_price_trends_", treated_category, ".pdf")
  tryCatch({
    ggsave(pdf_file, plot = p, width = 8, height = 6)
    cat("Saved plot to:", pdf_file, "\n")
  }, error = function(e) {
    message("Failed to save plot for market ", treated_category, ": ", e$message)
  })
}

# Combine matched pairs into a data frame
match_pairs <- do.call(rbind, match_pairs_list)
cat("Final Matched Pairs:\n")
print(match_pairs)

# Save match pairs to CSV
write_csv(match_pairs, "../output/match_pairs.csv")