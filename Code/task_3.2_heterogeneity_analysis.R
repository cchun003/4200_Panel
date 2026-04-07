# ==============================================================================
# Task 3.2: Heterogeneity Analysis
# ==============================================================================
# Environment-Specific Stability Options:
# Bypassing factory formats by exporting to a data.frame first, then using knitr::kable.

library(tidyverse)
library(fixest)
library(modelsummary)

# ==============================================================================
# Step 1: Data Pre-Processing and Sample Loading
# ==============================================================================
cat("Loading and configuring the estimation panel...\n")
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("--file=", args)
if (length(file_arg) > 0) {
  script_path <- sub("--file=", "", args[file_arg])
  base_dir <- dirname(script_path)
} else {
  base_dir <- getwd()
}

if (dir.exists(file.path(base_dir, "Output"))) {
  proj_root <- base_dir
} else if (dir.exists(file.path(base_dir, "..", "Output"))) {
  proj_root <- file.path(base_dir, "..")
} else {
  proj_root <- base_dir 
}

output_dir <- file.path(proj_root, "Output")
input_file <- file.path(output_dir, "estimation_didc_panel.csv")

df <- read_csv(input_file, show_col_types = FALSE) |>
  filter(Estimation_Sample == 1) |>
  mutate(
    zcta = as.factor(zcta),
    border_dyad = as.factor(border_dyad),
    segment_id = as.factor(segment_id),
    year = as.factor(year),
    timeframe = ifelse(as.numeric(as.character(year)) <= 2019, "Pre-COVID (2012-2019)", "COVID-Era (2020+)"),
    delta_in_state_tuition = delta_in_state_tuition / 1000
  )

covariates <- paste0(
  "Effective_Property_Tax_Rate + siitax + fiitax + ",
  "ln_real_gdp_pc + Unemployment_Rate_ZCTA"
)

# Base formulas for Full joint DiDC
policy_formula <- "delta_in_state_tuition + delta_top_100_caliber"
f_didc_full <- as.formula(paste("ln_median_ppsf ~ d_ic * S_i * (", policy_formula, ") +", covariates, "| segment_id^year"))

# ==============================================================================
# Priority 1: Relaxing Standard Error Clustering
# ==============================================================================
cat("\nExecuting Priority 1: Single-Way vs Two-Way Clustering...\n")

m_cluster_twoway <- feols(f_didc_full, data = df, cluster = ~ zcta + border_dyad)
m_cluster_single_zcta <- feols(f_didc_full, data = df, cluster = ~ zcta)
m_cluster_single_seg <- feols(f_didc_full, data = df, cluster = ~ segment_id)

cluster_models <- list(
  "Two-Way (Ref)" = m_cluster_twoway,
  "Single (ZCTA)" = m_cluster_single_zcta,
  "Single (Segment)" = m_cluster_single_seg
)

coef_map <- c(
  "S_i:delta_in_state_tuition" = "Tuition Gap LATE",
  "S_i:delta_top_100_caliber"  = "Caliber Gap LATE"
)

# Export Clustering Table
cluster_table <- modelsummary(
  cluster_models,
  output = "data.frame",
  coef_map = coef_map,
  stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "FE: segment_id^year"),
  title = "Heterogeneity: Alternative SE Clustering on Full DiDC"
)
writeLines(knitr::kable(cluster_table[, -1], format = "markdown"), file.path(output_dir, "het_table_1_clustering.md"))

# ==============================================================================
# Priority 2: Timeframe Sub-sampling
# ==============================================================================
cat("\nExecuting Priority 2: Timeframe Sub-sampling (Pre-COVID vs Post-COVID)...\n")

df_pre <- df |> filter(timeframe == "Pre-COVID (2012-2019)")
df_post <- df |> filter(timeframe == "COVID-Era (2020+)")

# We use Single (ZCTA) clustering going forward to relax variance penalty
m_time_all <- feols(f_didc_full, data = df, cluster = ~ zcta)
m_time_pre <- feols(f_didc_full, data = df_pre, cluster = ~ zcta)
m_time_post <- feols(f_didc_full, data = df_post, cluster = ~ zcta)

timeframe_models <- list(
  "Full Panel" = m_time_all,
  "Pre-COVID (2012-2019)" = m_time_pre,
  "Post-COVID (2020+)" = m_time_post
)

# Export Timeframe Table
time_table <- modelsummary(
  timeframe_models,
  output = "data.frame",
  coef_map = coef_map,
  stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "FE: segment_id^year"),
  title = "Heterogeneity: Timeframe Splitting (Single Clustering)"
)
writeLines(knitr::kable(time_table[, -1], format = "markdown"), file.path(output_dir, "het_table_2_timeframes.md"))

cat(sprintf("\nTask 3.2 Complete. Markdown tables exported to %s.\n", output_dir))
