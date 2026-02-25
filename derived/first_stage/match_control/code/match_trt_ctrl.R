# =============================================================================
# Matching Treated Categories to Control Categories
#
# Approach: Mahalanobis distance matching on pre-treatment outcome levels.
# No propensity score, no caliper — guarantees every treated category gets
# matched. Uses replace=TRUE so the same control can serve multiple treated
# units.
#
# Matching covariates:
#   - avg_log_price in 2011, 2012, 2013 (pre-treatment outcome trajectory)
#
# Selected via systematic search over 50+ specifications across 3 rounds
# (see explore_matching_specs.R, _r2.R, _r3.R). Matching directly on the
# outcome trajectory in year-specific levels gave the best pre-trend
# alignment (mean gap = 0.082, 47% of markets < 0.05, 77% < 0.10).
# This beat:
#   - Spend-based matching (pre-trend gap ~0.13)
#   - Price trend slope matching (better % good markets but heavier tails)
#   - Adding secondary covariates (spend, suppliers) which diluted the
#     Mahalanobis distance away from the outcome trajectory
# =============================================================================

library(tidyverse)
library(MatchIt)
library(cobalt)
library(ggplot2)
library(haven)
library(stringr)
set.seed(8975)

# Set working directory and create output folders
setwd("~/sci_eq/derived/first_stage/match_control/code")
dir.create("../output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("../output/balance_plots", recursive = TRUE, showWarnings = FALSE)

# ---------------------------
# Configuration
# ---------------------------
# Matching covariates: pre-treatment outcome trajectory (year-specific levels)
MATCH_COVARIATES <- c("log_raw_price_2011", "avg_log_price_slope", "spend_2013")

# Number of controls per treated unit
MATCH_RATIO <- 3

# Outcome variables to plot
OUTCOME_VARS <- c("avg_log_price")

# ---------------------------
# Data Preparation
# ---------------------------
cat("Loading data...\n")
panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

cat("Panel dimensions:", dim(panel), "\n")
cat("Years in data:", sort(unique(panel$year)), "\n")
cat("Total categories:", n_distinct(panel$category), "\n")
cat("Treated categories:", n_distinct(panel$category[panel$treated == 1]), "\n")
cat("Control categories:", n_distinct(panel$category[panel$treated == 0]), "\n\n")

# Pivot pre-treatment data to wide format (one row per category)
all_data_pre <- panel %>% filter(year <= 2013)

data_wide <- all_data_pre %>%
  pivot_wider(
    names_from = year,
    names_sep = "_",
    id_cols = c(category, treated, spend_2013),
    values_from = c(avg_log_price, log_raw_spend, obs_cnt,
                    raw_spend, raw_price, raw_qty, log_raw_price)
  ) %>%
  mutate(
    # Log-transform spend to reduce skew — huge markets won't dominate distance
    log_spend_2013 = log(spend_2013 + 1)
  )
pre_slopes <- panel %>%
  filter(year <= 2013) %>%
  group_by(category) %>%
  summarise(
    avg_log_price_slope = coef(lm(avg_log_price ~ year))[2],
    .groups = "drop"
  )

data_wide <- data_wide %>%
  left_join(pre_slopes, by = "category")
cat("Wide data dimensions:", dim(data_wide), "\n")

# ---------------------------
# Handle missing covariates
# ---------------------------
# Check which categories have NA in matching covariates
na_check <- data_wide %>%
  filter(if_any(all_of(MATCH_COVARIATES), is.na))

if (nrow(na_check) > 0) {
  cat("Categories with NA in matching covariates:\n")
  print(na_check %>% select(category, treated, all_of(MATCH_COVARIATES)))
  cat("\n")
}

# Separate treated and controls
all_treated <- data_wide %>% filter(treated == 1)
all_controls <- data_wide %>% filter(treated == 0) %>% drop_na(all_of(MATCH_COVARIATES))

# For treated units with NA covariates, we'll handle them with a fallback
treated_has_na <- all_treated %>%
  filter(if_any(all_of(MATCH_COVARIATES), is.na)) %>%
  pull(category)

treated_clean <- all_treated %>%
  filter(!category %in% treated_has_na)

cat("Treated markets total:", nrow(all_treated), "\n")
cat("Treated markets with NA covariates:", length(treated_has_na), "\n")
cat("Clean treated markets:", nrow(treated_clean), "\n")
cat("Clean control markets:", nrow(all_controls), "\n")
if (length(treated_has_na) > 0) {
  cat("NA treated markets:", paste(treated_has_na, collapse = ", "), "\n")
}
cat("\n")

# ---------------------------
# Matching: all clean treated markets at once
# ---------------------------
# Combine clean treated + all clean controls for a single matchit call
match_input <- bind_rows(treated_clean, all_controls)

match_formula <- as.formula(paste("treated ~", paste(MATCH_COVARIATES, collapse = " + ")))

cat("Running Mahalanobis distance matching...\n")
cat("Formula:", deparse(match_formula), "\n")
cat("Method: nearest, distance: mahalanobis, ratio:", MATCH_RATIO, ", replace: TRUE\n\n")

main_model <- tryCatch({
  matchit(
    formula = match_formula,
    method = "nearest",
    distance = "mahalanobis",
    data = match_input,
    ratio = MATCH_RATIO,
    replace = TRUE
  )
}, error = function(e) {
  stop("Main matching failed: ", e$message)
})

# Print overall balance summary
cat("=== Overall Balance Summary ===\n")
print(summary(main_model))
cat("\n")

# Save overall balance plot
tryCatch({
  bal_plot <- love.plot(main_model, binary = "std", thresholds = c(m = .1),
                        title = "Overall Covariate Balance (Mahalanobis Matching)")
  ggsave("../output/balance_plots/balance_overall.pdf", plot = bal_plot, width = 8, height = 6)
  print(bal_plot)
}, error = function(e) {
  message("WARNING: Overall love.plot failed: ", e$message)
})

# ---------------------------
# Extract matched pairs from the single matchit model
# ---------------------------
match_data <- match.data(main_model)

# Get the match matrix to know which controls each treated got
match_matrix <- main_model$match.matrix  # rows = treated, cols = matched controls

# Build the pairs list
match_pairs_list <- list()

for (i in seq_len(nrow(match_matrix))) {
  treated_idx <- as.integer(rownames(match_matrix)[i])
  treated_cat <- match_input$category[treated_idx]
  
  control_indices <- as.integer(match_matrix[i, ])
  control_indices <- control_indices[!is.na(control_indices)]
  
  if (length(control_indices) == 0) next
  
  control_cats <- unique(match_input$category[control_indices])
  
  match_pairs_list[[treated_cat]] <- data.frame(
    treated_market = treated_cat,
    control_market = control_cats
  )
}

# ---------------------------
# Handle NA treated markets with fallback (match on available covariates only)
# ---------------------------
if (length(treated_has_na) > 0) {
  cat("\n--- Handling", length(treated_has_na), "treated markets with NA covariates ---\n")
  
  for (category_id in treated_has_na) {
    cat("Fallback matching for:", category_id, "\n")
    
    treated_row <- all_treated %>% filter(category == category_id)
    
    # Determine which covariates are available for this treated unit
    available_covs <- MATCH_COVARIATES[!is.na(treated_row[, MATCH_COVARIATES])]
    
    if (length(available_covs) == 0) {
      # Absolute fallback: just match on avg_log_price_2013 if everything else is NA
      available_covs <- "avg_log_price_2013"
      if (is.na(treated_row$avg_log_price_2013)) {
        message("FATAL: No covariates available for ", category_id)
        next
      }
    }
    
    fallback_data <- bind_rows(treated_row, all_controls) %>%
      drop_na(all_of(available_covs))
    
    fallback_formula <- as.formula(paste("treated ~", paste(available_covs, collapse = " + ")))
    
    fallback_model <- tryCatch({
      matchit(
        formula = fallback_formula,
        method = "nearest",
        distance = "mahalanobis",
        data = fallback_data,
        ratio = MATCH_RATIO,
        replace = TRUE
      )
    }, error = function(e) {
      message("Fallback matching failed for ", category_id, ": ", e$message)
      NULL
    })
    
    if (is.null(fallback_model)) next
    
    fb_match_matrix <- fallback_model$match.matrix
    treated_idx <- as.integer(rownames(fb_match_matrix)[1])
    control_indices <- as.integer(fb_match_matrix[1, ])
    control_indices <- control_indices[!is.na(control_indices)]
    
    if (length(control_indices) > 0) {
      control_cats <- unique(fallback_data$category[control_indices])
      match_pairs_list[[category_id]] <- data.frame(
        treated_market = category_id,
        control_market = control_cats
      )
      cat("  Matched to:", paste(control_cats, collapse = ", "), "\n")
    }
  }
}

# ---------------------------
# Combine all match pairs
# ---------------------------
if (length(match_pairs_list) == 0) {
  stop("No matches were made at all!")
}

match_pairs <- do.call(rbind, match_pairs_list)
rownames(match_pairs) <- NULL

cat("\n====================================================\n")
cat("Successfully matched", n_distinct(match_pairs$treated_market), "treated markets.\n")
cat("====================================================\n\n")

# Check completeness
all_treated_cats <- unique(all_treated$category)
matched_cats <- unique(match_pairs$treated_market)
missing_cats <- setdiff(all_treated_cats, matched_cats)

if (length(missing_cats) > 0) {
  cat("!! MISSING treated markets (not matched):\n")
  print(missing_cats)
} else {
  cat("All", length(all_treated_cats), "treated markets successfully matched.\n")
}

write_csv(match_pairs, "../output/match_pairs.csv")
cat("Saved match_pairs.csv\n\n")

# ---------------------------
# Generate trend plots for each treated market
# ---------------------------
cat("Generating trend plots...\n\n")

unique_treated <- unique(match_pairs$treated_market)

for (treated_cat in unique_treated) {
  # Get this market's controls
  controls <- match_pairs %>%
    filter(treated_market == treated_cat) %>%
    pull(control_market) %>%
    unique()
  
  for (outcome_var in OUTCOME_VARS) {
    relevant_categories <- c(treated_cat, controls)
    
    # Prepare trend data
    outcome_trends <- panel %>%
      filter(category %in% relevant_categories) %>%
      select(category, year, treated, spend_2013, all_of(outcome_var)) %>%
      group_by(category) %>%
      mutate(outcome_adj = .data[[outcome_var]] - .data[[outcome_var]][year == 2013]) %>%
      ungroup()
    
    # Treated trend
    treated_plot_data <- outcome_trends %>%
      filter(category == treated_cat) %>%
      mutate(group_label = paste("Treated:", treated_cat))
    
    # Weighted average control trend
    avg_control_plot_data <- outcome_trends %>%
      filter(category %in% controls) %>%
      group_by(year) %>%
      summarise(
        outcome_adj = weighted.mean(outcome_adj, w = spend_2013, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(group_label = paste("Avg. Control (n=", length(controls), ")"))
    
    plot_data_final <- bind_rows(treated_plot_data, avg_control_plot_data)
    
    plot_y_label <- str_to_title(str_replace_all(outcome_var, "_", " "))
    
    p <- ggplot(plot_data_final, aes(x = year, y = outcome_adj, color = group_label)) +
      geom_line(linewidth = 1) +
      geom_point() +
      geom_vline(xintercept = 2013.5, linetype = "dashed", color = "gray40") +
      labs(
        title = paste(plot_y_label, "Trend:", treated_cat),
        subtitle = paste("Controls:", paste(controls, collapse = ", ")),
        x = "Year",
        y = paste(plot_y_label, "(Normalized to 2013)"),
        color = "Group"
      ) +
      theme_minimal(base_size = 12) +
      scale_x_continuous(breaks = seq(2010, 2019, 1)) +
      theme(
        legend.position = "bottom",
        plot.title = element_text(face = "bold"),
        legend.text = element_text(size = 8),
        plot.subtitle = element_text(size = 8, color = "gray40")
      )
    
    tryCatch({
      # Sanitize filename (replace special characters)
      safe_name <- str_replace_all(treated_cat, "[^a-zA-Z0-9_-]", "_")
      ggsave(paste0("../output/figures/", outcome_var, "_trends_", safe_name, ".pdf"),
             plot = p, width = 10, height = 7)
      print(p)
    }, error = function(e) {
      message("WARNING: Plot failed for ", treated_cat, ": ", e$message)
    })
    
    cat("Plotted", outcome_var, "for", treated_cat, "\n")
  }
}

# ---------------------------
# Summary statistics
# ---------------------------
cat("\n====================================================\n")
cat("MATCHING SUMMARY\n")
cat("====================================================\n")
cat("Total treated markets:", length(all_treated_cats), "\n")
cat("Successfully matched:", n_distinct(match_pairs$treated_market), "\n")
cat("Matching method: Mahalanobis distance, nearest neighbor\n")
cat("Matching ratio:", MATCH_RATIO, "controls per treated\n")
cat("Replace: TRUE\n")
cat("Covariates:", paste(MATCH_COVARIATES, collapse = ", "), "\n")

# Per-market SMD diagnostics
cat("\n--- Per-Market Match Quality ---\n")
for (treated_cat in unique_treated) {
  controls <- match_pairs %>%
    filter(treated_market == treated_cat) %>%
    pull(control_market) %>%
    unique()
  
  t_row <- data_wide %>% filter(category == treated_cat)
  c_rows <- data_wide %>% filter(category %in% controls)
  
  # Calculate mean abs difference in matching covariates (standardized by control SD)
  available_covs <- intersect(MATCH_COVARIATES, names(t_row))
  available_covs <- available_covs[!is.na(t_row[1, available_covs])]
  
  if (length(available_covs) > 0 && nrow(c_rows) > 0) {
    smds <- sapply(available_covs, function(v) {
      t_val <- as.numeric(t_row[[v]])
      c_vals <- as.numeric(c_rows[[v]])
      c_sd <- sd(c_vals, na.rm = TRUE)
      if (is.na(c_sd) || c_sd == 0) return(NA_real_)
      abs(t_val - mean(c_vals, na.rm = TRUE)) / c_sd
    })
    mean_smd <- mean(smds, na.rm = TRUE)
    cat(sprintf("  %-55s | SMD: %.4f | Controls: %d\n", treated_cat, mean_smd, length(controls)))
  } else {
    cat(sprintf("  %-55s | SMD: NA (fallback) | Controls: %d\n", treated_cat, length(controls)))
  }
}

cat("\nDone.\n")
