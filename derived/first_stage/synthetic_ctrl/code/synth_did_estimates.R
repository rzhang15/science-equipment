# -----------------------------------------------------------
# FULL PIPELINE: Synthetic Control -> Stacked DiD (MANUAL PLOTTING)
# -----------------------------------------------------------
library(tidyverse)
library(Synth)
library(haven)
library(fixest) 
library(broom)
library(ggplot2) # We will use standard ggplot for total control

# --- 1. Setup ---
# [Adjust your paths]
DATA_INPUT  <- "../external/samp/category_yr_tfidf.dta"
OUTPUT_DIR  <- "../output/figures/"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# --- 2. Load and Prep Data ---
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

# --- HELPER: Extract Coeffs & CIs for Plotting (FIXED REGEX) ---
get_plot_data <- function(model, model_name = "Model") {
  # 1. Get the tidy table with Confidence Intervals
  df <- broom::tidy(model, conf.int = TRUE, conf.level = 0.95)
  
  # 2. Filter for the time interactions and extract the year robustly
  df <- df %>% 
    filter(str_detect(term, "rel_year")) %>% 
    mutate(
      # FIX: Robust Regex using lookbehind. 
      # Finds "rel_year::" and grabs the number immediately following it.
      rel = as.numeric(str_extract(term, "(?<=rel_year::)-?\\d+")),
      
      b = estimate,
      se = std.error,
      ub = conf.high,
      lb = conf.low,
      upper = round(ub, 1),
      year = rel + 2014, # Adjust to your specific event year
      model_label = model_name
    ) %>%
    # Remove any rows where extraction failed (e.g. if a term didn't match)
    filter(!is.na(rel)) %>%
    select(model_label, b, se, ub, lb, rel, upper, year)
  
  return(df)
}

# ==============================================================================
# PART 3: MAIN LOOP (SCM + Local DiD)
# ==============================================================================

for (mkt in treated_categories) {
  clean_mkt <- gsub("[^[:alnum:]]", "_", mkt) 
  curr_id <- unique(panel$category_num[panel$category == mkt])
  
  # --- A. Run Synthetic Control ---
  dp_out <- tryCatch({
    dataprep(
      foo = as.data.frame(panel),
      predictors = c("spend_2013"),
      predictors.op = "mean",
      time.predictors.prior = 2010:2013,
      special.predictors = list(
        list("avg_log_price", 2013, "mean"),
        list("avg_log_price", 2012, "mean"),
        list("avg_log_price", 2011, "mean"),
        list("avg_log_price", 2010, "mean")
      ),
      dependent = "avg_log_price",
      unit.variable = "category_num",
      unit.names.variable = "category",
      time.variable = "year",
      treatment.identifier = curr_id,
      controls.identifier = control_ids,
      time.optimize.ssr = 2010:2013,
      time.plot = 2010:2019
    )
  }, error = function(e) { message(paste("Dataprep fail:", mkt)); return(NULL) })
  
  if (is.null(dp_out)) next
  
  s_out <- tryCatch({ synth(dp_out) }, error = function(e) { message(paste("Synth fail:", mkt)); return(NULL) })
  if (is.null(s_out)) next
  
  # --- B. Extract Weights & Build Stack ---
  control_weights <- data.frame(
    category_num = as.numeric(rownames(s_out$solution.w)),
    weight = as.numeric(s_out$solution.w)
  )
  
  stack_data <- bind_rows(data.frame(category_num = curr_id, weight = 1), control_weights) %>%
    mutate(stack_id = curr_id)
  
  stack_list[[mkt]] <- stack_data
  
  # --- C. Plot 1: SCM Trends ---
  observed <- dp_out$Y1plot
  synthetic <- dp_out$Y0plot %*% s_out$solution.w
  plot_df <- data.frame(year = as.numeric(rownames(observed)),
                        observed = as.numeric(observed),
                        synthetic = as.numeric(synthetic)) %>%
    pivot_longer(cols = c(observed, synthetic), names_to = "group", values_to = "price")
  
  p_trend <- ggplot(plot_df, aes(x = year, y = price, color = group, linetype = group)) +
    geom_line(size = 1.2) + geom_point() +
    geom_vline(xintercept = 2013.5, linetype = "dashed", color = "darkred") +
    scale_color_manual(values = c("observed" = "black", "synthetic" = "blue")) +
    labs(title = paste("SCM Fit:", mkt), x = "Year", y = "Avg Log Price") +
    theme_minimal()
  
  ggsave(filename = paste0(OUTPUT_DIR, "trend_", clean_mkt, ".pdf"), plot = p_trend, width = 8, height = 5)
  
  # --- D. Run Local Event Study ---
  local_panel <- inner_join(panel, stack_data, by = "category_num") %>%
    mutate(rel_year = year - 2014, is_treated = (category_num == curr_id))
  
  est_local <- feols(avg_log_price ~ i(rel_year, is_treated, ref = -1) | year + category_num, 
                     data = local_panel, weights = ~weight,cluster = ~category_num)
  
  # Get Stats (Manually extracted)
  stats_df <- get_plot_data(est_local, model_name = mkt)
  
  # Save .dta
  write_dta(stats_df, paste0(OUTPUT_DIR, "est_", clean_mkt, ".dta"))
  
  # --- E. Plot 2: Coefficients WITH VISIBLE CIs ---
  p_coef <- ggplot(stats_df, aes(x = rel, y = b)) +
    geom_hline(yintercept = 0, color = "black", size = 0.5) +
    geom_vline(xintercept = -1, linetype = "dashed", color = "gray50") +
    # The Error Bars
    geom_errorbar(aes(ymin = lb, ymax = ub), width = 0.2, size = 0.8, color = "navy") +
    # The Points
    geom_point(size = 3, color = "navy") +
    labs(title = paste("Event Study:", mkt), x = "Time to Treatment", y = "Estimate") +
    theme_minimal()
  p_coef
  ggsave(filename = paste0(OUTPUT_DIR, "coef_", clean_mkt, ".pdf"), plot = p_coef, width = 8, height = 5)
}

# ==============================================================================
# PART 4: GLOBAL ANALYSIS
# ==============================================================================

if (length(stack_list) == 0) stop("No successful matches found.")

weights_df <- bind_rows(stack_list)

synth_panel <- inner_join(panel, weights_df, by = "category_num", relationship = "many-to-many") %>%
  group_by(stack_id) %>%
  mutate(
    treated_spend_2013 = max(spend_2013[category_num == stack_id], na.rm = TRUE),
    composite_weight = weight * treated_spend_2013,
    is_treated_in_stack = (category_num == stack_id),
    rel_year = year - 2014
  ) %>%
  ungroup() %>%
  filter(composite_weight > 0)

# --- Model A: Pooled ---
est_pooled <- feols(avg_log_price ~ i(rel_year, is_treated_in_stack, ref = -1) | 
                      year + category_num, 
                    data = synth_panel, weights = ~composite_weight, cluster = ~stack_id)

# --- Model B: Stacked ---
est_stacked <- feols(avg_log_price ~ i(rel_year, is_treated_in_stack, ref = -1) | 
                       stack_id^year + stack_id^category_num, 
                     data = synth_panel, weights = ~composite_weight, cluster = ~stack_id)

# --- Save Stats ---
stats_pooled <- get_plot_data(est_pooled, "Pooled")
write_dta(stats_pooled, paste0(OUTPUT_DIR, "est_pooled.dta"))

stats_stacked <- get_plot_data(est_stacked, "Stacked")
write_dta(stats_stacked, paste0(OUTPUT_DIR, "est_stacked.dta"))

# --- Compare Plot (Pooled vs Stacked) ---
compare_df <- bind_rows(stats_pooled, stats_stacked)

p_compare <- ggplot(compare_df, aes(x = rel, y = b, color = model_label, group = model_label)) +
  geom_hline(yintercept = 0, color = "black", size = 0.5) +
  geom_vline(xintercept = -1, linetype = "dashed", color = "gray50") +
  # Points and Lines
  geom_point(size = 3, position = position_dodge(width = 0.4)) +
  geom_line(position = position_dodge(width = 0.4), alpha = 0.3) +
  # Error Bars (Dodged so they don't overlap)
  geom_errorbar(aes(ymin = lb, ymax = ub), width = 0.2, size = 0.8, 
                position = position_dodge(width = 0.4)) +
  scale_color_manual(values = c("Pooled" = "firebrick", "Stacked" = "navy")) +
  labs(title = "DiD Comparison: Pooled vs Stacked", 
       subtitle = "Weighted by Market Size",
       x = "Years Relative to Treatment", y = "Effect on Log Price") +
  theme_minimal() +
  theme(legend.position = "bottom")
p_compare
ggsave(paste0(OUTPUT_DIR, "plot_pooled_vs_stacked.pdf"), p_compare, width = 10, height = 6)

print("Pipeline Complete.")
