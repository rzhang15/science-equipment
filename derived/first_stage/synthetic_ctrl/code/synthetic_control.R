# -----------------------------------------------------------
# SCM Trend Plotting Script: Treated vs. Synthetic
# -----------------------------------------------------------
library(tidyverse)
library(Synth)
library(haven)

# Setup Paths
setwd("~/sci_eq/derived/first_stage/synthetic_ctrl/code")
DATA_INPUT  <- "../external/samp/category_yr_tfidf.dta"
OUTPUT_DIR  <- "../output/figures/"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Load and Prep
panel <- read_dta(DATA_INPUT) %>%
  mutate(category_num = as.numeric(as.factor(category)),
         treated = as.numeric(treated)) %>%
  filter(year >= 2010) %>%
  group_by(category) %>%
  filter(!any(is.na(avg_log_price))) %>%
  ungroup()

treated_categories <- unique(panel$category[panel$treated == 1])
control_ids <- unique(panel$category_num[panel$treated == 0])
stack_list <- list()
# --- Main Loop ---
for (mkt in treated_categories) {
  curr_id <- unique(panel$category_num[panel$category == mkt])
  
  # 1. Synth Data Setup
  dp_out <- tryCatch({
    dataprep(
      foo = as.data.frame(panel),
      predictors = c("spend_2013"),
      predictors.op = "mean",
      time.predictors.prior = 2010:2013,
      special.predictors = list(list("avg_log_price", 2010:2013, "mean")),
      dependent = "avg_log_price",
      unit.variable = "category_num",
      unit.names.variable = "category",
      time.variable = "year",
      treatment.identifier = curr_id,
      controls.identifier = control_ids,
      time.optimize.ssr = 2010:2013,
      time.plot = 2010:2019
    )
  }, error = function(e) return(NULL))
  
  if (is.null(dp_out)) next
  
  # 2. Run Synth
  s_out <- tryCatch({ synth(dp_out) }, error = function(e) return(NULL))
  if (is.null(s_out)) next
  control_weights <- data.frame(
    category_num = as.numeric(rownames(s_out$solution.w)), # The Control Unit IDs
    weight = as.numeric(s_out$solution.w)
  )
  control_weights <- control_weights %>% filter(weight > 0.001)
  treated_row <- data.frame(
    category_num = curr_id,
    weight = 1
  )
  stack_data <- bind_rows(treated_row, control_weights) %>%
    mutate(stack_id = curr_id) # Using the treated unit's ID as the unique Stack ID
  
  # E. Store in the list
  stack_list[[mkt]] <- stack_data
  # 3. Extract Values for ggplot
  # Observed (Treated) values
  observed <- dp_out$Y1plot
  # Synthetic values (Matrix multiplication of control outcomes and SCM weights)
  synthetic <- dp_out$Y0plot %*% s_out$solution.w
  
  plot_df <- data.frame(
    year = as.numeric(rownames(observed)),
    observed = as.numeric(observed),
    synthetic = as.numeric(synthetic)
  ) %>%
    pivot_longer(cols = c(observed, synthetic), names_to = "group", values_to = "price")
  
  # 4. Calculate Match Quality (Pre-treatment RMSPE)
  pre_data <- plot_df %>% filter(year <= 2013) %>% pivot_wider(names_from = group, values_from = price)
  rmspe <- sqrt(mean((pre_data$observed - pre_data$synthetic)^2))
  
  # 5. Generate ggplot
  p <- ggplot(plot_df, aes(x = year, y = price, color = group, linetype = group)) +
    geom_line(size = 1.2) +
    geom_point() +
    geom_vline(xintercept = 2013.5, linetype = "dashed", color = "darkred") +
    scale_color_manual(values = c("observed" = "black", "synthetic" = "blue"),
                       labels = c("Actual Market", "Synthetic Control")) +
    scale_linetype_manual(values = c("observed" = "solid", "synthetic" = "dashed"),
                          labels = c("Actual Market", "Synthetic Control")) +
    labs(title = paste("SCM Fit for Market:", mkt),
         subtitle = paste("Pre-treatment RMSPE:", round(rmspe, 5)),
         x = "Year", y = "Avg Log Price",
         caption = "Red dashed line indicates start of treatment period.") +
    theme_minimal() +
    theme(legend.position = "bottom", legend.title = element_blank())
  
  # 6. Save
  ggsave(filename = paste0(OUTPUT_DIR, "/trend_", mkt, ".pdf"), plot = p, width = 8, height = 5)
  print(p) # Show in RStudio
}

# 1. Combine all stacks into one long "Weights" dataframe
weights_df <- bind_rows(stack_list)

# 2. Merge back with the original panel data (Prices, Spend, etc.)
# We do an inner_join because we only want the units that are part of a stack
synth_panel <- inner_join(panel, weights_df, by = "category_num")

# 3. Create the necessary variables for DiD / Event Study
synth_panel <- synth_panel %>%
  mutate(
    # Identify if this row is the Treated Unit IN THIS STACK
    is_treated_in_stack = (category_num == stack_id),
    
    # Event Study Time (Relative Year)
    rel_year = year - 2014, # Adjust to your actual event year
    
    # Post Dummy
    post = as.numeric(year >= 2014),
    
    # Interaction for standard DiD
    treat_post = is_treated_in_stack * post
  )

# 4. Save for Stata/R Analysis
write_dta(synth_panel, paste0("../output/synth_stacked_panel.dta"))

print("Panel construction complete. Ready for fixest/reghdfe.")