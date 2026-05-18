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
library(fixest)
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

# Load uni-category-year panel for spec-level event-study residualization
cat("Loading uni-cat-year panel for event-study pretrend plots...\n")
uni_panel <- read_dta("../external/samp/uni_category_yr_tfidf.dta") %>%
  mutate(category = as.character(category)) %>%
  select(uni_id, category, mkt, year, treated, spend_2013,
         avg_log_price, log_raw_qty, log_raw_spend) %>%
  filter(!is.na(spend_2013))
cat("Uni panel:", nrow(uni_panel), "rows |",
    n_distinct(uni_panel$uni_id), "unis x",
    n_distinct(uni_panel$category), "cats\n\n")

# ---------------------------
# Raw pre-trends: weighted average of outcomes by treatment status over time
# ---------------------------
# Average log_price / log_qty / log_spend across categories within each
# (treated, year) cell, weighted by category-level 2013 spending. This matches
# the spend_2013-weighted event study in analysis.do, so the visual reflects
# what the event study coefficients will look like.
cat("Plotting raw pre-trends by treatment status (spend_2013-weighted)...\n")

trend_plot_vars <- c("avg_log_price", "log_raw_qty", "log_raw_spend")

raw_trends <- panel %>%
  select(category, year, treated, spend_2013, all_of(trend_plot_vars)) %>%
  pivot_longer(all_of(trend_plot_vars), names_to = "variable", values_to = "value") %>%
  filter(!is.na(value), !is.na(spend_2013)) %>%
  group_by(variable, treated, year) %>%
  summarise(wmean = weighted.mean(value, w = spend_2013, na.rm = TRUE),
            n_cat = n(), .groups = "drop") %>%
  mutate(treated_lbl = factor(treated, levels = c(0, 1),
                              labels = c("Control", "Treated")),
         variable = factor(variable, levels = trend_plot_vars,
                           labels = c("log price", "log qty", "log spend")))

p_levels <- ggplot(raw_trends, aes(x = year, y = wmean,
                                   color = treated_lbl, group = treated_lbl)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.5) +
  geom_vline(xintercept = 2013, linetype = "dashed", color = "grey40") +
  facet_wrap(~ variable, scales = "free_y") +
  scale_color_manual(values = c("Control" = "#1f78b4", "Treated" = "#e31a1c")) +
  labs(x = "Year", y = "Spend-weighted mean", color = NULL,
       title = "Weighted means by treatment status (weights = spend_2013)") +
  theme_bw() +
  theme(legend.position = "bottom")

# Also normalize to 2013 = 0 to make pretrend visual comparison easier
raw_trends_norm <- raw_trends %>%
  group_by(variable, treated_lbl) %>%
  mutate(wmean_norm = wmean - wmean[year == 2013]) %>%
  ungroup()

p_norm <- ggplot(raw_trends_norm, aes(x = year, y = wmean_norm,
                                      color = treated_lbl, group = treated_lbl)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 0, color = "grey70") +
  geom_vline(xintercept = 2013, linetype = "dashed", color = "grey40") +
  facet_wrap(~ variable, scales = "free_y") +
  scale_color_manual(values = c("Control" = "#1f78b4", "Treated" = "#e31a1c")) +
  labs(x = "Year", y = "Weighted mean, relative to 2013", color = NULL,
       title = "Pre-trend alignment (normalized to 2013 = 0)") +
  theme_bw() +
  theme(legend.position = "bottom")

dir.create("../output/spec_search", recursive = TRUE, showWarnings = FALSE)
dir.create("../output/spec_search/spec_pretrends", recursive = TRUE, showWarnings = FALSE)
ggsave("../output/spec_search/pretrends_unmatched_levels.png", p_levels,
       width = 10, height = 4, dpi = 150)
ggsave("../output/spec_search/pretrends_unmatched_normalized.png", p_norm,
       width = 10, height = 4, dpi = 150)

cat("Saved unmatched-baseline pre-trend plots to ../output/spec_search/\n\n")

# ---------------------------
# Per-spec trend plotter: treated vs matched-control weighted means over time
# ---------------------------
# Given a match_pairs table (treated_market, control_market) for a spec, build
# the spend-weighted mean of price/qty/spend in each year for treated vs the
# matched controls, and save a PNG into spec_pretrends/. Controls used for
# multiple treateds are weighted by spend_2013 * (# times matched), mirroring
# how a stacked spend_2013-weighted event study would treat them.
plot_match_trends <- function(match_pairs, panel, spec_name, match_ratio,
                              vars = c("avg_log_price", "log_raw_qty", "log_raw_spend")) {
  treated_cats <- unique(match_pairs$treated_market)
  control_weights <- match_pairs %>%
    count(control_market, name = "n_matched")

  treated_long <- panel %>%
    filter(category %in% treated_cats) %>%
    select(category, year, spend_2013, all_of(vars)) %>%
    mutate(eff_weight = spend_2013, group = "Treated")

  control_long <- panel %>%
    filter(category %in% control_weights$control_market) %>%
    inner_join(control_weights, by = c("category" = "control_market")) %>%
    mutate(eff_weight = spend_2013 * n_matched, group = "Matched control") %>%
    select(category, year, eff_weight, group, all_of(vars))

  combined <- bind_rows(
    treated_long %>% select(category, year, eff_weight, group, all_of(vars)),
    control_long
  ) %>%
    pivot_longer(all_of(vars), names_to = "variable", values_to = "value") %>%
    filter(!is.na(value), !is.na(eff_weight)) %>%
    group_by(variable, group, year) %>%
    summarise(wmean = weighted.mean(value, w = eff_weight, na.rm = TRUE),
              .groups = "drop") %>%
    group_by(variable, group) %>%
    mutate(wmean_norm = wmean - wmean[year == 2013]) %>%
    ungroup() %>%
    mutate(variable = factor(variable, levels = vars,
                             labels = c("log price", "log qty", "log spend")))

  p <- ggplot(combined, aes(x = year, y = wmean_norm,
                            color = group, group = group)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.5) +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_vline(xintercept = 2013, linetype = "dashed", color = "grey40") +
    facet_wrap(~ variable) +
    scale_color_manual(values = c("Matched control" = "#1f78b4",
                                  "Treated" = "#e31a1c")) +
    labs(x = "Year", y = "Spend-weighted mean, relative to 2013", color = NULL,
         title = sprintf("%s (ratio=%d)", spec_name, match_ratio),
         subtitle = sprintf("n_treated = %d  |  n_controls used = %d",
                            length(treated_cats), nrow(control_weights))) +
    theme_bw() +
    theme(legend.position = "bottom")

  ggsave(sprintf("../output/spec_search/spec_pretrends/pretrends_r%d_%s.png", match_ratio, spec_name),
         p, width = 10, height = 4, dpi = 150)
}

# ---------------------------
# Per-spec event-study-style trend plot: residualize on uni + mkt FE first
# ---------------------------
# Mirrors the analysis.do event study setup more closely than plot_match_trends:
#   1. uni-category-year panel (not category-year)
#   2. balanced filter: keep uni-mkt cells with min(year)<2014 AND max(year)>2014
#   3. residualize each outcome on uni_id + mkt FE, weighted by spend_2013
#   4. plot weighted mean of residuals by year x treated, normalized to 2013 = 0
# This shows the differential time path that the lead/lag dummies would identify
# in the actual event study.
plot_match_trends_es <- function(match_pairs, uni_panel, spec_name, match_ratio,
                                 vars = c("avg_log_price", "log_raw_qty", "log_raw_spend")) {
  cats <- unique(c(match_pairs$treated_market, match_pairs$control_market))

  sub <- uni_panel %>%
    filter(category %in% cats) %>%
    group_by(uni_id, mkt) %>%
    filter(min(year) < 2014, max(year) > 2014) %>%
    ungroup()

  if (nrow(sub) == 0) return(invisible(NULL))

  resid_df <- sub %>% select(uni_id, mkt, year, treated, spend_2013)
  for (v in vars) {
    rows <- !is.na(sub[[v]])
    if (sum(rows) < 100) { resid_df[[v]] <- NA_real_; next }
    fit <- feols(as.formula(paste(v, "~ 1 | uni_id + mkt")),
                 data = sub[rows, ], weights = sub$spend_2013[rows],
                 notes = FALSE, warn = FALSE)
    resid_df[[v]] <- NA_real_
    resid_df[[v]][rows] <- residuals(fit)
  }

  long <- resid_df %>%
    pivot_longer(all_of(vars), names_to = "variable", values_to = "value") %>%
    filter(!is.na(value), !is.na(spend_2013)) %>%
    group_by(variable, treated, year) %>%
    summarise(wmean = weighted.mean(value, w = spend_2013), .groups = "drop") %>%
    group_by(variable, treated) %>%
    mutate(wmean_norm = wmean - wmean[year == 2013]) %>%
    ungroup() %>%
    mutate(group = factor(treated, levels = c(0, 1),
                          labels = c("Matched control", "Treated")),
           variable = factor(variable, levels = vars,
                             labels = c("log price", "log qty", "log spend")))

  n_uni <- n_distinct(sub$uni_id)
  n_mkt_t <- n_distinct(sub$mkt[sub$treated == 1])
  n_mkt_c <- n_distinct(sub$mkt[sub$treated == 0])

  p <- ggplot(long, aes(x = year, y = wmean_norm, color = group, group = group)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.5) +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_vline(xintercept = 2013, linetype = "dashed", color = "grey40") +
    facet_wrap(~ variable) +
    scale_color_manual(values = c("Matched control" = "#1f78b4",
                                  "Treated" = "#e31a1c")) +
    labs(x = "Year", y = "Residualized weighted mean (rel. to 2013)", color = NULL,
         title = sprintf("%s (ratio=%d) - uni+mkt FE residualized", spec_name, match_ratio),
         subtitle = sprintf("Balanced uni-mkt panel | n_uni=%d  treated mkts=%d  control mkts=%d",
                            n_uni, n_mkt_t, n_mkt_c)) +
    theme_bw() +
    theme(legend.position = "bottom")

  dir.create("../output/spec_search/spec_pretrends_es", recursive = TRUE, showWarnings = FALSE)
  ggsave(sprintf("../output/spec_search/spec_pretrends_es/pretrends_es_r%d_%s.png", match_ratio, spec_name),
         p, width = 10, height = 4, dpi = 150)
}

# ---------------------------
# Per-spec EVENT-STUDY GAP plot: implied (treated - control) coefficient curve.
# Mirrors what the actual event study with uni + mkt FE will identify:
#   1. Same balanced uni-mkt sample
#   2. Residualize each outcome on uni_id + mkt FE, weighted by spend_2013
#   3. Compute spend-weighted mean of residuals by (treated, year)
#   4. gap_t = treated_mean_t - control_mean_t
#   5. Normalize to gap_2013 = 0 (matches event study with 2013 base)
# Each year's y-value ≈ the lead/lag coefficient the event study would estimate.
# Pretrend OK ↔ pre-2013 line near zero. Treatment effect ↔ post-2013 jump.
plot_match_trends_gap <- function(match_pairs, uni_panel, spec_name, match_ratio,
                                  vars = c("avg_log_price", "log_raw_qty", "log_raw_spend")) {
  cats <- unique(c(match_pairs$treated_market, match_pairs$control_market))

  sub <- uni_panel %>%
    filter(category %in% cats) %>%
    group_by(uni_id, mkt) %>%
    filter(min(year) < 2014, max(year) > 2014) %>%
    ungroup()

  if (nrow(sub) == 0) return(invisible(NULL))

  resid_df <- sub %>% select(uni_id, mkt, year, treated, spend_2013)
  for (v in vars) {
    rows <- !is.na(sub[[v]])
    if (sum(rows) < 100) { resid_df[[v]] <- NA_real_; next }
    fit <- feols(as.formula(paste(v, "~ 1 | uni_id + mkt")),
                 data = sub[rows, ], weights = sub$spend_2013[rows],
                 notes = FALSE, warn = FALSE)
    resid_df[[v]] <- NA_real_
    resid_df[[v]][rows] <- residuals(fit)
  }

  long <- resid_df %>%
    pivot_longer(all_of(vars), names_to = "variable", values_to = "value") %>%
    filter(!is.na(value), !is.na(spend_2013)) %>%
    group_by(variable, treated, year) %>%
    summarise(wmean = weighted.mean(value, w = spend_2013), .groups = "drop") %>%
    pivot_wider(names_from = treated, values_from = wmean,
                names_prefix = "grp") %>%
    mutate(gap = grp1 - grp0) %>%
    group_by(variable) %>%
    mutate(gap_norm = gap - gap[year == 2013]) %>%
    ungroup() %>%
    mutate(variable = factor(variable, levels = vars,
                             labels = c("log price", "log qty", "log spend")))

  n_uni <- n_distinct(sub$uni_id)
  n_mkt_t <- n_distinct(sub$mkt[sub$treated == 1])
  n_mkt_c <- n_distinct(sub$mkt[sub$treated == 0])

  p <- ggplot(long, aes(x = year, y = gap_norm)) +
    geom_line(linewidth = 0.8, color = "#1f78b4") +
    geom_point(size = 2, color = "#1f78b4") +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_vline(xintercept = 2013, linetype = "dashed", color = "grey40") +
    facet_wrap(~ variable) +
    labs(x = "Year",
         y = "Treated - control (uni+mkt FE residualized, rel. to 2013)",
         title = sprintf("%s (ratio=%d) - implied event-study coefficient",
                         spec_name, match_ratio),
         subtitle = sprintf("Balanced uni-mkt panel | n_uni=%d  treated mkts=%d  control mkts=%d",
                            n_uni, n_mkt_t, n_mkt_c)) +
    theme_bw()

  dir.create("../output/spec_search/spec_pretrends_gap", recursive = TRUE, showWarnings = FALSE)
  ggsave(sprintf("../output/spec_search/spec_pretrends_gap/pretrends_gap_r%d_%s.png", match_ratio, spec_name),
         p, width = 10, height = 4, dpi = 150)
}

# ---------------------------
# Per-spec ACTUAL EVENT STUDY: leads/lags x treated, uni+mkt+year FE,
# weighted by spend_2013, clustered by mkt. Mirrors `manual_event_study`
# in analysis.do (lead=-4, lag=5, rel=-1/year=2013 as reference).
# Plots the coefficient curve with 95% CIs per outcome.
# ---------------------------
plot_event_study <- function(match_pairs, uni_panel, spec_name, match_ratio,
                             vars = c("avg_log_price", "log_raw_qty", "log_raw_spend")) {
  cats <- unique(c(match_pairs$treated_market, match_pairs$control_market))

  sub <- uni_panel %>%
    filter(category %in% cats, year >= 2010, year <= 2019) %>%
    group_by(uni_id, mkt) %>%
    filter(min(year) < 2014, max(year) > 2014) %>%
    ungroup()

  if (nrow(sub) == 0) return(invisible(NULL))

  n_uni   <- n_distinct(sub$uni_id)
  n_mkt_t <- n_distinct(sub$mkt[sub$treated == 1])
  n_mkt_c <- n_distinct(sub$mkt[sub$treated == 0])

  es_list <- list()
  for (v in vars) {
    rows <- !is.na(sub[[v]]) & !is.na(sub$spend_2013)
    if (sum(rows) < 100) next
    d <- sub[rows, ]
    fit <- tryCatch(
      fixest::feols(
        stats::as.formula(paste(v, "~ i(year, treated, ref = 2013) | uni_id + mkt + year")),
        data = d, weights = ~spend_2013, cluster = ~mkt,
        notes = FALSE, warn = FALSE),
      error = function(e) { cat("    feols failed for", v, ":", e$message, "\n"); NULL }
    )
    if (is.null(fit)) next

    co <- broom::tidy(fit, conf.int = TRUE) %>%
      filter(grepl("year::[0-9]+", term)) %>%
      mutate(year = as.integer(sub(".*year::([0-9]+).*", "\\1", term)),
             rel  = year - 2014,
             outcome = v) %>%
      filter(!is.na(year))
    ref_row <- tibble::tibble(term = "year::2013:treated", estimate = 0,
                              std.error = 0, conf.low = 0, conf.high = 0,
                              year = 2013L, rel = -1L, outcome = v)
    es_list[[v]] <- dplyr::bind_rows(co, ref_row) %>% dplyr::arrange(year)
  }

  if (length(es_list) == 0) return(invisible(NULL))

  long <- dplyr::bind_rows(es_list) %>%
    mutate(outcome = factor(outcome, levels = vars,
                            labels = c("log price", "log qty", "log spend")))

  p <- ggplot(long, aes(x = rel, y = estimate)) +
    geom_hline(yintercept = 0, color = "grey60") +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey40") +
    geom_line(color = "#1f78b4", linewidth = 0.5, alpha = 0.6) +
    geom_pointrange(aes(ymin = conf.low, ymax = conf.high),
                    color = "#1f78b4", size = 0.35) +
    facet_wrap(~ outcome) +
    scale_x_continuous(breaks = -4:5) +
    labs(x = "Years from 2014",
         y = "Event-study coefficient (rel. to 2013)",
         title = sprintf("%s (ratio=%d) - actual event study (lead/lag x treated)",
                         spec_name, match_ratio),
         subtitle = sprintf("uni+mkt+year FE, w=spend_2013, cluster=mkt | n_uni=%d  trt mkts=%d  ctrl mkts=%d",
                            n_uni, n_mkt_t, n_mkt_c)) +
    theme_bw()

  dir.create("../output/spec_search/spec_event_study", recursive = TRUE, showWarnings = FALSE)
  ggsave(sprintf("../output/spec_search/spec_event_study/es_r%d_%s.png", match_ratio, spec_name),
         p, width = 10, height = 4, dpi = 150)

  # Persist lead/lag coefficients so we can rank specs by actual pretrends.
  out <- long %>%
    mutate(spec = spec_name, match_ratio = match_ratio) %>%
    select(spec, match_ratio, outcome, year, rel, estimate, std.error,
           conf.low, conf.high)
  dir.create("../output/spec_search/es_coefs", recursive = TRUE, showWarnings = FALSE)
  write_csv(out, sprintf("../output/spec_search/es_coefs/es_r%d_%s.csv", match_ratio, spec_name))

  invisible(long)
}

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
  }) %>%
  ungroup()

cat("Computed trends for", nrow(trends), "categories\n")

# Also grab 2013 levels for hybrid specs
levels_2013 <- panel %>%
  filter(year == 2013) %>%
  select(category, avg_log_price_2013 = avg_log_price,
         log_raw_spend_2013 = log_raw_spend,
         log_raw_price_2013 = log_raw_price,
         log_raw_qty_2013 = log_raw_qty,
         raw_spend_2013 = raw_spend,
         raw_qty_2013 = raw_qty)

# Merge trends + 2013 levels
data_wide <- trends %>%
  left_join(levels_2013, by = "category") %>%
  mutate(log_spend_2013 = log(spend_2013 + 1))

# Year-specific levels for 2010-2012 (avoid 2013 — already in levels_2013).
# Expanded to include all key outcomes (log price, log qty, log spend, raw
# qty, raw spend) so specs can reference e.g. `log_raw_qty_2012` directly
# instead of using a fitted intercept.
levels_wide <- panel %>%
  filter(year <= 2012) %>%
  select(category, year, avg_log_price, log_raw_price, log_raw_qty,
         log_raw_spend, raw_qty, raw_spend) %>%
  pivot_wider(names_from = year,
              values_from = c(avg_log_price, log_raw_price, log_raw_qty,
                              log_raw_spend, raw_qty, raw_spend),
              names_glue = "{.value}_{year}")

data_wide <- data_wide %>%
  left_join(levels_wide, by = "category")

# ---------------------------
# Pre-period summary stats (2011-2013): mean, SD, and 2-/3-year changes.
# Complement slope/level specs: pre_mean smooths single-year noise; pre_chg is
# a simpler alternative to a fitted slope; pre_sd captures within-cat volatility.
# ---------------------------
cat("Computing pre-period summary statistics (2011-2013)...\n")
pre_summary <- pre_panel %>%
  filter(year >= 2011, year <= 2013) %>%
  group_by(category) %>%
  summarise(
    avg_log_price_pre_mean = mean(avg_log_price, na.rm = TRUE),
    avg_log_price_pre_sd   = sd(avg_log_price,   na.rm = TRUE),
    log_raw_qty_pre_mean   = mean(log_raw_qty,   na.rm = TRUE),
    log_raw_qty_pre_sd     = sd(log_raw_qty,     na.rm = TRUE),
    log_raw_spend_pre_mean = mean(log_raw_spend, na.rm = TRUE),
    log_raw_spend_pre_sd   = sd(log_raw_spend,   na.rm = TRUE),
    log_raw_price_pre_mean = mean(log_raw_price, na.rm = TRUE),
    .groups = "drop"
  )

data_wide <- data_wide %>%
  left_join(pre_summary, by = "category") %>%
  mutate(
    # 2-year change: 2013 - 2011 (less noisy alternative to fitted slope)
    avg_log_price_pre_chg = avg_log_price_2013 - avg_log_price_2011,
    log_raw_qty_pre_chg   = log_raw_qty_2013   - log_raw_qty_2011,
    log_raw_spend_pre_chg = log_raw_spend_2013 - log_raw_spend_2011,
    log_raw_price_pre_chg = log_raw_price_2013 - log_raw_price_2011,
    # 3-year change: 2013 - 2010 (where 2010 available)
    avg_log_price_pre_chg3 = avg_log_price_2013 - avg_log_price_2010,
    log_raw_qty_pre_chg3   = log_raw_qty_2013   - log_raw_qty_2010
  )

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
# Trimmed to specs that span the trade-off:
#   qty-heavy matching  -> flat qty pre + post (small qty event-study coefficient)
#   price-light matching -> preserve large post price gap (treatment effect)
#   anchor price pretrend without over-matching post
# All covariates are either: a slope (log or raw), or an actual year-specific
# level (log or raw). No fitted intercepts.
specs <- list(
  # === Slope-only baselines: max post-price gap, but level mismatch on qty ===
  t10_alp_spend_slopes = c("avg_log_price_slope", "log_raw_spend_slope"),
  t13_alp_qty_slopes   = c("avg_log_price_slope", "log_raw_qty_slope"),
  t14_three_slopes     = c("avg_log_price_slope", "log_raw_spend_slope",
                           "log_raw_qty_slope"),

  # === Qty-heavy, NO price covariates: qty flat throughout, max post-price ===
  t29_qty_slope_qty13   = c("log_raw_qty_slope", "log_raw_qty_2013"),
  t46_qty13_spend13     = c("log_raw_qty_2013", "log_raw_spend_2013"),

  # === Price slope (light) + qty level (heavy): pretrend anchored, flat qty ===
  t48_alp_slope_alp13_qty13 = c("avg_log_price_slope", "avg_log_price_2013",
                                "log_raw_qty_2013"),
  t35_annual_alp_11_13_qty  = c("avg_log_price_2011", "avg_log_price_2012",
                                "avg_log_price_2013", "log_raw_qty_slope"),

  # === Hybrid (price + qty both matched): slopes + year-specific levels ===
  t17_price_qty_slopes_levels13 = c("avg_log_price_slope", "log_raw_qty_slope",
                                    "avg_log_price_2013", "log_raw_qty_2013"),

  # === Annual price levels benchmark ===
  bench_alp_levels_11_13 = c("avg_log_price_2011", "avg_log_price_2012",
                             "avg_log_price_2013"),

  # === NEW 1-cov baselines: how much does a single covariate buy us? ===
  n01_alp_slope_only       = c("avg_log_price_slope"),
  n02_qty_slope_only       = c("log_raw_qty_slope"),
  n03_alp13_only           = c("avg_log_price_2013"),

  # === NEW 2-cov: vol-only slopes (no price covariate) ===
  n10_qty_spend_slopes     = c("log_raw_qty_slope", "log_raw_spend_slope"),

  # === NEW 2-cov: anchor each var's slope + same-var 2013 level ===
  n11_alp_slope_alp13      = c("avg_log_price_slope", "avg_log_price_2013"),
  n12_spend_slope_spend13  = c("log_raw_spend_slope", "log_raw_spend_2013"),

  # === NEW 2-cov: 2-year levels (richer pin than slope) ===
  n13_alp_12_13            = c("avg_log_price_2012", "avg_log_price_2013"),
  n14_qty_12_13            = c("log_raw_qty_2012", "log_raw_qty_2013"),
  n15_spend_12_13          = c("log_raw_spend_2012", "log_raw_spend_2013"),

  # === NEW 2-cov: cross 2013 levels (no slopes) ===
  n16_alp13_qty13          = c("avg_log_price_2013", "log_raw_qty_2013"),
  n17_alp13_spend13        = c("avg_log_price_2013", "log_raw_spend_2013"),

  # === NEW 2-cov: scale (log_spend_2013) + slope ===
  n18_alp_slope_logspend13 = c("avg_log_price_slope", "log_spend_2013"),
  n19_qty_slope_logspend13 = c("log_raw_qty_slope", "log_spend_2013"),

  # === NEW 3-cov: all three 2013 levels ===
  n20_alp13_qty13_spend13  = c("avg_log_price_2013", "log_raw_qty_2013",
                               "log_raw_spend_2013"),

  # === NEW 3-cov: price+qty slopes + a 2013 anchor ===
  n21_alp_qty_slopes_alp13   = c("avg_log_price_slope", "log_raw_qty_slope",
                                 "avg_log_price_2013"),
  n22_alp_qty_slopes_qty13   = c("avg_log_price_slope", "log_raw_qty_slope",
                                 "log_raw_qty_2013"),
  n23_alp_qty_slopes_spend13 = c("avg_log_price_slope", "log_raw_qty_slope",
                                 "log_raw_spend_2013"),

  # === NEW 3-cov: price slope + 2-year price levels ===
  n24_alp_slope_alp_12_13  = c("avg_log_price_slope", "avg_log_price_2012",
                               "avg_log_price_2013"),

  # === NEW 3-cov: qty slope + 2-year qty levels ===
  n25_qty_slope_qty_12_13  = c("log_raw_qty_slope", "log_raw_qty_2012",
                               "log_raw_qty_2013"),

  # === NEW 2-cov: price slope + 2013 spend level ===
  n26_alp_slope_spend13    = c("avg_log_price_slope", "log_raw_spend_2013"),

  # === v2 pre-period means (3-yr avg of 2011-2013, smoother than 2013-only) ===
  v01_alp_pre_mean              = c("avg_log_price_pre_mean"),
  v02_alp_qty_pre_means         = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean"),
  v03_three_pre_means           = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean",
                                    "log_raw_spend_pre_mean"),

  # === v2: 2-year pre-period change (2013-2011) as simpler alternative to slope ===
  v10_alp_pre_chg               = c("avg_log_price_pre_chg"),
  v11_alp_qty_pre_chg           = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg"),
  v12_alp_pre_chg_alp13         = c("avg_log_price_pre_chg", "avg_log_price_2013"),
  v13_qty_pre_chg_qty13         = c("log_raw_qty_pre_chg", "log_raw_qty_2013"),
  v14_three_pre_chg             = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg",
                                    "log_raw_spend_pre_chg"),

  # === v2: 3-year pre-period change (2013-2010) ===
  v15_alp_pre_chg3              = c("avg_log_price_pre_chg3"),
  v16_alp_qty_pre_chg3          = c("avg_log_price_pre_chg3", "log_raw_qty_pre_chg3"),

  # === v2: pre-period SD (within-cat volatility) + 2013 anchor ===
  v20_alp_pre_sd_alp13          = c("avg_log_price_pre_sd", "avg_log_price_2013"),
  v21_qty_pre_sd_qty13          = c("log_raw_qty_pre_sd", "log_raw_qty_2013"),

  # === v2: 2010 + 2013 anchors (no slope, early/late level pin) ===
  v30_alp_2010_2013             = c("avg_log_price_2010", "avg_log_price_2013"),
  v31_qty_2010_2013             = c("log_raw_qty_2010", "log_raw_qty_2013"),
  v32_alp_qty_2010_2013         = c("avg_log_price_2010", "avg_log_price_2013",
                                    "log_raw_qty_2010", "log_raw_qty_2013"),

  # === v2: full annual levels 2010-2013 (max info, no slope smoothing) ===
  v40_alp_annual_10_13          = c("avg_log_price_2010", "avg_log_price_2011",
                                    "avg_log_price_2012", "avg_log_price_2013"),
  v41_qty_annual_10_13          = c("log_raw_qty_2010", "log_raw_qty_2011",
                                    "log_raw_qty_2012", "log_raw_qty_2013"),

  # === v2: log_raw_price (different aggregation than avg_log_price) ===
  v50_lrp_slope_lrp13           = c("log_raw_price_slope", "log_raw_price_2013"),
  v51_lrp_qty_slopes            = c("log_raw_price_slope", "log_raw_qty_slope"),
  v52_lrp_pre_mean              = c("log_raw_price_pre_mean"),

  # === v2: size control (log_spend_2013) added ===
  v60_alp_pre_mean_size         = c("avg_log_price_pre_mean", "log_spend_2013"),
  v61_alp_qty_slopes_size       = c("avg_log_price_slope", "log_raw_qty_slope",
                                    "log_spend_2013"),
  v62_three_pre_means_size      = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean",
                                    "log_raw_spend_pre_mean", "log_spend_2013"),

  # === v2: cross-variable level mixes (early-of-one + late-of-other) ===
  v70_alp10_qty13               = c("avg_log_price_2010", "log_raw_qty_2013"),
  v71_alp13_qty10               = c("avg_log_price_2013", "log_raw_qty_2010"),

  # === v2: pre_mean + slope (level pin + direction) ===
  v80_alp_pre_mean_alp_slope    = c("avg_log_price_pre_mean", "avg_log_price_slope"),
  v81_qty_pre_mean_qty_slope    = c("log_raw_qty_pre_mean", "log_raw_qty_slope"),
  v82_two_pre_means_two_slopes  = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean",
                                    "avg_log_price_slope", "log_raw_qty_slope")
)

cat("\nTesting", length(specs), "specifications\n\n")

# ---------------------------
# Evaluation function (same as R2)
# ---------------------------
OUTCOME_VAR <- "avg_log_price"
# Outcomes scored for pretrend alignment ("across the board" metric)
PRETREND_VARS <- c("avg_log_price", "log_raw_qty", "log_raw_spend")

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

  # Save per-spec pre/post trend plot (treated vs matched controls)
  tryCatch(
    plot_match_trends(match_pairs, panel, spec_name, match_ratio),
    error = function(e) cat("  PLOT FAILED:", e$message, "\n")
  )

  # Save event-study-style residualized plot (uni+mkt FE, balanced uni-mkt panel)
  tryCatch(
    plot_match_trends_es(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  ES PLOT FAILED:", e$message, "\n")
  )

  # Save event-study gap plot: single line per outcome showing the
  # implied (treated - control) coefficient curve, residualized on uni + mkt FE.
  # This is what the actual event study identifies — read coefficients off it.
  tryCatch(
    plot_match_trends_gap(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  GAP PLOT FAILED:", e$message, "\n")
  )

  # Run the actual event study (lead/lag x treated, uni+mkt+year FE,
  # weighted by spend_2013, clustered by mkt) and plot coefficient curves.
  tryCatch(
    plot_event_study(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  ES PLOT (real) FAILED:", e$message, "\n")
  )

  # Pre- AND post-trend alignment: compute gaps per outcome (price/qty/spend)
  # in deviation-from-2013 form. post_gap_<v> measures how flat the implied
  # event-study coefficient curve is in the post period — a small post_gap_qty
  # means qty stays at parallel-trend baseline post-treatment (no qty effect).
  gaps_by_var <- setNames(vector("list", length(PRETREND_VARS)), PRETREND_VARS)
  post_gaps_by_var <- setNames(vector("list", length(PRETREND_VARS)), PRETREND_VARS)

  for (treated_cat in unique(match_pairs$treated_market)) {
    controls <- match_pairs %>%
      filter(treated_market == treated_cat) %>% pull(control_market) %>% unique()

    trend_data <- panel %>%
      filter(category %in% c(treated_cat, controls)) %>%
      select(category, year, treated, spend_2013, all_of(PRETREND_VARS))

    for (v in PRETREND_VARS) {
      sub <- trend_data %>%
        select(category, year, spend_2013, value = all_of(v)) %>%
        group_by(category) %>%
        mutate(value_adj = value - value[year == 2013]) %>%
        ungroup()

      t_trend <- sub %>% filter(category == treated_cat) %>%
        select(year, t_out = value_adj)

      c_trend <- sub %>% filter(category %in% controls) %>%
        group_by(year) %>%
        summarise(c_out = weighted.mean(value_adj, w = spend_2013, na.rm = TRUE),
                  .groups = "drop")

      merged <- inner_join(t_trend, c_trend, by = "year")
      if (nrow(merged) == 0) next

      pre_rows <- merged %>% filter(year <= 2013)
      post_rows <- merged %>% filter(year >= 2014)

      if (nrow(pre_rows) > 0)
        gaps_by_var[[v]] <- c(gaps_by_var[[v]],
                              mean(abs(pre_rows$t_out - pre_rows$c_out), na.rm = TRUE))
      if (nrow(post_rows) > 0)
        post_gaps_by_var[[v]] <- c(post_gaps_by_var[[v]],
                                   mean(abs(post_rows$t_out - post_rows$c_out), na.rm = TRUE))
    }
  }

  # Price-only metrics (kept for backward compatibility)
  pre_trend_gaps <- gaps_by_var[[OUTCOME_VAR]]
  mean_pre_gap <- mean(pre_trend_gaps, na.rm = TRUE)
  median_pre_gap <- median(pre_trend_gaps, na.rm = TRUE)
  p75_pre_gap <- quantile(pre_trend_gaps, 0.75, na.rm = TRUE)
  p90_pre_gap <- quantile(pre_trend_gaps, 0.90, na.rm = TRUE)
  pct_good <- mean(pre_trend_gaps < 0.05)
  pct_ok <- mean(pre_trend_gaps < 0.10)

  # Per-outcome means + across-outcome average (the "across the board" metric)
  pre_gap_price <- mean(gaps_by_var[["avg_log_price"]], na.rm = TRUE)
  pre_gap_qty   <- mean(gaps_by_var[["log_raw_qty"]],   na.rm = TRUE)
  pre_gap_spend <- mean(gaps_by_var[["log_raw_spend"]], na.rm = TRUE)
  pre_gap_avg   <- mean(c(pre_gap_price, pre_gap_qty, pre_gap_spend), na.rm = TRUE)
  pre_gap_max   <- max(c(pre_gap_price, pre_gap_qty, pre_gap_spend), na.rm = TRUE)

  # Post-period deviation gaps (event-study-coefficient-style): low values
  # mean the implied event-study curve stays near zero post-2013. Useful for
  # picking specs where qty/spend show no treatment effect (parallel post too).
  post_gap_price_dev <- mean(post_gaps_by_var[["avg_log_price"]], na.rm = TRUE)
  post_gap_qty_dev   <- mean(post_gaps_by_var[["log_raw_qty"]],   na.rm = TRUE)
  post_gap_spend_dev <- mean(post_gaps_by_var[["log_raw_spend"]], na.rm = TRUE)
  qty_total_dev      <- pre_gap_qty + post_gap_qty_dev
  spend_total_dev    <- pre_gap_spend + post_gap_spend_dev
  
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
  
  cat(sprintf("  SMD: mean=%.4f max=%.4f | Pre-gap (price): mean=%.4f | Pre-gap avg(p/q/s): %.4f (p=%.3f q=%.3f s=%.3f)\n",
              bal, max_smd, mean_pre_gap, pre_gap_avg,
              pre_gap_price, pre_gap_qty, pre_gap_spend))

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
    pre_gap_price = round(pre_gap_price, 4),
    pre_gap_qty   = round(pre_gap_qty,   4),
    pre_gap_spend = round(pre_gap_spend, 4),
    pre_gap_avg   = round(pre_gap_avg,   4),
    pre_gap_max   = round(pre_gap_max,   4),
    post_mean_gap = round(mean(post_gaps, na.rm = TRUE), 4),
    post_gap_price_dev = round(post_gap_price_dev, 4),
    post_gap_qty_dev   = round(post_gap_qty_dev,   4),
    post_gap_spend_dev = round(post_gap_spend_dev, 4),
    qty_total_dev      = round(qty_total_dev,      4),
    spend_total_dev    = round(spend_total_dev,    4),
    stringsAsFactors = FALSE
  )
}

# ---------------------------
# Run all specs
# ---------------------------
results_list <- list()

# Run each spec at multiple match ratios
RATIOS <- c(2, 3)
for (r in RATIOS) {
  cat(sprintf("\n========= MATCH RATIO = %d =========\n\n", r))
  for (spec_name in names(specs)) {
    res <- tryCatch(
      evaluate_spec(spec_name, specs[[spec_name]], data_wide, panel, match_ratio = r),
      error = function(e) { cat("  ERROR:", e$message, "\n\n"); NULL }
    )
    if (!is.null(res)) results_list[[paste0(spec_name, "_r", r)]] <- res
  }
}

# ---------------------------
# Compile and rank
# ---------------------------
results <- do.call(rbind, results_list) %>%
  as_tibble() %>%
  mutate(
    abs_post_gap        = abs(post_mean_gap),
    rank_pretrend_price = rank(pre_trend_mean_gap),
    rank_pretrend_avg   = rank(pre_gap_avg),
    rank_pretrend_max   = rank(pre_gap_max),
    rank_balance        = rank(mean_abs_smd),
    rank_coverage       = rank(n_treated_dropped),
    rank_post_price     = rank(-abs_post_gap),     # bigger |post gap| = better
    rank_simplicity     = rank(n_covariates),      # fewer covs = better
    composite_rank = (2 * rank_pretrend_avg + rank_balance + rank_coverage) / 4,
    # User-target composite: small pretrend across all 3 outcomes,
    # large |post gap| on price, and simple formula.
    target_rank = (2 * rank_pretrend_avg + 2 * rank_post_price + rank_simplicity) / 5
  ) %>%
  arrange(composite_rank)

cat("\n================================================================\n")
cat("ROUND 3 RESULTS: TREND-BASED MATCHING\n")
cat("================================================================\n\n")

results %>%
  select(spec, covariates, match_ratio, n_treated_matched, n_treated_dropped,
         mean_abs_smd, max_abs_smd,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg, pre_gap_max,
         pct_good_pretrend, pct_ok_pretrend, composite_rank) %>%
  print(n = Inf, width = Inf)

cat("\n--- Top 5 by ACROSS-OUTCOME pre-trend alignment (avg of price/qty/spend) ---\n")
results %>%
  arrange(pre_gap_avg) %>%
  slice_head(n = 5) %>%
  select(spec, covariates, match_ratio, mean_abs_smd,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg, pre_gap_max) %>%
  print(width = Inf)

cat("\n--- Top 5 by WORST-OUTCOME pre-trend (minimize the max across price/qty/spend) ---\n")
results %>%
  arrange(pre_gap_max) %>%
  slice_head(n = 5) %>%
  select(spec, covariates, match_ratio, mean_abs_smd,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg, pre_gap_max) %>%
  print(width = Inf)

cat("\n--- Top 5 by price-only pre-trend (legacy ranking) ---\n")
results %>%
  arrange(pre_trend_mean_gap) %>%
  slice_head(n = 5) %>%
  select(spec, covariates, match_ratio,
         mean_abs_smd, pre_trend_mean_gap, pct_good_pretrend, pct_ok_pretrend) %>%
  print(width = Inf)

cat("\n--- For each spec: best (lowest pre_gap_avg) ratio ---\n")
results %>%
  group_by(spec) %>%
  slice_min(pre_gap_avg, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(pre_gap_avg) %>%
  select(spec, covariates, match_ratio, mean_abs_smd,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg, pre_gap_max,
         post_mean_gap) %>%
  print(n = Inf, width = Inf)

cat("\n--- All (spec, ratio) combos sorted by across-outcome pre-trend (top 25) ---\n")
results %>%
  arrange(pre_gap_avg) %>%
  slice_head(n = 25) %>%
  select(spec, covariates, match_ratio, n_covariates, mean_abs_smd,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg, pre_gap_max,
         post_mean_gap) %>%
  print(width = Inf)

# ---------------------------
# User target: small pretrend (price/qty/spend) + large |post-price gap| + simple
# ---------------------------
cat("\n=================================================================\n")
cat("SIMPLE SPECS (<=3 covariates) ranked by user target across ALL ratios\n")
cat("  -> low pre_gap_avg + large |post_mean_gap| on price\n")
cat("=================================================================\n")
results %>%
  filter(n_covariates <= 3) %>%
  arrange(target_rank) %>%
  slice_head(n = 25) %>%
  select(spec, covariates, n_covariates, match_ratio,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg,
         post_mean_gap, abs_post_gap, mean_abs_smd, target_rank) %>%
  print(n = Inf, width = Inf)

cat("\n--- Same, only n_covariates <= 2 (simplest formulas) ---\n")
results %>%
  filter(n_covariates <= 2) %>%
  arrange(target_rank) %>%
  slice_head(n = 20) %>%
  select(spec, covariates, n_covariates, match_ratio,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg,
         post_mean_gap, abs_post_gap, mean_abs_smd) %>%
  print(n = Inf, width = Inf)

# Pareto frontier across ALL (spec, ratio) combos
cat("\n--- Pareto frontier: simple (<=3 covs) on (pre_gap_avg, |post|) ---\n")
simple <- results %>% filter(n_covariates <= 3)
is_pareto <- sapply(seq_len(nrow(simple)), function(i) {
  !any(simple$pre_gap_avg <= simple$pre_gap_avg[i] &
       simple$abs_post_gap >= simple$abs_post_gap[i] &
       (simple$pre_gap_avg < simple$pre_gap_avg[i] |
        simple$abs_post_gap > simple$abs_post_gap[i]))
})
simple %>%
  filter(is_pareto) %>%
  arrange(pre_gap_avg) %>%
  select(spec, covariates, n_covariates, match_ratio,
         pre_gap_price, pre_gap_qty, pre_gap_spend, pre_gap_avg,
         post_mean_gap, abs_post_gap) %>%
  print(n = Inf, width = Inf)

# ---------------------------
# Specs where qty event-study coefficient stays near 0 (pre AND post),
# AND price pretrend is small. Useful when you want flat qty throughout
# and only a price treatment effect.
# ---------------------------
cat("\n=================================================================\n")
cat("RANKED: low qty gap (pre+post) + low price pretrend (across ALL ratios)\n")
cat("  -> sort by (pre_gap_qty + post_gap_qty_dev) + pre_gap_price\n")
cat("=================================================================\n")
results %>%
  mutate(qty_flat_score = qty_total_dev + pre_gap_price) %>%
  arrange(qty_flat_score) %>%
  select(spec, covariates, n_covariates, match_ratio,
         pre_gap_price, pre_gap_qty, post_gap_qty_dev, qty_total_dev,
         post_gap_price_dev, post_mean_gap, mean_abs_smd) %>%
  print(n = 25, width = Inf)

write_csv(results, "../output/spec_search/spec_comparison_r3.csv")
cat("\nSaved to ../output/spec_search/spec_comparison_r3.csv\n")

cat("\nDone.\n")

