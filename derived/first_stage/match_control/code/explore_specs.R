# =============================================================================
# Round 3: Matching on pre-treatment linear time trends
#
# For each category, regress outcome/covariates on year in the pre-period
# and extract the slope (and optionally intercept). Use these as matching
# covariates. This directly targets the parallel trends assumption.
#
# Compares trend-based specs to R2 winner (avg_log_price levels 2011-2013).
# =============================================================================

library(tidyverse)
library(MatchIt)
library(haven)
library(broom)
set.seed(8975)

setwd("~/sci_eq/derived/first_stage/match_control/code")
dir.create("../output/spec_search", recursive = TRUE, showWarnings = FALSE)

# ---------------------------
# Load data
# ---------------------------
cat("Loading data...\n")
panel <- read_dta("../external/samp/category_yr_tfidf.dta") %>%
  mutate(category = as.character(category))

cat("Panel:", n_distinct(panel$category), "categories x",
    n_distinct(panel$year), "years\n\n")

# ---------------------------
# Compute pre-treatment trend coefficients per category
# ---------------------------
# Use pre-period only (up to 2013)
pre_panel <- panel %>% filter(year <= 2013)

# Center year so intercept = approximate midpoint level (reduces collinearity)
# For 2011-2013: center at 2012; for 2010-2013: center at 2011.5
# We'll use year_c = year - 2012 so intercept ≈ level at 2012

pre_panel <- pre_panel %>% mutate(year_c = year - 2012)

# Function to extract slope + intercept from a regression of var on year
get_trend <- function(df, var) {
  y <- df[[var]]
  x <- df$year_c
  if (sum(!is.na(y)) < 2) {
    return(data.frame(slope = NA_real_, intercept = NA_real_))
  }
  fit <- lm(y ~ x)
  data.frame(slope = coef(fit)[2], intercept = coef(fit)[1])
}

# Compute trends for each variable of interest
cat("Computing per-category pre-treatment trends...\n")

trend_vars <- c("avg_log_price", "log_raw_spend", "log_raw_price",
                "raw_spend", "raw_price", "num_suppliers")

trends <- pre_panel %>%
  group_by(category, treated, spend_2013) %>%
  group_modify(~ {
    result <- data.frame(category_placeholder = 1)
    for (v in trend_vars) {
      tr <- get_trend(.x, v)
      result[[paste0(v, "_slope")]] <- tr$slope
      result[[paste0(v, "_intercept")]] <- tr$intercept
    }
    result %>% select(-category_placeholder)
  }) %>%
  ungroup()

cat("Computed trends for", nrow(trends), "categories\n")

# Also grab 2013 levels for hybrid specs
levels_2013 <- panel %>%
  filter(year == 2013) %>%
  select(category, avg_log_price_2013 = avg_log_price,
         log_raw_spend_2013 = log_raw_spend,
         log_raw_price_2013 = log_raw_price,
         num_suppliers_2013 = num_suppliers,
         raw_spend_2013 = raw_spend)

# Merge trends + 2013 levels
data_wide <- trends %>%
  left_join(levels_2013, by = "category") %>%
  mutate(log_spend_2013 = log(spend_2013 + 1))

# Also get year-specific levels for the R2 winner benchmark
levels_wide <- panel %>%
  filter(year <= 2013) %>%
  select(category, year, avg_log_price) %>%
  pivot_wider(names_from = year, names_prefix = "avg_log_price_",
              values_from = avg_log_price)

data_wide <- data_wide %>%
  left_join(levels_wide, by = "category")

cat("\nWide data:", nrow(data_wide), "categories x", ncol(data_wide), "columns\n")

# Print summary of trend variables
cat("\n--- Trend variable summaries (treated vs control) ---\n")
for (v in c("avg_log_price_slope", "avg_log_price_intercept",
            "log_raw_spend_slope", "log_raw_price_slope")) {
  t_vals <- data_wide %>% filter(treated == 1) %>% pull(!!sym(v))
  c_vals <- data_wide %>% filter(treated == 0) %>% pull(!!sym(v))
  cat(sprintf("  %-30s | Treated: mean=%.4f sd=%.4f | Control: mean=%.4f sd=%.4f\n",
              v, mean(t_vals, na.rm = TRUE), sd(t_vals, na.rm = TRUE),
              mean(c_vals, na.rm = TRUE), sd(c_vals, na.rm = TRUE)))
}

# ---------------------------
# Define specifications
# ---------------------------
specs <- list(
  # === Pure trend-based ===
  # Price slope only
  t01_alp_slope = c("avg_log_price_slope"),
  
  # Price slope + intercept (captures both level and trajectory)
  t02_alp_slope_int = c("avg_log_price_slope", "avg_log_price_intercept"),
  
  # log_raw_price slope only
  t03_lrp_slope = c("log_raw_price_slope"),
  
  # log_raw_price slope + intercept
  t04_lrp_slope_int = c("log_raw_price_slope", "log_raw_price_intercept"),
  
  # === Trend + 2013 level hybrids ===
  # Price slope + 2013 price level
  t05_alp_slope_level13 = c("avg_log_price_slope", "avg_log_price_2013"),
  
  # Price slope + intercept + 2013 level (redundant? intercept ≈ 2012 level)
  t06_alp_slope_int_level13 = c("avg_log_price_slope", "avg_log_price_intercept",
                                "avg_log_price_2013"),
  
  # Price slope + 2013 spend level
  t07_alp_slope_spend13 = c("avg_log_price_slope", "log_raw_spend_2013"),
  
  # Price slope + 2013 price level + 2013 spend level
  t08_alp_slope_level13_spend13 = c("avg_log_price_slope", "avg_log_price_2013",
                                    "log_raw_spend_2013"),
  
  # Price slope + intercept + spend 2013
  t09_alp_slope_int_spend13 = c("avg_log_price_slope", "avg_log_price_intercept",
                                "log_raw_spend_2013"),
  
  # === Multi-variable trends ===
  # Price slope + spend slope
  t10_alp_spend_slopes = c("avg_log_price_slope", "log_raw_spend_slope"),
  
  # Price slope + spend slope + price intercept
  t11_alp_spend_slopes_int = c("avg_log_price_slope", "log_raw_spend_slope",
                               "avg_log_price_intercept"),
  
  # Price slope + spend slope + 2013 levels
  t12_slopes_levels13 = c("avg_log_price_slope", "log_raw_spend_slope",
                          "avg_log_price_2013", "log_raw_spend_2013"),
  
  # Price slope + supplier trend
  t13_alp_supp_slopes = c("avg_log_price_slope", "num_suppliers_slope"),
  
  # All slopes: price + spend + suppliers
  t14_three_slopes = c("avg_log_price_slope", "log_raw_spend_slope",
                       "num_suppliers_slope"),
  
  # === Price intercept + slope with secondary market chars ===
  t15_alp_slope_int_suppliers = c("avg_log_price_slope", "avg_log_price_intercept",
                                  "num_suppliers_2013"),
  
  # Everything: slope + intercept + spend + suppliers
  t16_kitchen_sink = c("avg_log_price_slope", "avg_log_price_intercept",
                       "log_raw_spend_2013", "num_suppliers_2013"),
  
  # === R2 winner as benchmark ===
  bench_alp_levels_11_13 = c("avg_log_price_2011", "avg_log_price_2012",
                             "avg_log_price_2013")
)

cat("\nTesting", length(specs), "specifications\n\n")

# ---------------------------
# Evaluation function (same as R2)
# ---------------------------
OUTCOME_VAR <- "avg_log_price"

evaluate_spec <- function(spec_name, covariates, data_wide, panel, match_ratio) {
  cat(sprintf("--- %s (ratio=%d): %s ---\n", spec_name, match_ratio,
              paste(covariates, collapse = ", ")))
  
  all_treated <- data_wide %>% filter(treated == 1)
  all_controls <- data_wide %>% filter(treated == 0) %>% drop_na(all_of(covariates))
  
  treated_has_na <- all_treated %>%
    filter(if_any(all_of(covariates), is.na)) %>%
    pull(category)
  treated_clean <- all_treated %>% filter(!category %in% treated_has_na)
  
  n_treated_total <- nrow(all_treated)
  n_treated_clean <- nrow(treated_clean)
  n_controls <- nrow(all_controls)
  
  if (n_treated_clean == 0 || n_controls < match_ratio) {
    cat("  SKIPPED\n\n"); return(NULL)
  }
  
  match_input <- bind_rows(treated_clean, all_controls)
  match_formula <- as.formula(paste("treated ~", paste(covariates, collapse = " + ")))
  
  model <- tryCatch({
    matchit(formula = match_formula, method = "nearest",
            distance = "mahalanobis", data = match_input,
            ratio = match_ratio, replace = TRUE)
  }, error = function(e) { cat("  FAILED:", e$message, "\n\n"); NULL })
  
  if (is.null(model)) return(NULL)
  
  bal <- tryCatch({
    s <- summary(model)
    smd_vals <- abs(s$sum.matched[, "Std. Mean Diff."])
    mean(smd_vals, na.rm = TRUE)
  }, error = function(e) NA_real_)
  
  max_smd <- tryCatch({
    s <- summary(model)
    max(abs(s$sum.matched[, "Std. Mean Diff."]), na.rm = TRUE)
  }, error = function(e) NA_real_)
  
  # Extract match pairs
  match_matrix <- model$match.matrix
  match_pairs_list <- list()
  for (i in seq_len(nrow(match_matrix))) {
    treated_idx <- as.integer(rownames(match_matrix)[i])
    treated_cat <- match_input$category[treated_idx]
    control_indices <- as.integer(match_matrix[i, ])
    control_indices <- control_indices[!is.na(control_indices)]
    if (length(control_indices) == 0) next
    control_cats <- unique(match_input$category[control_indices])
    match_pairs_list[[treated_cat]] <- data.frame(
      treated_market = treated_cat, control_market = control_cats)
  }
  
  if (length(match_pairs_list) == 0) return(NULL)
  match_pairs <- do.call(rbind, match_pairs_list)
  
  # Pre-trend alignment
  pre_trend_gaps <- c()
  for (treated_cat in unique(match_pairs$treated_market)) {
    controls <- match_pairs %>%
      filter(treated_market == treated_cat) %>% pull(control_market) %>% unique()
    
    trend_data <- panel %>%
      filter(category %in% c(treated_cat, controls), year <= 2013) %>%
      select(category, year, treated, spend_2013, all_of(OUTCOME_VAR)) %>%
      group_by(category) %>%
      mutate(outcome_adj = .data[[OUTCOME_VAR]] - .data[[OUTCOME_VAR]][year == 2013]) %>%
      ungroup()
    
    treated_trend <- trend_data %>% filter(category == treated_cat) %>%
      select(year, outcome_adj) %>% rename(treated_outcome = outcome_adj)
    
    control_trend <- trend_data %>% filter(category %in% controls) %>%
      group_by(year) %>%
      summarise(control_outcome = weighted.mean(outcome_adj, w = spend_2013, na.rm = TRUE),
                .groups = "drop")
    
    merged <- inner_join(treated_trend, control_trend, by = "year")
    if (nrow(merged) > 0)
      pre_trend_gaps <- c(pre_trend_gaps,
                          mean(abs(merged$treated_outcome - merged$control_outcome), na.rm = TRUE))
  }
  
  mean_pre_gap <- mean(pre_trend_gaps, na.rm = TRUE)
  median_pre_gap <- median(pre_trend_gaps, na.rm = TRUE)
  p75_pre_gap <- quantile(pre_trend_gaps, 0.75, na.rm = TRUE)
  p90_pre_gap <- quantile(pre_trend_gaps, 0.90, na.rm = TRUE)
  pct_good <- mean(pre_trend_gaps < 0.05)
  pct_ok <- mean(pre_trend_gaps < 0.10)
  
  # Post gap
  post_gaps <- c()
  for (treated_cat in unique(match_pairs$treated_market)) {
    controls <- match_pairs %>% filter(treated_market == treated_cat) %>%
      pull(control_market) %>% unique()
    
    td <- panel %>% filter(category %in% c(treated_cat, controls), year >= 2014) %>%
      select(category, year, treated, spend_2013, all_of(OUTCOME_VAR))
    
    t_post <- td %>% filter(category == treated_cat) %>%
      summarise(m = mean(.data[[OUTCOME_VAR]], na.rm = TRUE)) %>% pull(m)
    c_post <- td %>% filter(category %in% controls) %>%
      summarise(m = weighted.mean(.data[[OUTCOME_VAR]], w = spend_2013, na.rm = TRUE)) %>% pull(m)
    
    if (!is.na(t_post) && !is.na(c_post)) post_gaps <- c(post_gaps, t_post - c_post)
  }
  
  cat(sprintf("  SMD: mean=%.4f max=%.4f | Pre-gap: mean=%.4f med=%.4f | Good: %.0f%% | OK: %.0f%%\n",
              bal, max_smd, mean_pre_gap, median_pre_gap, pct_good*100, pct_ok*100))
  
  data.frame(
    spec = spec_name,
    covariates = paste(covariates, collapse = " + "),
    n_covariates = length(covariates),
    match_ratio = match_ratio,
    n_treated_matched = n_distinct(match_pairs$treated_market),
    n_treated_dropped = n_treated_total - n_treated_clean,
    n_controls_available = n_controls,
    mean_abs_smd = round(bal, 4),
    max_abs_smd = round(max_smd, 4),
    pre_trend_mean_gap = round(mean_pre_gap, 4),
    pre_trend_median_gap = round(median_pre_gap, 4),
    pre_trend_p75_gap = round(p75_pre_gap, 4),
    pre_trend_p90_gap = round(p90_pre_gap, 4),
    pct_good_pretrend = round(pct_good, 4),
    pct_ok_pretrend = round(pct_ok, 4),
    post_mean_gap = round(mean(post_gaps, na.rm = TRUE), 4),
    stringsAsFactors = FALSE
  )
}

# ---------------------------
# Run all specs
# ---------------------------
results_list <- list()

# Main run: ratio=3
for (spec_name in names(specs)) {
  res <- tryCatch(
    evaluate_spec(spec_name, specs[[spec_name]], data_wide, panel, match_ratio = 3),
    error = function(e) { cat("  ERROR:", e$message, "\n\n"); NULL }
  )
  if (!is.null(res)) results_list[[spec_name]] <- res
}

# Ratio sensitivity for top trend specs
cat("\n--- Ratio sensitivity ---\n\n")
ratio_test <- c("t01_alp_slope", "t02_alp_slope_int", "t05_alp_slope_level13")

for (spec_name in ratio_test) {
  for (r in c(1, 5)) {
    res_name <- paste0(spec_name, "_r", r)
    res <- tryCatch(
      evaluate_spec(res_name, specs[[spec_name]], data_wide, panel, match_ratio = r),
      error = function(e) { cat("  ERROR:", e$message, "\n\n"); NULL }
    )
    if (!is.null(res)) results_list[[res_name]] <- res
  }
}

# ---------------------------
# Compile and rank
# ---------------------------
results <- do.call(rbind, results_list) %>%
  as_tibble() %>%
  mutate(
    rank_pretrend = rank(pre_trend_mean_gap),
    rank_balance = rank(mean_abs_smd),
    rank_coverage = rank(n_treated_dropped),
    composite_rank = (2 * rank_pretrend + rank_balance + rank_coverage) / 4
  ) %>%
  arrange(composite_rank)

cat("\n================================================================\n")
cat("ROUND 3 RESULTS: TREND-BASED MATCHING\n")
cat("================================================================\n\n")

results %>%
  select(spec, covariates, match_ratio, n_treated_matched, n_treated_dropped,
         mean_abs_smd, max_abs_smd,
         pre_trend_mean_gap, pre_trend_median_gap, pre_trend_p90_gap,
         pct_good_pretrend, pct_ok_pretrend, composite_rank) %>%
  print(n = Inf, width = Inf)

cat("\n--- Top 5 by pre-trend alignment ---\n")
results %>%
  arrange(pre_trend_mean_gap) %>%
  slice_head(n = 5) %>%
  select(spec, covariates, match_ratio,
         mean_abs_smd, pre_trend_mean_gap, pct_good_pretrend, pct_ok_pretrend) %>%
  print(width = Inf)

cat("\n--- Trend specs vs R2 benchmark ---\n")
results %>%
  filter(match_ratio == 3) %>%
  arrange(pre_trend_mean_gap) %>%
  select(spec, covariates, mean_abs_smd, pre_trend_mean_gap,
         pct_good_pretrend, pct_ok_pretrend) %>%
  print(n = Inf, width = Inf)

write_csv(results, "../output/spec_search/spec_comparison_r3.csv")
cat("\nSaved to ../output/spec_search/spec_comparison_r3.csv\n")

cat("\nDone.\n")

