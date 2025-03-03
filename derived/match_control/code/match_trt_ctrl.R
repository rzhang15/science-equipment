# Load necessary libraries
library(tidyverse)
library(fixest)
library(MatchIt)
library(cobalt)
library(ggplot2)
library(here)

# Create output directory
dir.create("../output/figures", recursive = TRUE, showWarnings = FALSE)

# ---------------------------
# Data Preparation
# ---------------------------
# Load your data into a data frame
panel <- read_dta("../external/dallas/mkt_yr.dta")  # Adjust if using Stata files
panel <- panel %>% mutate(mkt = as.character(mkt))

# Compute number of years per market
panel <- panel %>%
  group_by(mkt) %>%
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
  select(mkt, prdct_ctgry, year, treated, avg_log_price,
         log_tot_qty, log_tot_spend, raw_price, raw_qty, raw_spend)

control_pre <- control %>%
  filter(year <= 2013) %>%
  select(mkt, prdct_ctgry, year, treated, avg_log_price,
         log_tot_qty, log_tot_spend, raw_price, raw_qty, raw_spend)

all_data_pre <- bind_rows(treated_pre, control_pre)

# Compute linear time trend coefficients
all_data_pre <- all_data_pre %>%
  group_by(mkt) %>%
  mutate(
    coef_log_price = coef(lm(avg_log_price ~ year, data = cur_data()))[2],
    coef_log_spend = coef(lm(log_tot_spend ~ year, data = cur_data()))[2],
    coef_log_qty   = coef(lm(log_tot_qty ~ year, data = cur_data()))[2],
    coef_price = coef(lm(raw_price ~ year, data = cur_data()))[2],
    coef_spend = coef(lm(raw_spend ~ year, data = cur_data()))[2],
    coef_qty   = coef(lm(raw_qty ~ year, data = cur_data()))[2]
  ) %>%
  ungroup()

# Pivot data to wide format
data_wide <- all_data_pre %>%
  pivot_wider(names_from = year, names_sep = "_",
              values_from = c(avg_log_price, raw_price, log_tot_spend, raw_spend, log_tot_qty, raw_qty)) %>%
  mutate(log_price_chg = avg_log_price_2013 - avg_log_price_2012) %>%
  rowwise() %>%
  na.omit() %>%
  ungroup()

# Merge product category info
prdct_info <- all_data_pre %>% distinct(mkt, prdct_ctgry)
data_wide <- left_join(data_wide, prdct_info, by = "mkt")

# Prepare price trends data for plotting
price_trends <- panel %>%
  filter(mkt %in% unique(data_wide$mkt)) %>%
  select(mkt, prdct_ctgry, year, avg_log_price, treated) %>%
  group_by(mkt) %>%
  mutate(price_adj = avg_log_price - avg_log_price[year == 2013]) %>%
  ungroup()

# ---------------------------
# Matching and Plot Saving Loop
# ---------------------------
covariates <- "coef_log_price + raw_price_2011 + coef_price"
treated_markets <- unique(data_wide$mkt[data_wide$treated == 1])

# Initialize storage
match_pairs_list <- list()

for (mkt_id in treated_markets) {
  cat("\nProcessing treated market:", mkt_id, "\n")
  
  # Subset data for the treated market and controls
  temp_data <- data_wide %>% filter(mkt == mkt_id | treated == 0)
  
  # Run matching
  current_model <- tryCatch({
    matchit(
      as.formula(paste("treated ~", covariates)),
      method = "nearest",
      distance = "glm",
      data = temp_data,
      caliper = 0.2,
      ratio = 1,
      replace = TRUE
    )
  }, error = function(e) {
    message("Matching failed for market ", mkt_id, ": ", e$message)
    return(NULL)
  })
  
  # Skip if no match was found
  if (is.null(current_model)) {
    next
  }
  
  # Extract matched data
  match_data <- tryCatch({
    match.data(current_model)
  }, error = function(e) {
    message("Error extracting matched data for market ", mkt_id)
    return(NULL)
  })
  
  # Skip if matched data is empty
  if (is.null(match_data) || nrow(match_data) == 0) {
    next
  }
  
  # Identify matched pairs
  treated_mkt <- unique(match_data$mkt[match_data$treated == 1])
  matched_control_mkt <- unique(match_data$mkt[match_data$treated == 0])
  
  if (length(treated_mkt) < 1 || length(matched_control_mkt) < 1) {
    next  # Skip if no control found
  }
  
  # Append to list
  match_pairs_list[[as.character(mkt_id)]] <- data.frame(
    mkt = treated_mkt, matched_control = matched_control_mkt, stringsAsFactors = FALSE
  )
  
  # ---------------------------
  # Generate and Display Plot in Console & Save to File
  # ---------------------------
  pair_data <- price_trends %>%
    filter(mkt %in% c(treated_mkt, matched_control_mkt)) %>%
    mutate(mkt_label = case_when(
      mkt == treated_mkt ~ paste0("Treated: ", prdct_info$prdct_ctgry[prdct_info$mkt == treated_mkt]),
      mkt == matched_control_mkt ~ paste0("Control: ", prdct_info$prdct_ctgry[prdct_info$mkt == matched_control_mkt])
    ))
  
  p <- ggplot(pair_data, aes(x = year, y = price_adj, color = mkt_label)) +
    geom_line(linewidth = 1) +
    geom_point() +
    labs(title = paste("Price Trends for Treated:", treated_mkt, "and Control:", matched_control_mkt),
         x = "Year", y = "Avg Log Price (2013 = 0)", color = "Market Type") +
    theme_minimal()
  
  # **Print the plot to the console**
  print(p)  # This ensures the plot is displayed in the console
  
  # **Save the plot to a PDF file**
  pdf_file <- paste0("../output/figures/log_price_trends_", treated_mkt, ".pdf")
  tryCatch({
    ggsave(pdf_file, plot = p, width = 8, height = 6)
    cat("Saved plot to:", pdf_file, "\n")
  }, error = function(e) {
    message("Failed to save plot for market ", treated_mkt, ": ", e$message)
  })
}

# Combine matched pairs into a data frame
match_pairs <- do.call(rbind, match_pairs_list)
cat("Final Matched Pairs:\n")
print(match_pairs)

# Save match pairs to CSV
write_csv(match_pairs, "../output/match_pairs.csv")