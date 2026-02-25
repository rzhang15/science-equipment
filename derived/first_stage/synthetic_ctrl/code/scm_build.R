# =============================================================================
# 01_scm_build.R
#
# Synthetic Control Method: Build synthetic controls for each treated category,
# generate trend plots, and construct a stacked panel for DiD estimation.
#
# Outputs:
#   ../output/synth_stacked_panel.dta   — stacked panel for 02_scm_did.R
#   ../output/scm_weights.csv           — per-market SCM donor weights
#   ../output/figures/trend_*.pdf       — treated vs synthetic trend plots
# =============================================================================

library(tidyverse)
library(Synth)
library(haven)
library(stringr)
set.seed(8975)

# ---------------------------
# Setup
# ---------------------------
setwd("~/sci_eq/derived/first_stage/synthetic_ctrl/code")
DATA_INPUT <- "../external/samp/category_yr_tfidf.dta"
OUTPUT_DIR <- "../output/figures/"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Treatment year: post-treatment starts at 2014
TREAT_YEAR <- 2014
PRE_YEARS  <- 2010:2013
POST_YEARS <- 2014:2019
ALL_YEARS  <- 2010:2019

# ---------------------------
# Load and Prep
# ---------------------------
cat("Loading data...\n")
panel <- read_dta(DATA_INPUT) %>%
  mutate(
    category = as.character(category),
    category_num = as.numeric(as.factor(category)),
    treated = as.numeric(treated)
  ) %>%
  filter(year >= min(ALL_YEARS))

# Drop categories that have any NA in the outcome — Synth cannot handle them
panel <- panel %>%
  group_by(category) %>%
  filter(!any(is.na(avg_log_price))) %>%
  ungroup()

# Verify panel balance: each category should have all years
year_counts <- panel %>% count(category) %>% filter(n != length(ALL_YEARS))
if (nrow(year_counts) > 0) {
  cat("WARNING: Unbalanced panel — these categories don't have all years:\n")
  print(year_counts)
  # Drop unbalanced categories
  panel <- panel %>%
    group_by(category) %>%
    filter(n() == length(ALL_YEARS)) %>%
    ungroup()
  cat("Dropped unbalanced categories. Remaining:", n_distinct(panel$category), "\n")
}

# Rebuild category_num after filtering (must be contiguous for Synth)
panel <- panel %>%
  mutate(category_num = as.numeric(as.factor(category)))

treated_categories <- unique(panel$category[panel$treated == 1])
control_ids <- unique(panel$category_num[panel$treated == 0])

cat("Panel dimensions:", dim(panel), "\n")
cat("Years:", paste(sort(unique(panel$year)), collapse = ", "), "\n")
cat("Treated categories:", length(treated_categories), "\n")
cat("Control categories:", length(control_ids), "\n\n")

# ---------------------------
# Main SCM Loop
# ---------------------------
stack_list    <- list()
weights_list  <- list()
fit_summary   <- list()
failed_markets <- c()

for (mkt in treated_categories) {
  cat("Processing:", mkt, "... ")
  
  curr_id <- unique(panel$category_num[panel$category == mkt])
  clean_name <- str_replace_all(mkt, "[^a-zA-Z0-9_-]", "_")
  
  # --- A. Synth Data Prep ---
  dp_out <- tryCatch({
    dataprep(
      foo = as.data.frame(panel),
      predictors = c("spend_2013"),
      predictors.op = "mean",
      time.predictors.prior = PRE_YEARS,
      special.predictors = list(
        list("avg_log_price", 2013, "mean"),
        list("avg_log_price", 2012, "mean"),
        list("avg_log_price", 2011, "mean")
      ),
      dependent = "avg_log_price",
      unit.variable = "category_num",
      unit.names.variable = "category",
      time.variable = "year",
      treatment.identifier = curr_id,
      controls.identifier = control_ids,
      time.optimize.ssr = PRE_YEARS,
      time.plot = ALL_YEARS
    )
  }, error = function(e) {
    message("dataprep failed: ", e$message)
    return(NULL)
  })
  
  if (is.null(dp_out)) {
    failed_markets <- c(failed_markets, mkt)
    cat("FAILED (dataprep)\n")
    next
  }
  
  # --- B. Run Synth ---
  s_out <- tryCatch({
    synth(dp_out)
  }, error = function(e) {
    message("synth() failed: ", e$message)
    return(NULL)
  })
  
  if (is.null(s_out)) {
    failed_markets <- c(failed_markets, mkt)
    cat("FAILED (synth)\n")
    next
  }
  
  # --- C. Extract Weights ---
  control_weights <- data.frame(
    category_num = as.numeric(rownames(s_out$solution.w)),
    weight = as.numeric(s_out$solution.w)
  )
  
  # Keep donors with non-trivial weight
  active_donors <- control_weights %>% filter(weight > 0.001)
  
  # Look up category names for the donors
  cat_lookup <- panel %>% distinct(category_num, category)
  active_donors_named <- active_donors %>%
    left_join(cat_lookup, by = "category_num")
  
  weights_list[[mkt]] <- active_donors_named %>%
    mutate(treated_market = mkt)
  
  # Build stack: treated unit (weight=1) + all control donors (with SCM weights)
  treated_row <- data.frame(category_num = curr_id, weight = 1)
  stack_data <- bind_rows(treated_row, control_weights) %>%
    mutate(stack_id = curr_id)
  
  stack_list[[mkt]] <- stack_data
  
  # --- D. Extract Trend Data for Plot ---
  observed  <- dp_out$Y1plot
  synthetic <- dp_out$Y0plot %*% s_out$solution.w
  
  plot_df <- data.frame(
    year = as.numeric(rownames(observed)),
    observed = as.numeric(observed),
    synthetic = as.numeric(synthetic)
  ) %>%
    pivot_longer(cols = c(observed, synthetic),
                 names_to = "group", values_to = "price")
  
  # Pre-treatment RMSPE
  pre_obs  <- as.numeric(observed[as.character(PRE_YEARS), ])
  pre_syn  <- as.numeric(synthetic[as.character(PRE_YEARS), ])
  rmspe    <- sqrt(mean((pre_obs - pre_syn)^2))
  
  # Post-treatment RMSPE
  post_obs  <- as.numeric(observed[as.character(POST_YEARS), ])
  post_syn  <- as.numeric(synthetic[as.character(POST_YEARS), ])
  post_rmspe <- sqrt(mean((post_obs - post_syn)^2))
  
  fit_summary[[mkt]] <- data.frame(
    treated_market = mkt,
    pre_rmspe = rmspe,
    post_rmspe = post_rmspe,
    ratio = post_rmspe / max(rmspe, 1e-10),
    n_donors = nrow(active_donors)
  )
  
  # --- E. Trend Plot ---
  tryCatch({
    p <- ggplot(plot_df, aes(x = year, y = price, color = group, linetype = group)) +
      geom_line(linewidth = 1.2) +
      geom_point() +
      geom_vline(xintercept = TREAT_YEAR - 0.5, linetype = "dashed", color = "darkred") +
      scale_color_manual(
        values = c("observed" = "black", "synthetic" = "steelblue"),
        labels = c("Actual", "Synthetic")
      ) +
      scale_linetype_manual(
        values = c("observed" = "solid", "synthetic" = "dashed"),
        labels = c("Actual", "Synthetic")
      ) +
      labs(
        title = paste("SCM:", mkt),
        subtitle = paste0("Pre-RMSPE: ", round(rmspe, 5),
                          "  |  Donors: ", nrow(active_donors)),
        x = "Year", y = "Avg Log Price",
        caption = "Dashed red line = treatment onset"
      ) +
      theme_minimal(base_size = 12) +
      scale_x_continuous(breaks = ALL_YEARS) +
      theme(legend.position = "bottom", legend.title = element_blank())
    
    ggsave(paste0(OUTPUT_DIR, "trend_", clean_name, ".pdf"),
           plot = p, width = 8, height = 5)
    print(p)
  }, error = function(e) {
    message("Plot failed for ", mkt, ": ", e$message)
  })
  
  cat("OK (RMSPE:", round(rmspe, 5), ", donors:", nrow(active_donors), ")\n")
}

# ---------------------------
# Summary
# ---------------------------
cat("\n====================================================\n")
cat("SCM SUMMARY\n")
cat("====================================================\n")
cat("Treated markets attempted:", length(treated_categories), "\n")
cat("Successful:", length(stack_list), "\n")
cat("Failed:", length(failed_markets), "\n")

if (length(failed_markets) > 0) {
  cat("Failed markets:\n")
  print(failed_markets)
}

# Save fit quality summary
if (length(fit_summary) > 0) {
  fit_df <- do.call(rbind, fit_summary) %>% arrange(desc(ratio))
  cat("\nFit quality (sorted by post/pre RMSPE ratio):\n")
  print(fit_df)
  write_csv(fit_df, "../output/scm_fit_summary.csv")
}

# Save donor weights
if (length(weights_list) > 0) {
  all_weights <- do.call(rbind, weights_list)
  rownames(all_weights) <- NULL
  write_csv(all_weights, "../output/scm_weights.csv")
  cat("\nSaved SCM donor weights to scm_weights.csv\n")
}

# ---------------------------
# Build Stacked Panel
# ---------------------------
if (length(stack_list) == 0) {
  stop("No successful SCM fits — cannot build stacked panel.")
}

cat("\nBuilding stacked panel...\n")

weights_df <- bind_rows(stack_list)

# Inner join: keep only units that appear in at least one stack
synth_panel <- inner_join(panel, weights_df, by = "category_num",
                          relationship = "many-to-many")

# Create DiD variables
synth_panel <- synth_panel %>%
  mutate(
    is_treated_in_stack = (category_num == stack_id),
    rel_year = year - TREAT_YEAR,
    post = as.numeric(year >= TREAT_YEAR),
    treat_post = is_treated_in_stack * post
  )

# Add treated market's spend_2013 for composite weighting (used in script 2)
synth_panel <- synth_panel %>%
  group_by(stack_id) %>%
  mutate(
    treated_spend_2013 = max(spend_2013[category_num == stack_id], na.rm = TRUE)
  ) %>%
  ungroup()

cat("Stacked panel dimensions:", dim(synth_panel), "\n")
cat("Unique stacks (treated markets):", n_distinct(synth_panel$stack_id), "\n")
cat("Unique categories in panel:", n_distinct(synth_panel$category), "\n")

# Save
write_dta(synth_panel, "../output/synth_stacked_panel.dta")
cat("Saved synth_stacked_panel.dta\n")

cat("\n01_scm_build.R complete.\n")
