# Load necessary libraries
library(tidyverse)
library(fixest)
library(haven)
library(MatchIt)
library(cobalt)
library(Synth)
library(ggplot2)
isid <- function(data, ...) {
  # Get the column names provided as input
  cols <- enquos(...)
  # Group by the input columns and check uniqueness
  duplicates <- data %>%
    group_by(!!!cols) %>%
    summarise(row_count = n(), .groups = "drop") %>%
    filter(row_count > 1)
  # Return result
  if (nrow(duplicates) == 0) {
    message("The combination of columns uniquely identifies rows.")
    return(TRUE)
  } else {
    message("The combination of columns does NOT uniquely identify rows.")
    print(duplicates)
    return(FALSE)
  }
}
# Load data
panel <- read_dta("../external/dallas/sku_yr.dta") 
treated <- panel %>% filter(treated==1)
control <-panel %>% filter(treated==0) 

treated_pre <- treated %>%
  filter(year <= 2013) %>%
  select(
    sku,
    mkt,
    year,
    treated,
    price,
    qty,
    spend,
    raw_price,
    raw_qty,
    raw_spend
  )
control_pre <- control %>%
  filter(year <= 2013) %>%
  select(
    sku,
    mkt,
    year,
    treated,
    price,
    qty,
    spend,
    raw_price,
    raw_qty,
    raw_spend
  )

all_data_pre <- bind_rows(treated_pre, control_pre) %>% 
  group_by(sku) %>%
  filter(n() >= 2) %>%
  ungroup() %>%
  group_by(mkt) %>% 
  filter(n_distinct(treated) == 2) %>%
  ungroup()
  ## check its a fully balanced panel
missing_years <- all_data_pre %>%
  group_by(sku) %>%
  reframe(missing_year = setdiff(2011:2013, unique(year))) %>%
  filter(!is.na(missing_year))
missing_years

# get linear time trend coefs
all_data_pre <- all_data_pre %>%
  group_by(product_grp) %>%
  mutate(
    coef_log_price = coef(lm(log_prdct_price ~ year, data = cur_data()))[2],
    coef_log_spend = coef(lm(log_prdct_spend ~ year, data = cur_data()))[2],
    coef_log_qty = coef(lm(log_prdct_qty ~ year, data = cur_data()))[2],
    coef_price = coef(lm(prdct_price ~ year, data = cur_data()))[2],
    coef_spend = coef(lm(prdct_spend ~ year, data = cur_data()))[2],
    coef_qty = coef(lm(prdct_qty ~ year, data = cur_data()))[2]
  ) %>%
  ungroup()
isid(all_data_pre, product_grp, year)
write_csv(all_data_pre, "../output/pre_data.csv")

regnums <- all_data_pre  %>%
  select(product_grp, starts_with("regnum")) %>% 
  distinct()
# Perform pivot_wider
data_wide <- all_data_pre %>%
filter(year >= 2014 & year <= 2015) %>% 
  pivot_wider(
    names_from = year,
    names_sep = "_",
    values_from = c(
      log_prdct_price,
      prdct_price,
      r_log_prdct_price,
      prdct_spend,
      log_prdct_spend,
      r_log_prdct_spend,
      prdct_qty,
      log_prdct_qty,
      r_log_prdct_qty,
      tot_mfgs,
      new_devices,
      num_trans,
      num_hosps,
      r_log_old_device_qty,
      log_old_device_qty,
    )
  ) %>%
  mutate(
    w_log_prdct_price_2014 = log_prdct_price_2014 * prdct_spend_2014,
    w_log_prdct_price_2015 = log_prdct_price_2015 * prdct_spend_2014,
    w_log_prdct_qty_2014 = log_prdct_qty_2014 * prdct_spend_2014,
    w_log_prdct_qty_2015 = log_prdct_qty_2015 * prdct_spend_2014,
    w_log_prdct_spend_2014 = log_prdct_spend_2014 * prdct_spend_2014,
    w_log_prdct_spend_2015 = log_prdct_spend_2015 * prdct_spend_2014,
    w_prdct_price_2014 = prdct_price_2014 * prdct_spend_2014,
    w_prdct_price_2015 = prdct_price_2015 * prdct_spend_2014,
    w_prdct_qty_2014 = prdct_qty_2014 * prdct_spend_2014,
    w_prdct_qty_2015 = prdct_qty_2015 * prdct_spend_2014,
    w_prdct_spend_2014 = prdct_spend_2014 * prdct_spend_2014,
    w_prdct_spend_2015 = prdct_spend_2015 * prdct_spend_2014,
    log_price_chg = (log_prdct_price_2015 - log_prdct_price_2014),
    price_chg = (prdct_price_2015-prdct_price_2014)/prdct_price_2014,
    log_qty_chg = (log_prdct_qty_2015 - log_prdct_qty_2014) ,
    qty_chg = (prdct_qty_2015-prdct_qty_2014)/prdct_qty_2014,
    log_spend_chg = (log_prdct_spend_2015 - log_prdct_spend_2014),
    spend_chg = (prdct_spend_2015 - prdct_spend_2014)/prdct_spend_2014,
    avg_num_mfgs = rowMeans(cbind(tot_mfgs_2014, tot_mfgs_2015, na.rm = TRUE)),
    num_mfgs = rowSums(cbind(tot_mfgs_2014, tot_mfgs_2015, na.rm = TRUE)),
    avg_hosps = rowMeans(cbind(num_hosps_2014, num_hosps_2015, na.rm = TRUE)),
    tot_hosps = rowSums(cbind(num_hosps_2014, num_hosps_2015, na.rm = TRUE)),
    avg_trans = rowMeans(cbind(num_trans_2014, num_trans_2015, na.rm = TRUE)),
    new_devices = rowSums(cbind(new_devices_2014, new_devices_2015, na.rm = TRUE))
  )  %>% rowwise() %>%
  mutate(
    set_regnum = paste(sort(na.omit(c_across(starts_with("regnum")))), collapse = "_")
  ) %>%
  ungroup() %>% 
  select(-starts_with("regnum")) %>% 
  na.omit()

n = nrow(data_wide %>% filter(treatment == 1) %>% distinct(product_grp))

#version1 match on levels: 
#covariates <- "coef_price + coef_qty + w_prdct_qty_2014 + w_prdct_price_2014"
#covariates <- "coef_log_price + coef_log_qty +w_log_prdct_price_2014 +w_log_prdct_qty_2014"
covariates <- "coef_log_price +coef_log_qty +w_prdct_price_2014"

# Grid Search for Optimal Caliper 4nd Ratio
caliper_grid <- seq(0.01, 0.01, by = 0.01)
ratio_grid <- 1:1
results <- expand_grid(caliper = caliper_grid, ratio = ratio_grid) %>%
  mutate(mean_std_diff = NA)

optimal_match_model <- NULL  # Variable to store the optimal match model

for (i in 1:nrow(results)) {
  caliper_val <- results$caliper[i]
  ratio_val <- results$ratio[i]
  
  # Run matchit with the current caliper and ratio
  match_model <- tryCatch({
    matchit(
      as.formula(paste("treatment ~", covariates)),
      method = "nearest",
      data = data_wide,
      distance = "glm", 
      discard = "both",
      caliper = 0.2,
      antiexact = ~set_regnum,
      ratio = ratio_grid,
      replace = TRUE, 
      reestimate = TRUE
      )
  }, error = function(e)
    NULL)
  
  if (!is.null(match_model)) {
    # Compute balance statistics
    bal_stats <- bal.tab(match_model,
                         un = TRUE,
                         thresholds = c(m = 0.05))
    results$mean_std_diff[i] <- mean(bal_stats$Balance$Diff.Adj, na.rm = TRUE)
    
    # Assign the optimal model if this configuration is the best so far
    if (is.null(optimal_match_model) ||
        results$mean_std_diff[i] < min(results$mean_std_diff, na.rm = TRUE)) {
      optimal_match_model <- match_model
    }
  }
}

# Find the Optimal Parameters
optimal_params <- results %>%
  filter(!is.na(mean_std_diff)) %>%
  arrange(mean_std_diff) %>%
  slice(1)

# Use the optimal match model directly
print(optimal_params)
plot(optimal_match_model, type = "jitter", interactive = FALSE)

# Extract the matched data
product_xw <- read_stata("../temp/product_grp_xw.dta") %>%
  distinct(productcode_list, product_grp)

matched_data <- match.data(optimal_match_model)
write_dta(matched_data, "../output/optimal_matched_data.dta")

match_matrix <- optimal_match_model$match.matrix
matched_pairs_save <- data.frame(Treated_Index = rownames(match_matrix),
                                 Control_Index = as.vector(match_matrix))

matched_pairs_save$treated_product_grp <- data_wide$product_grp[as.numeric(matched_pairs_save$Treated_Index)]
matched_pairs_save$control_product_grp <- data_wide$product_grp[as.numeric(matched_pairs_save$Control_Index)]

matched_pairs_save <- matched_pairs_save %>%
  left_join(product_xw, by = c("treated_product_grp" = "product_grp")) %>%
  rename(treated_productcode_list = productcode_list) %>%
  left_join(product_xw, by = c("control_product_grp" = "product_grp")) %>%
  rename(control_productcode_list = productcode_list) %>%
  filter(!is.na(control_product_grp)) %>% 
  left_join(regnums, by = c("treated_product_grp" ="product_grp")) %>% 
  left_join(regnums, by = c("control_product_grp" ="product_grp"), suffix = c("","_control")) %>% 
  rowwise() %>%
  mutate(
    has_overlap = any(
      na.omit(c_across(starts_with("regnum"))) %in% 
        na.omit(c_across(starts_with("regnum_control")))
    )
  ) %>%
  ungroup() %>% 
  select(-starts_with("regnum"))
  
write_dta(matched_pairs_save, "../output/matched_pairs.dta")

# Save treated list
treated_list <- matched_pairs_save %>%
  distinct(treated_product_grp) %>%
  rename(product_grp = treated_product_grp)
write_dta(treated_list, "../output/matched_treated_products.dta")

# Save matched control data
matched_control <- control %>%
  filter(product_grp %in% matched_pairs_save$control_product_grp)
write_dta(matched_control, "../output/matched_control_highsim.dta")

# Combine matched treated and control data across all years
matched_all_years <- bind_rows(treated %>% semi_join(treated_list, by = "product_grp"),
                               matched_control)
write_dta(matched_all_years, "../output/matched_all_years.dta")

# Add tot_prdct_spend_2015 for each product group
prdct_spend_2014 <- matched_all_years %>%
  filter(year == 2014) %>%
  select(product_grp, prdct_spend_2014 = prdct_spend)

matched_all_years <- matched_all_years %>%
  left_join(prdct_spend_2014, by = "product_grp")

# Collapse Data for Visualization
collapsed_data <- matched_all_years %>%
  group_by(year, treatment) %>%
  summarise(
    r_log_prdct_price = weighted.mean(r_log_prdct_price, prdct_spend_2014, na.rm = TRUE),
    r_log_prdct_qty = weighted.mean(r_log_prdct_qty, prdct_spend_2014, na.rm = TRUE),
    r_log_prdct_spend = weighted.mean(r_log_prdct_spend, prdct_spend_2014, na.rm = TRUE),
    r_log_old_device_qty = weighted.mean(r_log_old_device_qty, prdct_spend_2014, na.rm = TRUE),
    .groups = 'drop'
  )

# Normalize Data
r_log_prdct_price_2015_treat0 <- collapsed_data %>%
  filter(year == 2015, treatment == 0) %>%
  pull(r_log_prdct_price)

r_log_prdct_price_2015_treat1 <- collapsed_data %>%
  filter(year == 2015, treatment == 1) %>%
  pull(r_log_prdct_price)

r_log_prdct_qty_2015_treat0 <- collapsed_data %>%
  filter(year == 2015, treatment == 0) %>%
  pull(r_log_prdct_qty)

r_log_prdct_qty_2015_treat1 <- collapsed_data %>%
  filter(year == 2015, treatment == 1) %>%
  pull(r_log_prdct_qty)

r_log_prdct_spend_treat0 <- collapsed_data %>%
  filter(year == 2015, treatment == 0) %>%
  pull(r_log_prdct_spend)

r_log_prdct_spend_treat1 <- collapsed_data %>%
  filter(year == 2015, treatment == 1) %>%
  pull(r_log_prdct_spend)

r_log_old_device_qty_treat0 <- collapsed_data %>%
  filter(year == 2015, treatment == 0) %>%
  pull(r_log_old_device_qty)

r_log_old_device_qty_treat1 <- collapsed_data %>%
  filter(year == 2015, treatment == 1) %>%
  pull(r_log_old_device_qty)

collapsed_data <- collapsed_data %>%
  mutate(
    r_log_prdct_price_2015 = ifelse(
      treatment == 0,
      r_log_prdct_price_2015_treat0,
      r_log_prdct_price_2015_treat1
    ),
    r_log_prdct_qty_2015 = ifelse(
      treatment == 0,
      r_log_prdct_qty_2015_treat0,
      r_log_prdct_qty_2015_treat1
    ),
    r_log_prdct_spend_2015 = ifelse(
      treatment == 0,
      r_log_prdct_spend_treat0,
      r_log_prdct_spend_treat1
    ),
    r_log_old_device_qty_2015 = ifelse(
      treatment == 0,
      r_log_old_device_qty_treat0,
      r_log_old_device_qty_treat1
    ),
    normalized_log_prdct_price = r_log_prdct_price - r_log_prdct_price_2015,
    normalized_log_prdct_qty = r_log_prdct_qty - r_log_prdct_qty_2015,
    normalized_log_prdct_spend = r_log_prdct_spend - r_log_prdct_spend_2015,
    normalized_log_old_device_qty = r_log_old_device_qty - r_log_old_device_qty_2015,
    treatment = factor(
      treatment,
      levels = c(0, 1),
      labels = c("Control", "Treated")
    )
  )

# Plot normalized log average price by treatment status
ggplot(collapsed_data,
       aes(x = year, y = normalized_log_prdct_price, color = treatment)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = seq(2012, 2022, by = 1)) +
  labs(
    title = "Normalized Log Average Price by Treatment Status",
    subtitle = paste(
      "Optimal Matching Parameters: Caliper =",
      round(optimal_params$caliper, 2),
      "| Ratio =",
      optimal_params$ratio
    ),
    x = "Year",
    y = "Normalized Log Average Price",
    color = "Treatment Status"
  ) +
  theme_minimal() +
  theme(legend.position = c(0.9, 0.7))
ggplot(collapsed_data,
       aes(x = year, y = normalized_log_prdct_qty, color = treatment)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = seq(2012, 2022, by = 1)) +
  labs(
    title = "Normalized Log Qty by Treatment Status",
    subtitle = paste(
      "Optimal Matching Parameters: Caliper =",
      round(optimal_params$caliper, 2),
      "| Ratio =",
      optimal_params$ratio
    ),
    x = "Year",
    y = "Normalized Log Qty",
    color = "Treatment Status"
  ) +
  theme_minimal() +
  theme(legend.position = c(0.9, 0.7))
ggplot(collapsed_data,
       aes(x = year, y = normalized_log_prdct_spend, color = treatment)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = seq(2012, 2022, by = 1)) +
  labs(
    title = "Normalized Log Spend by Treatment Status",
    subtitle = paste(
      "Optimal Matching Parameters: Caliper =",
      round(optimal_params$caliper, 2),
      "| Ratio =",
      optimal_params$ratio
    ),
    x = "Year",
    y = "Normalized Log Spend",
    color = "Treatment Status"
  ) +
  theme_minimal() +
  theme(legend.position = c(0.9, 0.7))


ggplot(collapsed_data,
       aes(x = year, y = normalized_log_old_device_qty, color = treatment)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = seq(2012, 2022, by = 1)) +
  labs(
    title = "Normalized Log Spend by Treatment Status",
    subtitle = paste(
      "Optimal Matching Parameters: Caliper =",
      round(optimal_params$caliper, 2),
      "| Ratio =",
      optimal_params$ratio
    ),
    x = "Year",
    y = "Normalized Log Spend",
    color = "Treatment Status"
  ) +
  theme_minimal() +
  theme(legend.position = c(0.9, 0.7))

