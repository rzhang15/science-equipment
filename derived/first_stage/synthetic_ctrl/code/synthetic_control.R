# --- 1. Load Libraries and Data ---
library(tidyverse)
library(fixest)
library(here)
library(haven)
library(Synth)
library(SCtools)
library(skimr)

# setwd("~/sci_eq/derived/first_stage/match_control/code")
dir.create("../output/figures", recursive = TRUE, showWarnings = FALSE)

panel_raw <- read_dta("../external/samp/category_yr_tfidf.dta")

# --- 2. Prepare Data ---
panel <- panel_raw %>% 
  mutate(category = as.character(category),
         mkt_id = as.numeric(as.factor(category)))

# Compute linear time trend coefficients
trends_pre <- panel %>%
  filter(year <= 2013) %>% 
  group_by(category) %>%
  summarise(
    coef_log_price = possibly(~coef(lm(avg_log_price ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    coef_log_spend = possibly(~coef(lm(avg_log_spend ~ year, .x, weights = spend_2013))[2], otherwise = NA_real_)(cur_data()),
    .groups = "drop"
  ) %>%
  ungroup() # <-- FIX 1: Add ungroup() after summarise

# Join the trends back in
panel <- panel %>% 
  left_join(trends_pre, by="category") %>%
  ungroup() # <-- FIX 2: Add ungroup() after join

# --- 3. Clean Data and Finalize Format ---
panel_clean <- panel %>%
  filter(
    !is.na(mkt_id) &            
      !is.na(avg_log_price) &   
      !is.na(coef_log_price) &  
      !is.na(raw_spend)
  ) %>%
  ungroup() %>% # <-- FIX 3: Add a final ungroup()
  as.data.frame() # <-- FIX 4: Convert from tibble to a classic data.frame

# --- 4. Create Unit Lists for the Loop (use panel_clean) ---
treated_mkts_list <- panel_clean %>% 
  filter(treated == 1) %>% 
  distinct(mkt_id) %>%
  pull(mkt_id)

ctrl_mkts_list <- panel_clean %>% 
  filter(treated == 0) %>% 
  distinct(mkt_id) %>%
  pull(mkt_id)
# --- 5. Loop Through Each Treated Market ---

all_synth_results <- list()
all_synth_plots <- list() # This will now store just the one path plot per market

print(paste("Starting synth loop for", length(treated_mkts_list), "treated markets..."))

for (current_treated_id in treated_mkts_list) {
  
  market_name <- panel_clean %>% 
    filter(mkt_id == current_treated_id) %>% 
    distinct(category) %>% 
    pull(category)
  
  print(paste("--- Running for:", market_name, "(ID:", current_treated_id, ") ---"))
  
  # 1. Run dataprep 
  dataprep.out <- dataprep(
    foo = panel_clean,
    predictors = c("coef_log_price"),
    time.predictors.prior = 2010:2013,
    special.predictors = list(
      list("raw_spend", 2013:2013, "mean")
    ),
    dependent = "avg_log_spend", # <-- Outcome is avg_log_spend
    unit.variable = "mkt_id",         
    unit.names.variable = "category", 
    time.variable = "year", 
    treatment.identifier =  current_treated_id, 
    controls.identifier = ctrl_mkts_list,     
    time.optimize.ssr = 2010:2013,
    time.plot = 2010:2019
  )
  
  # 2. Run the synth model
  synth.out <- try(synth(
    data.prep.obj = dataprep.out,
    method = "BFGS" 
  ), silent = TRUE)
  
  # 3. Check for success, print weights, and PLOT
  if (!"try-error" %in% class(synth.out)) {
    
    print("Synth successful. Generating plot...")
    
    all_synth_results[[as.character(current_treated_id)]] <- synth.out
    
    # --- Print Control Weights ---
    synth.tables <- synth.tab(dataprep.res = dataprep.out, synth.res = synth.out)
    controls_used <- as_tibble(synth.tables$tab.w) %>%
      filter(w.weights > 0.0001) %>%
      arrange(desc(w.weights))
    
    print("--- Control Market Weights: ---")
    print(controls_used)
    print("-------------------------------")
    
    
    # --- ------------------------------------------ ---
    # --- 1. Prepare Data for Plotting             ---
    # --- ------------------------------------------ ---
    
    # Create a vector of the years
    years_vec <- as.numeric(rownames(dataprep.out$Y1plot))
    
    # Get the treated unit's data (Y1) as a simple vector
    treated_Y_vec <- as.vector(dataprep.out$Y1plot)
    
    # Get the synthetic unit's data (Y0 * Weights) as a simple vector
    synth_Y_vec <- as.vector(dataprep.out$Y0plot %*% synth.out$solution.w)
    
    # Find the 2013 values for adjustment
    treated_2013_val <- treated_Y_vec[years_vec == 2013]
    synth_2013_val   <- synth_Y_vec[years_vec == 2013]
    
    # Create the ADJUSTED data
    treated_Y_adj <- treated_Y_vec - treated_2013_val
    synth_Y_adj   <- synth_Y_vec - synth_2013_val
    
    # Create a safe filename (replaces spaces/symbols with _)
    safe_market_name <- str_replace_all(market_name, "[^A-Za-z0-9]", "_")
    
    # --- ------------------------------------------ ---
    # --- 2. Generate PLOT 1: Path Plot (Adjusted)   ---
    # --- ------------------------------------------ ---
    
    path_plot_data <- tibble(
      year = years_vec,
      !!market_name := treated_Y_adj, # Adjusted Treated
      `Synthetic Control` = synth_Y_adj   # Adjusted Synthetic
    ) %>%
      pivot_longer(
        cols = -year,
        names_to = "group_label",
        values_to = "outcome_val"
      )
    
    p_path <- ggplot(path_plot_data, aes(x = year, y = outcome_val, color = group_label)) +
      geom_line(linewidth = 1) + 
      geom_point() +
      geom_vline(xintercept = 2013.5, linetype = "dashed", color = "gray40") +
      geom_hline(yintercept = 0, linetype = "dotted", color = "gray20") +
      labs(
        title = paste("Synthetic Control (Path Plot):", market_name),
        subtitle = "Treated Market vs. Synthetic Control Trend (Adjusted to 0 at 2013)",
        x = "Year",
        y = "Average Log Spend (Adjusted to 2013)",
        color = "Market Group"
      ) +
      theme_minimal(base_size = 12) +
      scale_x_continuous(breaks = seq(min(path_plot_data$year), max(path_plot_data$year), 1)) +
      theme(
        legend.position = "bottom",
        plot.title = element_text(face = "bold")
      )
    
    # Save the path plot
    ggsave(paste0("../output/figures/synth_PATH_plot_adj_", safe_market_name, ".pdf"), plot = p_path, width = 10, height = 7)
    
    # --- ------------------------------------------ ---
    # --- 3. (Gaps Plot Code Removed)              ---
    # --- ------------------------------------------ ---
    
    # --- ------------------------------------------ ---
    # --- 4. Print & Store Plot                    ---
    # --- ------------------------------------------ ---
    
    # Print the path plot to your RStudio Plots pane
    print(p_path)
    
    # Store the plot object
    all_synth_plots[[as.character(current_treated_id)]] <- p_path
    
  } else {
    # If synth failed, print the error
    print(paste("Synth FAILED for", market_name))
    print(synth.out)
  }
}

print("--- Synthetic control loop complete. ---")