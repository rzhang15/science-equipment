#  Rank specs by actual event-study pretrend coefficients in price + spend.
#  Mirrors evaluate_spec() in explore_specs.R for matching + event study, but
#  skips all the plotting and just extracts the lead/lag coefficient table.
#  Writes one combined CSV of lead coefs across all (spec, ratio) combos.

suppressPackageStartupMessages({
  library(tidyverse)
  library(MatchIt)
  library(haven)
  library(broom)
  library(fixest)
})
set.seed(8975)

setwd("~/sci_eq/derived/first_stage/match_control/code")

panel <- read_dta("../external/samp/category_yr_tfidf.dta") %>%
  mutate(category = as.character(category))

uni_panel <- read_dta("../external/samp/uni_category_yr_tfidf.dta") %>%
  mutate(category = as.character(category)) %>%
  select(uni_id, category, mkt, year, treated, spend_2013,
         avg_log_price, log_raw_qty, log_raw_spend) %>%
  filter(!is.na(spend_2013))

# Pre-period trends + year-specific levels (same as explore_specs.R)
pre_panel <- panel %>% filter(year <= 2013) %>% mutate(year_c = year - 2012)

get_trend <- function(df, var) {
  y <- df[[var]]; x <- df$year_c
  if (sum(!is.na(y)) < 2) return(data.frame(slope = NA_real_, intercept = NA_real_))
  fit <- lm(y ~ x)
  data.frame(slope = coef(fit)[2], intercept = coef(fit)[1])
}

trend_vars <- c("avg_log_price", "log_raw_spend", "log_raw_price",
                "log_raw_qty", "raw_spend", "raw_price", "raw_qty")

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
  }) %>% ungroup()

levels_2013 <- panel %>% filter(year == 2013) %>%
  select(category, avg_log_price_2013 = avg_log_price,
         log_raw_spend_2013 = log_raw_spend,
         log_raw_price_2013 = log_raw_price,
         log_raw_qty_2013 = log_raw_qty,
         raw_spend_2013 = raw_spend, raw_qty_2013 = raw_qty)

levels_wide <- panel %>% filter(year <= 2012) %>%
  select(category, year, avg_log_price, log_raw_price, log_raw_qty,
         log_raw_spend, raw_qty, raw_spend) %>%
  pivot_wider(names_from = year,
              values_from = c(avg_log_price, log_raw_price, log_raw_qty,
                              log_raw_spend, raw_qty, raw_spend),
              names_glue = "{.value}_{year}")

data_wide <- trends %>%
  left_join(levels_2013, by = "category") %>%
  mutate(log_spend_2013 = log(spend_2013 + 1)) %>%
  left_join(levels_wide, by = "category")

specs <- list(
  t10_alp_spend_slopes = c("avg_log_price_slope", "log_raw_spend_slope"),
  t13_alp_qty_slopes   = c("avg_log_price_slope", "log_raw_qty_slope"),
  t14_three_slopes     = c("avg_log_price_slope", "log_raw_spend_slope", "log_raw_qty_slope"),
  t29_qty_slope_qty13  = c("log_raw_qty_slope", "log_raw_qty_2013"),
  t46_qty13_spend13    = c("log_raw_qty_2013", "log_raw_spend_2013"),
  t48_alp_slope_alp13_qty13 = c("avg_log_price_slope", "avg_log_price_2013", "log_raw_qty_2013"),
  t35_annual_alp_11_13_qty  = c("avg_log_price_2011", "avg_log_price_2012", "avg_log_price_2013", "log_raw_qty_slope"),
  t17_price_qty_slopes_levels13 = c("avg_log_price_slope", "log_raw_qty_slope", "avg_log_price_2013", "log_raw_qty_2013"),
  bench_alp_levels_11_13 = c("avg_log_price_2011", "avg_log_price_2012", "avg_log_price_2013"),
  n01_alp_slope_only       = c("avg_log_price_slope"),
  n02_qty_slope_only       = c("log_raw_qty_slope"),
  n03_alp13_only           = c("avg_log_price_2013"),
  n10_qty_spend_slopes     = c("log_raw_qty_slope", "log_raw_spend_slope"),
  n11_alp_slope_alp13      = c("avg_log_price_slope", "avg_log_price_2013"),
  n12_spend_slope_spend13  = c("log_raw_spend_slope", "log_raw_spend_2013"),
  n13_alp_12_13            = c("avg_log_price_2012", "avg_log_price_2013"),
  n14_qty_12_13            = c("log_raw_qty_2012", "log_raw_qty_2013"),
  n15_spend_12_13          = c("log_raw_spend_2012", "log_raw_spend_2013"),
  n16_alp13_qty13          = c("avg_log_price_2013", "log_raw_qty_2013"),
  n17_alp13_spend13        = c("avg_log_price_2013", "log_raw_spend_2013"),
  n18_alp_slope_logspend13 = c("avg_log_price_slope", "log_spend_2013"),
  n19_qty_slope_logspend13 = c("log_raw_qty_slope", "log_spend_2013"),
  n20_alp13_qty13_spend13  = c("avg_log_price_2013", "log_raw_qty_2013", "log_raw_spend_2013"),
  n21_alp_qty_slopes_alp13   = c("avg_log_price_slope", "log_raw_qty_slope", "avg_log_price_2013"),
  n22_alp_qty_slopes_qty13   = c("avg_log_price_slope", "log_raw_qty_slope", "log_raw_qty_2013"),
  n23_alp_qty_slopes_spend13 = c("avg_log_price_slope", "log_raw_qty_slope", "log_raw_spend_2013"),
  n24_alp_slope_alp_12_13  = c("avg_log_price_slope", "avg_log_price_2012", "avg_log_price_2013"),
  n25_qty_slope_qty_12_13  = c("log_raw_qty_slope", "log_raw_qty_2012", "log_raw_qty_2013"),
  n26_alp_slope_spend13    = c("avg_log_price_slope", "log_raw_spend_2013")
)

run_es <- function(spec_name, covariates, match_ratio) {
  cat(sprintf("[r=%d] %s\n", match_ratio, spec_name))

  all_treated <- data_wide %>% filter(treated == 1)
  all_controls <- data_wide %>% filter(treated == 0) %>% drop_na(all_of(covariates))
  treated_clean <- all_treated %>% filter(!if_any(all_of(covariates), is.na))

  if (nrow(treated_clean) == 0 || nrow(all_controls) < match_ratio) return(NULL)

  mi <- bind_rows(treated_clean, all_controls)
  fmla <- as.formula(paste("treated ~", paste(covariates, collapse = " + ")))
  model <- tryCatch(matchit(fmla, method = "nearest", distance = "mahalanobis",
                            data = mi, ratio = match_ratio, replace = TRUE),
                    error = function(e) NULL)
  if (is.null(model)) return(NULL)

  mm <- model$match.matrix
  pairs <- list()
  for (i in seq_len(nrow(mm))) {
    ti <- as.integer(rownames(mm)[i]); tc <- mi$category[ti]
    ci <- as.integer(mm[i, ]); ci <- ci[!is.na(ci)]
    if (!length(ci)) next
    pairs[[tc]] <- data.frame(treated_market = tc,
                              control_market = unique(mi$category[ci]))
  }
  if (!length(pairs)) return(NULL)
  match_pairs <- do.call(rbind, pairs)

  cats <- unique(c(match_pairs$treated_market, match_pairs$control_market))
  sub <- uni_panel %>%
    filter(category %in% cats, year >= 2010, year <= 2019) %>%
    group_by(uni_id, mkt) %>%
    filter(min(year) < 2014, max(year) > 2014) %>% ungroup()
  if (!nrow(sub)) return(NULL)

  vars <- c("avg_log_price", "log_raw_qty", "log_raw_spend")
  es_rows <- list()
  for (v in vars) {
    rows <- !is.na(sub[[v]]) & !is.na(sub$spend_2013)
    if (sum(rows) < 100) next
    d <- sub[rows, ]
    fit <- tryCatch(feols(
      as.formula(paste(v, "~ i(year, treated, ref = 2013) | uni_id + mkt + year")),
      data = d, weights = ~spend_2013, cluster = ~mkt,
      notes = FALSE, warn = FALSE), error = function(e) NULL)
    if (is.null(fit)) next
    co <- broom::tidy(fit, conf.int = TRUE) %>%
      filter(grepl("year::[0-9]+", term)) %>%
      mutate(year = as.integer(sub(".*year::([0-9]+).*", "\\1", term)),
             rel = year - 2014, outcome = v)
    es_rows[[v]] <- co
  }
  if (!length(es_rows)) return(NULL)
  bind_rows(es_rows) %>%
    mutate(spec = spec_name, match_ratio = match_ratio) %>%
    select(spec, match_ratio, outcome, year, rel, estimate, std.error,
           conf.low, conf.high)
}

all_rows <- list()
for (r in c(2, 3)) {
  for (sn in names(specs)) {
    res <- tryCatch(run_es(sn, specs[[sn]], r),
                    error = function(e) { cat("  ERR:", e$message, "\n"); NULL })
    if (!is.null(res)) all_rows[[paste0(sn, "_r", r)]] <- res
  }
}

coefs <- bind_rows(all_rows)
dir.create("../output/spec_search", recursive = TRUE, showWarnings = FALSE)
write_csv(coefs, "../output/spec_search/es_leads_all_specs.csv")

# Pretrend score: sum of |b| at rel = -4, -3, -2 (i.e., year 2010, 2011, 2012).
# rel = -1 (year 2013) is the reference, so it's 0 by construction.
pretrend <- coefs %>%
  filter(rel %in% c(-4, -3, -2)) %>%
  group_by(spec, match_ratio, outcome) %>%
  summarise(sum_abs_lead = sum(abs(estimate), na.rm = TRUE),
            max_abs_lead = max(abs(estimate), na.rm = TRUE),
            .groups = "drop") %>%
  pivot_wider(names_from = outcome,
              values_from = c(sum_abs_lead, max_abs_lead),
              names_glue = "{outcome}_{.value}") %>%
  mutate(price_spend_sum = avg_log_price_sum_abs_lead + log_raw_spend_sum_abs_lead,
         price_spend_max = pmax(avg_log_price_max_abs_lead, log_raw_spend_max_abs_lead))

ranked <- pretrend %>% arrange(price_spend_sum)
write_csv(ranked, "../output/spec_search/es_pretrend_rank.csv")

cat("\n========================================================\n")
cat("Top specs by SUM of |lead coefs| in PRICE + SPEND (rel = -4,-3,-2)\n")
cat("========================================================\n")
print(ranked %>%
        select(spec, match_ratio,
               avg_log_price_sum_abs_lead,
               log_raw_spend_sum_abs_lead,
               log_raw_qty_sum_abs_lead,
               price_spend_sum, price_spend_max) %>%
        head(20), n = 20, width = Inf)

cat("\nDone. Output: ../output/spec_search/es_pretrend_rank.csv\n")
