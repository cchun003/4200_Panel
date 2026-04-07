# ==============================================================================
# Task 3: Econometric Regression Estimation (DiDC Framework)
# ==============================================================================
# Environment-Specific Stability Options:
# Bypassing factory formats by exporting to a data.frame first, then using knitr::kable.

library(tidyverse)
library(fixest)
library(modelsummary)

# ==============================================================================
# Step 1: Data Pre-Processing and Sample Restriction
# ==============================================================================
cat("Loading and configuring the estimation panel...\n")
# Use dynamic context parsing if run from terminal
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("--file=", args)
if (length(file_arg) > 0) {
  script_path <- sub("--file=", "", args[file_arg])
  base_dir <- dirname(script_path)
} else {
  base_dir <- getwd()
}

# Detect project root dynamically
if (dir.exists(file.path(base_dir, "Output"))) {
  proj_root <- base_dir
} else if (dir.exists(file.path(base_dir, "..", "Output"))) {
  proj_root <- file.path(base_dir, "..")
} else {
  proj_root <- base_dir # Fallback
}

output_dir <- file.path(proj_root, "Output")
input_file <- file.path(output_dir, "estimation_didc_panel.csv")

# Load data, restrict to RD estimation sample, and format variables
df <- read_csv(input_file, show_col_types = FALSE) |>
  filter(Estimation_Sample == 1) |>
  mutate(
    zcta = as.factor(zcta),
    border_dyad = as.factor(border_dyad),
    segment_id = as.factor(segment_id),
    year = as.factor(year),
    # Scale tuition gap to $1,000s for interpretable coefficients
    delta_in_state_tuition = delta_in_state_tuition / 1000
  )

# Define covariate matrix string for dynamic formula generation
covariates <- paste0(
  "Effective_Property_Tax_Rate + siitax + fiitax + ",
  "ln_real_gdp_pc + Unemployment_Rate_ZCTA"
)

# ==============================================================================
# Step 2: Define the Regression Function (fixest wrapper)
# ==============================================================================
# Using fixest::feols for high-speed estimation with multi-way clustering
estimate_models <- function(policy_formula, model_name_prefix) {
  # 1. Naive OLS (No spatial gradient, no fixed effects)
  f_ols <- as.formula(paste("ln_median_ppsf ~ S_i * (", policy_formula, ")"))
  m_ols <- feols(f_ols, data = df, cluster = ~ zcta + border_dyad)

  # 2. Cross-Sectional Spatial RD (Local linear polynomials, no fixed effects)
  f_rd <- as.formula(paste("ln_median_ppsf ~ d_ic * S_i * (", policy_formula, ")"))
  m_rd <- feols(f_rd, data = df, cluster = ~ zcta + border_dyad)

  # 3. Baseline DiDC (Spatial RD + Segment-by-Year Fixed Effects)
  f_didc_base <- as.formula(paste("ln_median_ppsf ~ d_ic * S_i * (", policy_formula, ") | segment_id^year"))
  m_didc_base <- feols(f_didc_base, data = df, cluster = ~ zcta + border_dyad)

  # 4. Full DiDC (Baseline DiDC + Time-varying tax/macro covariates)
  f_didc_full <- as.formula(paste("ln_median_ppsf ~ d_ic * S_i * (", policy_formula, ") +", covariates, "| segment_id^year"))
  m_didc_full <- feols(f_didc_full, data = df, cluster = ~ zcta + border_dyad)

  # Return named list of models
  res <- list()
  res[[paste0(model_name_prefix, " 1: Naive OLS")]] <- m_ols
  res[[paste0(model_name_prefix, " 2: Spatial RD")]] <- m_rd
  res[[paste0(model_name_prefix, " 3: Base DiDC")]] <- m_didc_base
  res[[paste0(model_name_prefix, " 4: Full DiDC")]] <- m_didc_full

  res
}

# ==============================================================================
# Step 3: Estimate the 12 Target Models
# ==============================================================================
cat("Estimating 12 specifications via feols with multi-way clustering...\n")

# A. Tuition Gap Isolation
models_tuition <- estimate_models("delta_in_state_tuition", "Tuition")

# B. Caliber Gap Isolation (Top 100 as baseline index)
models_caliber <- estimate_models("delta_top_100_caliber", "Caliber")

# C. Joint Estimation (Holding simultaneous policies constant)
models_joint <- estimate_models("delta_in_state_tuition + delta_top_100_caliber", "Joint")

# Combine all models into a single master list for export
all_models <- c(models_tuition, models_caliber, models_joint)

# ==============================================================================
# Step 4: VIF / Collinearity Check on the Joint Full Model
# ==============================================================================
cat("\nChecking collinearity for the Full Joint DiDC Specification...\n")
collin_check <- collinearity(all_models[["Joint 4: Full DiDC"]])
print(collin_check)

# ==============================================================================
# Step 5: Export to Markdown via modelsummary
# ==============================================================================
cat("\nGenerating publication-ready Markdown tables...\n")

coef_map <- c(
  "S_i:delta_in_state_tuition" = "Tuition Gap LATE (S_i x Delta Tuition, $1k)",
  "S_i:delta_top_100_caliber" = "Caliber Gap LATE (S_i x Delta Caliber)",
  "S_i" = "Spatial Treatment (S_i)",
  "delta_in_state_tuition" = "Tuition Gap (Delta Policy, $1k)",
  "delta_top_100_caliber" = "Caliber Gap (Delta Policy)",
  "Effective_Property_Tax_Rate" = "Effective Property Tax Rate",
  "siitax" = "State Income Tax Liability",
  "ln_real_gdp_pc" = "Log Real GDP Per Capita",
  "Unemployment_Rate_ZCTA" = "Local Unemployment Rate"
)

# Render Tuition models to Markdown
table_1_df <- modelsummary(
  models_tuition,
  output = "data.frame",
  coef_map = coef_map,
  stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "adj.r.squared", "FE: segment_id^year"),
  title = "Table 1: Capitalization of Higher Education Tuition Subsidies"
)
writeLines(knitr::kable(table_1_df[, -1], format = "markdown"), file.path(output_dir, "table_1_tuition_didc.md"))

# Render Caliber models to Markdown
table_2_df <- modelsummary(
  models_caliber,
  output = "data.frame",
  coef_map = coef_map,
  stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "adj.r.squared", "FE: segment_id^year"),
  title = "Table 2: Capitalization of Higher Education Institutional Caliber"
)
writeLines(knitr::kable(table_2_df[, -1], format = "markdown"), file.path(output_dir, "table_2_caliber_didc.md"))

# Render Joint models to Markdown
table_3_df <- modelsummary(
  models_joint,
  output = "data.frame",
  coef_map = coef_map,
  stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "adj.r.squared", "FE: segment_id^year"),
  title = "Table 3: Joint Capitalization Model (Tuition and Caliber)"
)
writeLines(knitr::kable(table_3_df[, -1], format = "markdown"), file.path(output_dir, "table_3_joint_didc.md"))

cat(sprintf("Task 3 Complete. Markdown tables exported to %s.\n", output_dir))
