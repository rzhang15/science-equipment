library(tidyverse)
library(MatchIt)
library(haven)
library(broom)
library(fixest)
set.seed(8975)

setwd("~/sci_eq/derived/first_stage/match_control/code")
dir.create("../output/spec_search", recursive = TRUE, showWarnings = FALSE)

cat("Loading data...\n")
panel <- read_dta("../external/samp/category_yr_tfidf.dta") %>%
  mutate(category = as.character(category))

cat("Panel:", n_distinct(panel$category), "categories x",
    n_distinct(panel$year), "years\n\n")

cat("Loading uni-cat-year panel for event-study pretrend plots...\n")
uni_panel <- read_dta("../external/samp/uni_category_yr_tfidf.dta") %>%
  mutate(category = as.character(category)) %>%
  select(uni_id, category, mkt, year, treated, spend_2013,
         avg_log_price, log_raw_qty, log_raw_spend) %>%
  filter(!is.na(spend_2013))
cat("Uni panel:", nrow(uni_panel), "rows |",
    n_distinct(uni_panel$uni_id), "unis x",
    n_distinct(uni_panel$category), "cats\n\n")

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

  out <- long %>%
    mutate(spec = spec_name, match_ratio = match_ratio) %>%
    select(spec, match_ratio, outcome, year, rel, estimate, std.error,
           conf.low, conf.high)
  dir.create("../output/spec_search/es_coefs", recursive = TRUE, showWarnings = FALSE)
  write_csv(out, sprintf("../output/spec_search/es_coefs/es_r%d_%s.csv", match_ratio, spec_name))

  invisible(long)
}

plot_event_study_split <- function(match_pairs, uni_panel, spec_name, match_ratio,
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

  out_list <- list()
  for (v in vars) {
    rows <- !is.na(sub[[v]]) & !is.na(sub$spend_2013)
    if (sum(rows) < 100) next
    d <- sub[rows, ]
    fit <- tryCatch(
      fixest::feols(
        stats::as.formula(paste(v,
          "~ i(year, ref = 2013) + i(year, treated, ref = 2013) | uni_id + mkt")),
        data = d, weights = ~spend_2013, cluster = ~mkt,
        notes = FALSE, warn = FALSE),
      error = function(e) { cat("    split feols failed for", v, ":", e$message, "\n"); NULL }
    )
    if (is.null(fit)) next

    coefs <- coef(fit)
    vc    <- vcov(fit)

    yr_terms <- grep("^year::[0-9]+$", names(coefs), value = TRUE)
    yrs <- sort(as.integer(sub("^year::([0-9]+)$", "\\1", yr_terms)))

    ctrl_rows <- dplyr::bind_rows(lapply(yrs, function(yr) {
      tm <- paste0("year::", yr)
      data.frame(year = yr,
                 estimate  = unname(coefs[tm]),
                 std.error = sqrt(unname(vc[tm, tm])),
                 series = "Control")
    }))
    ctrl_rows <- dplyr::bind_rows(ctrl_rows,
      data.frame(year = 2013L, estimate = 0, std.error = 0, series = "Control"))

    trt_rows <- dplyr::bind_rows(lapply(yrs, function(yr) {
      tm_yr <- paste0("year::", yr)
      tm_di <- paste0("year::", yr, ":treated")
      if (!(tm_di %in% names(coefs))) return(NULL)
      est <- unname(coefs[tm_yr] + coefs[tm_di])
      var_est <- unname(vc[tm_yr, tm_yr] + vc[tm_di, tm_di] +
                          2 * vc[tm_yr, tm_di])
      data.frame(year = yr, estimate = est,
                 std.error = sqrt(pmax(var_est, 0)), series = "Treated")
    }))
    trt_rows <- dplyr::bind_rows(trt_rows,
      data.frame(year = 2013L, estimate = 0, std.error = 0, series = "Treated"))

    out <- dplyr::bind_rows(ctrl_rows, trt_rows) %>%
      mutate(rel = year - 2014, outcome = v)

    ctrl_only <- out %>% filter(series == "Control") %>% arrange(rel)
    if (nrow(ctrl_only) >= 2 && diff(range(ctrl_only$rel)) > 0) {
      fit_ctrl <- lm(estimate ~ rel, data = ctrl_only)
      trend <- predict(fit_ctrl, newdata = data.frame(rel = out$rel))
      base  <- predict(fit_ctrl, newdata = data.frame(rel = -1))
      out$estimate <- out$estimate - trend + base
    }
    out$conf.low  <- out$estimate - 1.96 * out$std.error
    out$conf.high <- out$estimate + 1.96 * out$std.error

    out_list[[v]] <- out
  }

  if (length(out_list) == 0) return(invisible(NULL))

  long <- dplyr::bind_rows(out_list) %>%
    mutate(outcome = factor(outcome, levels = vars,
                            labels = c("log price", "log qty", "log spend")))

  p <- ggplot(long, aes(x = rel, y = estimate, color = series, group = series)) +
    geom_hline(yintercept = 0, color = "grey60") +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey40") +
    geom_line(linewidth = 0.5, alpha = 0.7) +
    geom_pointrange(aes(ymin = conf.low, ymax = conf.high), size = 0.3,
                    position = position_dodge(width = 0.25)) +
    facet_wrap(~ outcome, scales = "free_y") +
    scale_color_manual(values = c("Control" = "#ff7f00", "Treated" = "#1f78b4")) +
    scale_x_continuous(breaks = -4:5) +
    labs(x = "Years from 2014",
         y = "Event-study coefficient (linearly detrended, rel. to 2013)",
         color = NULL,
         title = sprintf("%s (ratio=%d) - split event study (treated vs control)",
                         spec_name, match_ratio),
         subtitle = sprintf("uni+mkt FE, w=spend_2013, cluster=mkt | n_uni=%d  trt mkts=%d  ctrl mkts=%d",
                            n_uni, n_mkt_t, n_mkt_c)) +
    theme_bw() +
    theme(legend.position = "bottom")

  dir.create("../output/spec_search/spec_event_study_split",
             recursive = TRUE, showWarnings = FALSE)
  ggsave(sprintf("../output/spec_search/spec_event_study_split/es_split_r%d_%s.png",
                 match_ratio, spec_name),
         p, width = 10, height = 4, dpi = 150)

  invisible(long)
}

pre_panel <- panel %>% filter(year <= 2013)


pre_panel <- pre_panel %>% mutate(year_c = year - 2012)

get_trend <- function(df, var) {
  y <- df[[var]]
  x <- df$year_c
  if (sum(!is.na(y)) < 2) {
    return(data.frame(slope = NA_real_, intercept = NA_real_))
  }
  fit <- lm(y ~ x)
  data.frame(slope = coef(fit)[2], intercept = coef(fit)[1])
}

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

levels_2013 <- panel %>%
  filter(year == 2013) %>%
  select(category, avg_log_price_2013 = avg_log_price,
         log_raw_spend_2013 = log_raw_spend,
         log_raw_price_2013 = log_raw_price,
         log_raw_qty_2013 = log_raw_qty,
         raw_spend_2013 = raw_spend,
         raw_qty_2013 = raw_qty)

data_wide <- trends %>%
  left_join(levels_2013, by = "category") %>%
  mutate(log_spend_2013 = log(spend_2013 + 1))

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
    avg_log_price_pre_chg = avg_log_price_2013 - avg_log_price_2011,
    log_raw_qty_pre_chg   = log_raw_qty_2013   - log_raw_qty_2011,
    log_raw_spend_pre_chg = log_raw_spend_2013 - log_raw_spend_2011,
    log_raw_price_pre_chg = log_raw_price_2013 - log_raw_price_2011,
    avg_log_price_pre_chg3 = avg_log_price_2013 - avg_log_price_2010,
    log_raw_qty_pre_chg3   = log_raw_qty_2013   - log_raw_qty_2010
  )

cat("\nWide data:", nrow(data_wide), "categories x", ncol(data_wide), "columns\n")

cat("\n--- Trend variable summaries (treated vs control) ---\n")
for (v in c("avg_log_price_slope", "avg_log_price_intercept",
            "log_raw_spend_slope", "log_raw_price_slope")) {
  t_vals <- data_wide %>% filter(treated == 1) %>% pull(!!sym(v))
  c_vals <- data_wide %>% filter(treated == 0) %>% pull(!!sym(v))
  cat(sprintf("  %-30s | Treated: mean=%.4f sd=%.4f | Control: mean=%.4f sd=%.4f\n",
              v, mean(t_vals, na.rm = TRUE), sd(t_vals, na.rm = TRUE),
              mean(c_vals, na.rm = TRUE), sd(c_vals, na.rm = TRUE)))
}

specs <- list(
  t10_alp_spend_slopes = c("avg_log_price_slope", "log_raw_spend_slope"),
  t13_alp_qty_slopes   = c("avg_log_price_slope", "log_raw_qty_slope"),
  t14_three_slopes     = c("avg_log_price_slope", "log_raw_spend_slope",
                           "log_raw_qty_slope"),

  t29_qty_slope_qty13   = c("log_raw_qty_slope", "log_raw_qty_2013"),
  t46_qty13_spend13     = c("log_raw_qty_2013", "log_raw_spend_2013"),

  t48_alp_slope_alp13_qty13 = c("avg_log_price_slope", "avg_log_price_2013",
                                "log_raw_qty_2013"),
  t35_annual_alp_11_13_qty  = c("avg_log_price_2011", "avg_log_price_2012",
                                "avg_log_price_2013", "log_raw_qty_slope"),

  t17_price_qty_slopes_levels13 = c("avg_log_price_slope", "log_raw_qty_slope",
                                    "avg_log_price_2013", "log_raw_qty_2013"),

  bench_alp_levels_11_13 = c("avg_log_price_2011", "avg_log_price_2012",
                             "avg_log_price_2013"),

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

  n20_alp13_qty13_spend13  = c("avg_log_price_2013", "log_raw_qty_2013",
                               "log_raw_spend_2013"),

  n21_alp_qty_slopes_alp13   = c("avg_log_price_slope", "log_raw_qty_slope",
                                 "avg_log_price_2013"),
  n22_alp_qty_slopes_qty13   = c("avg_log_price_slope", "log_raw_qty_slope",
                                 "log_raw_qty_2013"),
  n23_alp_qty_slopes_spend13 = c("avg_log_price_slope", "log_raw_qty_slope",
                                 "log_raw_spend_2013"),

  n24_alp_slope_alp_12_13  = c("avg_log_price_slope", "avg_log_price_2012",
                               "avg_log_price_2013"),

  n25_qty_slope_qty_12_13  = c("log_raw_qty_slope", "log_raw_qty_2012",
                               "log_raw_qty_2013"),

  n26_alp_slope_spend13    = c("avg_log_price_slope", "log_raw_spend_2013"),

  v01_alp_pre_mean              = c("avg_log_price_pre_mean"),
  v02_alp_qty_pre_means         = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean"),
  v03_three_pre_means           = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean",
                                    "log_raw_spend_pre_mean"),

  v10_alp_pre_chg               = c("avg_log_price_pre_chg"),
  v11_alp_qty_pre_chg           = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg"),
  v12_alp_pre_chg_alp13         = c("avg_log_price_pre_chg", "avg_log_price_2013"),
  v13_qty_pre_chg_qty13         = c("log_raw_qty_pre_chg", "log_raw_qty_2013"),
  v14_three_pre_chg             = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg",
                                    "log_raw_spend_pre_chg"),

  v15_alp_pre_chg3              = c("avg_log_price_pre_chg3"),
  v16_alp_qty_pre_chg3          = c("avg_log_price_pre_chg3", "log_raw_qty_pre_chg3"),

  v20_alp_pre_sd_alp13          = c("avg_log_price_pre_sd", "avg_log_price_2013"),
  v21_qty_pre_sd_qty13          = c("log_raw_qty_pre_sd", "log_raw_qty_2013"),

  v30_alp_2010_2013             = c("avg_log_price_2010", "avg_log_price_2013"),
  v31_qty_2010_2013             = c("log_raw_qty_2010", "log_raw_qty_2013"),
  v32_alp_qty_2010_2013         = c("avg_log_price_2010", "avg_log_price_2013",
                                    "log_raw_qty_2010", "log_raw_qty_2013"),

  v40_alp_annual_10_13          = c("avg_log_price_2010", "avg_log_price_2011",
                                    "avg_log_price_2012", "avg_log_price_2013"),
  v41_qty_annual_10_13          = c("log_raw_qty_2010", "log_raw_qty_2011",
                                    "log_raw_qty_2012", "log_raw_qty_2013"),

  v50_lrp_slope_lrp13           = c("log_raw_price_slope", "log_raw_price_2013"),
  v51_lrp_qty_slopes            = c("log_raw_price_slope", "log_raw_qty_slope"),
  v52_lrp_pre_mean              = c("log_raw_price_pre_mean"),

  v60_alp_pre_mean_size         = c("avg_log_price_pre_mean", "log_spend_2013"),
  v61_alp_qty_slopes_size       = c("avg_log_price_slope", "log_raw_qty_slope",
                                    "log_spend_2013"),
  v62_three_pre_means_size      = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean",
                                    "log_raw_spend_pre_mean", "log_spend_2013"),

  v70_alp10_qty13               = c("avg_log_price_2010", "log_raw_qty_2013"),
  v71_alp13_qty10               = c("avg_log_price_2013", "log_raw_qty_2010"),

  v80_alp_pre_mean_alp_slope    = c("avg_log_price_pre_mean", "avg_log_price_slope"),
  v81_qty_pre_mean_qty_slope    = c("log_raw_qty_pre_mean", "log_raw_qty_slope"),
  v82_two_pre_means_two_slopes  = c("avg_log_price_pre_mean", "log_raw_qty_pre_mean",
                                    "avg_log_price_slope", "log_raw_qty_slope"),

  w01_spend_pre_mean_only         = c("log_raw_spend_pre_mean"),
  w02_spend_pre_chg_only          = c("log_raw_spend_pre_chg"),
  w03_spend_pre_mean_spend13      = c("log_raw_spend_pre_mean", "log_raw_spend_2013"),
  w04_spend_pre_chg_spend13       = c("log_raw_spend_pre_chg", "log_raw_spend_2013"),
  w05_spend_alp_pre_means         = c("log_raw_spend_pre_mean", "avg_log_price_pre_mean"),

  w10_spend_2010_2013             = c("log_raw_spend_2010", "log_raw_spend_2013"),
  w11_spend_2012_2013             = c("log_raw_spend_2012", "log_raw_spend_2013"),
  w12_spend_annual_10_13          = c("log_raw_spend_2010", "log_raw_spend_2011",
                                      "log_raw_spend_2012", "log_raw_spend_2013"),

  w20_alp_2011_only               = c("avg_log_price_2011"),
  w21_qty_2011_only               = c("log_raw_qty_2011"),
  w22_alp_2011_2013               = c("avg_log_price_2011", "avg_log_price_2013"),
  w23_qty_2011_2013               = c("log_raw_qty_2011", "log_raw_qty_2013"),

  w30_two_pre_chg_alp13           = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg",
                                      "avg_log_price_2013"),
  w31_two_pre_chg_qty13           = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg",
                                      "log_raw_qty_2013"),
  w32_three_pre_chg_size          = c("avg_log_price_pre_chg", "log_raw_qty_pre_chg",
                                      "log_raw_spend_pre_chg", "log_spend_2013"),

  w40_alp_slope_alp_pre_mean      = c("avg_log_price_slope", "avg_log_price_pre_mean"),
  w41_qty_slope_qty_pre_mean      = c("log_raw_qty_slope", "log_raw_qty_pre_mean"),

  w50_logspend13_only             = c("log_spend_2013"),
  w51_alp13_logspend13            = c("avg_log_price_2013", "log_spend_2013"),
  w52_qty13_logspend13            = c("log_raw_qty_2013", "log_spend_2013"),

  w60_alp_pre_chg_pre_mean        = c("avg_log_price_pre_chg", "avg_log_price_pre_mean"),
  w61_qty_pre_chg_pre_mean        = c("log_raw_qty_pre_chg", "log_raw_qty_pre_mean"),

  w70_alp_pre_mean_qty_pre_chg    = c("avg_log_price_pre_mean", "log_raw_qty_pre_chg"),
  w71_alp_pre_chg_qty_pre_mean    = c("avg_log_price_pre_chg", "log_raw_qty_pre_mean"),

  w80_lrp_pre_chg_only            = c("log_raw_price_pre_chg"),
  w81_lrp_pre_mean_lrp13          = c("log_raw_price_pre_mean", "log_raw_price_2013"),
  w82_lrp_qty_pre_chg             = c("log_raw_price_pre_chg", "log_raw_qty_pre_chg"),
  w83_lrp_pre_chg_lrp13           = c("log_raw_price_pre_chg", "log_raw_price_2013"),

  w90_alp_kitchen_sink            = c("avg_log_price_slope", "avg_log_price_pre_chg",
                                      "avg_log_price_pre_mean", "avg_log_price_2013"),
  w91_qty_kitchen_sink            = c("log_raw_qty_slope", "log_raw_qty_pre_chg",
                                      "log_raw_qty_pre_mean", "log_raw_qty_2013")
)

cat("\nTesting", length(specs), "specifications\n\n")

OUTCOME_VAR <- "avg_log_price"
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

  tryCatch(
    plot_match_trends(match_pairs, panel, spec_name, match_ratio),
    error = function(e) cat("  PLOT FAILED:", e$message, "\n")
  )

  tryCatch(
    plot_match_trends_es(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  ES PLOT FAILED:", e$message, "\n")
  )

  tryCatch(
    plot_match_trends_gap(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  GAP PLOT FAILED:", e$message, "\n")
  )

  tryCatch(
    plot_event_study(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  ES PLOT (real) FAILED:", e$message, "\n")
  )

  tryCatch(
    plot_event_study_split(match_pairs, uni_panel, spec_name, match_ratio),
    error = function(e) cat("  ES SPLIT PLOT FAILED:", e$message, "\n")
  )

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

  pre_trend_gaps <- gaps_by_var[[OUTCOME_VAR]]
  mean_pre_gap <- mean(pre_trend_gaps, na.rm = TRUE)
  median_pre_gap <- median(pre_trend_gaps, na.rm = TRUE)
  p75_pre_gap <- quantile(pre_trend_gaps, 0.75, na.rm = TRUE)
  p90_pre_gap <- quantile(pre_trend_gaps, 0.90, na.rm = TRUE)
  pct_good <- mean(pre_trend_gaps < 0.05)
  pct_ok <- mean(pre_trend_gaps < 0.10)

  pre_gap_price <- mean(gaps_by_var[["avg_log_price"]], na.rm = TRUE)
  pre_gap_qty   <- mean(gaps_by_var[["log_raw_qty"]],   na.rm = TRUE)
  pre_gap_spend <- mean(gaps_by_var[["log_raw_spend"]], na.rm = TRUE)
  pre_gap_avg   <- mean(c(pre_gap_price, pre_gap_qty, pre_gap_spend), na.rm = TRUE)
  pre_gap_max   <- max(c(pre_gap_price, pre_gap_qty, pre_gap_spend), na.rm = TRUE)

  post_gap_price_dev <- mean(post_gaps_by_var[["avg_log_price"]], na.rm = TRUE)
  post_gap_qty_dev   <- mean(post_gaps_by_var[["log_raw_qty"]],   na.rm = TRUE)
  post_gap_spend_dev <- mean(post_gaps_by_var[["log_raw_spend"]], na.rm = TRUE)
  qty_total_dev      <- pre_gap_qty + post_gap_qty_dev
  spend_total_dev    <- pre_gap_spend + post_gap_spend_dev
  
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

results_list <- list()

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

results <- do.call(rbind, results_list) %>%
  as_tibble() %>%
  mutate(
    abs_post_gap        = abs(post_mean_gap),
    rank_pretrend_price = rank(pre_trend_mean_gap),
    rank_pretrend_avg   = rank(pre_gap_avg),
    rank_pretrend_max   = rank(pre_gap_max),
    rank_balance        = rank(mean_abs_smd),
    rank_coverage       = rank(n_treated_dropped),
    rank_post_price     = rank(-abs_post_gap),
    rank_simplicity     = rank(n_covariates),
    composite_rank = (2 * rank_pretrend_avg + rank_balance + rank_coverage) / 4,
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

