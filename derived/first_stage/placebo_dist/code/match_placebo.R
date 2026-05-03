library(tidyverse)
library(MatchIt)
library(cobalt)
library(ggplot2)
library(haven)
library(stringr)

# ---------------------------
# Configuration
# ---------------------------
PLACEBO_SEED <- 8975
MATCH_COVARIATES <- c("log_raw_qty_2013",
                      "log_raw_spend_2013")
MATCH_RATIO <- 3

setwd("~/sci_eq/derived/first_stage/placebo_dist/code")
dir.create("../output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("../output/balance_plots", recursive = TRUE, showWarnings = FALSE)

set.seed(PLACEBO_SEED)

# ---------------------------
# Data Preparation
# ---------------------------
cat("Loading data...\n")
panel <- read_dta("../external/samp/category_yr_tfidf.dta")
panel <- panel %>% mutate(category = as.character(category))

real_treated_cats <- panel %>%
  filter(treated == 1) %>%
  distinct(category) %>%
  pull(category)
n_placebo <- length(real_treated_cats)

cat("Real treated markets (excluded from placebo pool):", n_placebo, "\n")

# Drop the real treated entirely; placebo draw is from original controls only
panel <- panel %>% filter(!category %in% real_treated_cats)

# Randomly assign n_placebo of the remaining categories as placebo-treated
all_cats <- unique(panel$category)
placebo_treated_cats <- sample(all_cats, size = n_placebo, replace = FALSE)
cat("Placebo treated drawn:", length(placebo_treated_cats), "of", length(all_cats), "candidate controls\n")

# Overwrite treated flag with placebo assignment
panel <- panel %>%
  mutate(treated = as.integer(category %in% placebo_treated_cats))

# Save the placebo treated/control crosswalk for downstream use
placebo_assignment <- panel %>%
  distinct(category, treated) %>%
  rename(placebo_treated = treated)
write_csv(placebo_assignment, "../output/placebo_assignment.csv")

# ---------------------------
# Pivot pre-treatment data to wide format
# ---------------------------
all_data_pre <- panel %>% filter(year <= 2013)

data_wide <- all_data_pre %>%
  pivot_wider(
    names_from = year,
    names_sep = "_",
    id_cols = c(category, treated, spend_2013),
    values_from = c(avg_log_price, log_raw_spend, obs_cnt, item_price,
                    raw_spend, raw_price, raw_qty, log_raw_price, log_raw_qty)
  ) %>%
  mutate(log_spend_2013 = log(spend_2013 + 1))

pre_slopes <- panel %>%
  filter(year <= 2013) %>%
  mutate(year_c = year - 2012) %>%
  group_by(category) %>%
  summarise(
    avg_log_price_slope     = coef(lm(avg_log_price ~ year_c))[2],
    avg_log_price_intercept = coef(lm(avg_log_price ~ year_c))[1],
    log_raw_spend_slope     = coef(lm(log_raw_spend ~ year_c))[2],
    log_raw_qty_slope       = coef(lm(log_raw_qty   ~ year_c))[2],
    .groups = "drop"
  )

data_wide <- data_wide %>%
  left_join(pre_slopes, by = "category")

# ---------------------------
# Matching
# ---------------------------
all_treated <- data_wide %>% filter(treated == 1)
all_controls <- data_wide %>% filter(treated == 0) %>% drop_na(all_of(MATCH_COVARIATES))

treated_has_na <- all_treated %>%
  filter(if_any(all_of(MATCH_COVARIATES), is.na)) %>%
  pull(category)
treated_clean <- all_treated %>% filter(!category %in% treated_has_na)

cat("Placebo treated:", nrow(all_treated),
    " | clean:", nrow(treated_clean),
    " | controls available:", nrow(all_controls), "\n")

match_input <- bind_rows(treated_clean, all_controls)
match_formula <- as.formula(paste("treated ~", paste(MATCH_COVARIATES, collapse = " + ")))

cat("Running Mahalanobis matching (placebo)...\n")
main_model <- matchit(
  formula = match_formula,
  method = "nearest",
  distance = "mahalanobis",
  data = match_input,
  ratio = MATCH_RATIO,
  replace = TRUE
)

cat("=== Overall Balance Summary (placebo) ===\n")
print(summary(main_model))

tryCatch({
  bal_plot <- love.plot(main_model, binary = "std", thresholds = c(m = .1),
                        title = "Placebo Covariate Balance (Mahalanobis Matching)")
  ggsave("../output/balance_plots/balance_overall.pdf", plot = bal_plot, width = 8, height = 6)
}, error = function(e) message("WARNING: love.plot failed: ", e$message))

# Extract matched pairs
match_matrix <- main_model$match.matrix
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

# Fallback for placebo treated with NA covariates
if (length(treated_has_na) > 0) {
  cat("\n--- Fallback matching for", length(treated_has_na), "placebo treated with NA covariates ---\n")
  for (category_id in treated_has_na) {
    treated_row <- all_treated %>% filter(category == category_id)
    available_covs <- MATCH_COVARIATES[!is.na(treated_row[, MATCH_COVARIATES])]
    if (length(available_covs) == 0) {
      available_covs <- "avg_log_price_2013"
      if (is.na(treated_row$avg_log_price_2013)) next
    }
    fallback_data <- bind_rows(treated_row, all_controls) %>% drop_na(all_of(available_covs))
    fallback_formula <- as.formula(paste("treated ~", paste(available_covs, collapse = " + ")))
    fallback_model <- tryCatch(matchit(
      formula = fallback_formula, method = "nearest", distance = "mahalanobis",
      data = fallback_data, ratio = MATCH_RATIO, replace = TRUE
    ), error = function(e) { message("Fallback failed for ", category_id, ": ", e$message); NULL })
    if (is.null(fallback_model)) next
    fb_match_matrix <- fallback_model$match.matrix
    control_indices <- as.integer(fb_match_matrix[1, ])
    control_indices <- control_indices[!is.na(control_indices)]
    if (length(control_indices) > 0) {
      control_cats <- unique(fallback_data$category[control_indices])
      match_pairs_list[[category_id]] <- data.frame(
        treated_market = category_id,
        control_market = control_cats
      )
    }
  }
}

if (length(match_pairs_list) == 0) stop("No placebo matches were made!")

match_pairs <- do.call(rbind, match_pairs_list)
rownames(match_pairs) <- NULL

cat("\nSuccessfully matched", n_distinct(match_pairs$treated_market), "of",
    nrow(all_treated), "placebo treated markets.\n")

write_csv(match_pairs, "../output/placebo_match_pairs.csv")
cat("Saved placebo_match_pairs.csv and placebo_assignment.csv\n")
