# ==============================================================================
# Task 3.2: Heterogeneity Analysis
# ==============================================================================
library(tidyverse)
library(fixest)
library(modelsummary)

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
  filter(as.numeric(as.character(year)) <= 2024) |>
  mutate(
    zcta = as.factor(zcta),
    border_dyad = as.factor(border_dyad),
    segment_id = as.factor(segment_id),
    year = as.factor(year),
    timeframe = ifelse(as.numeric(as.character(year)) <= 2019, "Pre-COVID (2012-2019)", "COVID-Era (2020-2024)"),
    delta_in_state_tuition = delta_in_state_tuition / 1000
  )

covariates <- paste0("Effective_Property_Tax_Rate + siitax + fiitax + ln_real_gdp_pc + Unemployment_Rate_ZCTA")

run_both_clusters <- function(formula_str, data_subset) {
  f <- as.formula(formula_str)
  m_single <- feols(f, data = data_subset, cluster = ~ zcta)
  m_twoway <- feols(f, data = data_subset, cluster = ~ zcta + border_dyad)
  list("Single" = m_single, "Two-Way" = m_twoway)
}

coef_map <- c(
  "S_i:delta_in_state_tuition" = "Tuition Gap LATE",
  "S_i:delta_top_100_caliber"  = "Caliber (Top 100) Gap LATE",
  "S_i:delta_top_50_caliber"   = "Caliber (Top 50) Gap LATE",
  "S_i:delta_top_20_caliber"   = "Caliber (Top 20) Gap LATE",
  "Effective_Property_Tax_Rate" = "Effective Property Tax Rate",
  "siitax" = "State Income Tax",
  "fiitax" = "Federal Income Tax",
  "ln_real_gdp_pc" = "Log Real GDP Per Capita",
  "Unemployment_Rate_ZCTA" = "Local Unemployment Rate"
)
gof_map <- c("nobs", "r.squared", "FE: segment_id^year")
stars <- c("*" = .1, "**" = .05, "***" = .01)

policy_formula_50 <- "delta_in_state_tuition + delta_top_50_caliber"
f_didc_full <- paste("ln_median_ppsf_acad ~ d_ic * S_i * (", policy_formula_50, ") +", covariates, "| segment_id^year")

# ==============================================================================
# 1. Timeframe Sub-sampling
# ==============================================================================
cat("\nRunning Timeframes...\n")
m_pre <- run_both_clusters(f_didc_full, df |> filter(timeframe == "Pre-COVID (2012-2019)"))
m_post <- run_both_clusters(f_didc_full, df |> filter(timeframe == "COVID-Era (2020-2024)"))

table_time <- modelsummary(
  c(m_pre, m_post), output = "data.frame", coef_map = coef_map, stars = stars, gof_map = gof_map,
  title = "Timeframe Heterogeneity (Top 50 Baseline)"
)
names(table_time)[4:7] <- c("Pre-COVID (Single)", "Pre-COVID (Two-Way)", "Post-COVID (Single)", "Post-COVID (Two-Way)")
writeLines(knitr::kable(table_time[, -1], format = "markdown"), file.path(output_dir, "het_table_2_timeframes.md"))

# ==============================================================================
# 2. Marginal Tax Cliff
# ==============================================================================
cat("\nRunning Marginal Tax Cliff...\n")
tax_gaps <- df |> group_by(border_dyad, year, S_i) |> summarize(mean_tax = mean(siitax, na.rm = TRUE), .groups = "drop") |> pivot_wider(names_from = S_i, values_from = mean_tax, names_prefix = "tax_S") |> mutate(tax_diff = abs(tax_S1 - tax_S0))
df_tax <- df |> left_join(tax_gaps |> select(border_dyad, year, tax_diff), by = c("border_dyad", "year"))
tax_diff_q25 <- quantile(df_tax$tax_diff, 0.25, na.rm = TRUE)
df_marginal_tax <- df_tax |> filter(tax_diff <= tax_diff_q25)

m_tax <- run_both_clusters(f_didc_full, df_marginal_tax)
table_tax <- modelsummary(
  m_tax, output = "data.frame", coef_map = coef_map, stars = stars, gof_map = gof_map,
  title = "Marginal Tax Cliff (Lowest Quartile of Tax Diff, Top 50 Baseline)"
)
names(table_tax)[4:5] <- c("Tax Cliff (Single)", "Tax Cliff (Two-Way)")
writeLines(knitr::kable(table_tax[, -1], format = "markdown"), file.path(output_dir, "het_table_3_tax_cliff.md"))

# ==============================================================================
# 3. Caliber Tiers (Top 20 vs Top 50 vs Top 100)
# ==============================================================================
cat("\nRunning Caliber Tiers (Top 20 vs Top 50 vs Top 100)...\n")

policy_formula_100 <- "delta_in_state_tuition + delta_top_100_caliber"
f_didc_100 <- paste("ln_median_ppsf_acad ~ d_ic * S_i * (", policy_formula_100, ") +", covariates, "| segment_id^year")

policy_formula_20 <- "delta_in_state_tuition + delta_top_20_caliber"
f_didc_20 <- paste("ln_median_ppsf_acad ~ d_ic * S_i * (", policy_formula_20, ") +", covariates, "| segment_id^year")

m_tier_100 <- run_both_clusters(f_didc_100, df)
m_tier_50 <- run_both_clusters(f_didc_full, df)
m_tier_20 <- run_both_clusters(f_didc_20, df)

table_tiers <- modelsummary(
  c(m_tier_100, m_tier_50, m_tier_20), output = "data.frame", coef_map = coef_map, stars = stars, gof_map = gof_map,
  title = "Caliber Option Value Tiers (Top 100 vs Top 50 vs Top 20)"
)
names(table_tiers)[4:9] <- c("Top 100 (Single)", "Top 100 (Two-Way)", "Top 50 (Single)", "Top 50 (Two-Way)", "Top 20 (Single)", "Top 20 (Two-Way)")
writeLines(knitr::kable(table_tiers[, -1], format = "markdown"), file.path(output_dir, "het_table_4_caliber_tiers.md"))

# ==============================================================================
# 4. Pure Price Elasticity
# ==============================================================================
cat("\nRunning Pure Price Elasticity (Same Caliber)...\n")
df_pure_price <- df |> filter(delta_top_50_caliber == 0)
policy_formula_pure <- "delta_in_state_tuition"
f_didc_pure <- paste("ln_median_ppsf_acad ~ d_ic * S_i * (", policy_formula_pure, ") +", covariates, "| segment_id^year")

m_pure <- run_both_clusters(f_didc_pure, df_pure_price)
table_pure <- modelsummary(
  m_pure, output = "data.frame", coef_map = coef_map, stars = stars, gof_map = gof_map,
  title = "Pure Price Elasticity (Equal Top 50 Caliber)"
)
names(table_pure)[4:5] <- c("Pure Price (Single)", "Pure Price (Two-Way)")
writeLines(knitr::kable(table_pure[, -1], format = "markdown"), file.path(output_dir, "het_table_5_pure_price.md"))

cat(sprintf("\nAll Heterogeneity Tasks Complete. Markdown tables exported to %s.\n", output_dir))
