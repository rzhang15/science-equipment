library(tidyverse)
library(MatchIt)
library(haven)

PLACEBO_SEED     <- 20260
N_DRAWS          <- 1000
MATCH_COVARIATES <- c("avg_log_price_pre_mean", "avg_log_price_slope")
MATCH_RATIO      <- 2

setwd("~/sci_eq/analysis/placebo_sd/code")

for (SUFFIX in c("", "_all3")) {
cat("\n########## Running suffix:", ifelse(SUFFIX == "", "baseline", SUFFIX), "##########\n")
panel <- read_dta(paste0("../external/samp/category_yr_tfidf", SUFFIX, ".dta")) %>%
  mutate(category = as.character(category))

real_treated_cats <- panel %>% filter(treated == 1) %>% distinct(category) %>% pull(category)
n_placebo <- length(real_treated_cats)
panel <- panel %>% filter(!category %in% real_treated_cats)
all_cats <- unique(panel$category)
cat("Real treated markets (excluded):", n_placebo, " | placebo pool:", length(all_cats), "\n")

pre_slopes <- panel %>%
  filter(year <= 2013) %>%
  mutate(year_c = year - 2012) %>%
  group_by(category) %>%
  summarise(avg_log_price_slope = coef(lm(avg_log_price ~ year_c))[2], .groups = "drop")

pre_means <- panel %>%
  filter(year >= 2011, year <= 2013) %>%
  group_by(category) %>%
  summarise(avg_log_price_pre_mean = mean(avg_log_price, na.rm = TRUE), .groups = "drop")

price_2013 <- panel %>% filter(year == 2013) %>% select(category, avg_log_price_2013 = avg_log_price)

data_wide_base <- tibble(category = all_cats) %>%
  left_join(pre_slopes, by = "category") %>%
  left_join(pre_means,  by = "category") %>%
  left_join(price_2013, by = "category")

match_one <- function(treated_row, controls, covs) {
  dat <- bind_rows(treated_row, controls) %>% drop_na(all_of(covs))
  fml <- as.formula(paste("treated ~", paste(covs, collapse = " + ")))
  m <- tryCatch(matchit(fml, method = "nearest", distance = "mahalanobis",
                        data = dat, ratio = MATCH_RATIO, replace = TRUE),
                error = function(e) NULL)
  if (is.null(m)) return(NULL)
  idx <- as.integer(m$match.matrix[1, ])
  idx <- idx[!is.na(idx)]
  if (length(idx) == 0) return(NULL)
  unique(dat$category[idx])
}

all_pairs <- vector("list", N_DRAWS)
for (iter in seq_len(N_DRAWS)) {
  if (iter %% 50 == 0) cat("iter", iter, "/", N_DRAWS, "\n")
  set.seed(PLACEBO_SEED + iter)
  placebo_treated_cats <- sample(all_cats, size = n_placebo, replace = FALSE)
  data_wide <- data_wide_base %>% mutate(treated = as.integer(category %in% placebo_treated_cats))

  all_treated  <- data_wide %>% filter(treated == 1)
  all_controls <- data_wide %>% filter(treated == 0) %>% drop_na(all_of(MATCH_COVARIATES))
  treated_clean <- all_treated %>% drop_na(all_of(MATCH_COVARIATES))
  treated_has_na <- setdiff(all_treated$category, treated_clean$category)

  pairs_list <- list()
  if (nrow(treated_clean) > 0) {
    main_model <- matchit(
      as.formula(paste("treated ~", paste(MATCH_COVARIATES, collapse = " + "))),
      method = "nearest", distance = "mahalanobis",
      data = bind_rows(treated_clean, all_controls), ratio = MATCH_RATIO, replace = TRUE
    )
    match_input  <- bind_rows(treated_clean, all_controls)
    match_matrix <- main_model$match.matrix
    for (i in seq_len(nrow(match_matrix))) {
      treated_cat <- match_input$category[as.integer(rownames(match_matrix)[i])]
      idx <- as.integer(match_matrix[i, ])
      idx <- idx[!is.na(idx)]
      if (length(idx) == 0) next
      pairs_list[[treated_cat]] <- tibble(treated_market = treated_cat,
                                          control_market = unique(match_input$category[idx]))
    }
  }

  for (category_id in treated_has_na) {
    treated_row <- all_treated %>% filter(category == category_id)
    covs <- MATCH_COVARIATES[!is.na(treated_row[, MATCH_COVARIATES])]
    if (length(covs) == 0) {
      if (is.na(treated_row$avg_log_price_2013)) next
      covs <- "avg_log_price_2013"
    }
    ctrls <- match_one(treated_row, all_controls, covs)
    if (!is.null(ctrls)) {
      pairs_list[[category_id]] <- tibble(treated_market = category_id, control_market = ctrls)
    }
  }

  iter_pairs <- bind_rows(pairs_list)
  n_matched <- if (length(pairs_list) == 0) 0L else n_distinct(iter_pairs$treated_market)
  if (n_matched != n_placebo) {
    stop("Incomplete placebo matching in iter ", iter, " (", SUFFIX, "): matched ",
         n_matched, " of ", n_placebo, " markets.")
  }
  all_pairs[[iter]] <- iter_pairs %>% mutate(iter = iter)
}

final_pairs <- bind_rows(all_pairs)
write_csv(final_pairs, paste0("../temp/placebo_sd_pairs", SUFFIX, ".csv"))
cat("Saved placebo_sd_pairs", SUFFIX, ".csv: ", N_DRAWS, " draws, ",
    n_distinct(paste(final_pairs$iter, final_pairs$treated_market)), " placebo-treated markets, ",
    nrow(final_pairs), " rows.\n", sep = "")
}
