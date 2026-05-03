# Dependency: install.packages(c("tidyverse", "fixest", "modelsummary", "rdrobust"))
library(tidyverse)
library(fixest)
library(modelsummary)
library(rdrobust)

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
    delta_in_state_tuition = delta_in_state_tuition / 1000
  )

covariates <- paste0(
  "Effective_Property_Tax_Rate + siitax + fiitax + ",
  "ln_real_gdp_pc + Unemployment_Rate_ZCTA"
)

estimate_models <- function(policy_formula, model_name_prefix) {
  # Natural Calendar (Jan-Dec) Models
  f_rd <- as.formula(paste("ln_median_ppsf ~ d_ic * S_i * (", policy_formula, ")"))
  m_rd <- feols(f_rd, data = df, cluster = ~ zcta + border_dyad)

  f_didc_full <- as.formula(paste("ln_median_ppsf ~ d_ic * S_i * (", policy_formula, ") +", covariates, "| segment_id^year"))
  m_didc_full <- feols(f_didc_full, data = df, cluster = ~ zcta + border_dyad)

  # Academic Calendar (Sept-Aug) Models
  f_rd_acad <- as.formula(paste("ln_median_ppsf_acad ~ d_ic * S_i * (", policy_formula, ")"))
  m_rd_acad <- feols(f_rd_acad, data = df, cluster = ~ zcta + border_dyad)

  f_didc_full_acad <- as.formula(paste("ln_median_ppsf_acad ~ d_ic * S_i * (", policy_formula, ") +", covariates, "| segment_id^year"))
  m_didc_full_acad <- feols(f_didc_full_acad, data = df, cluster = ~ zcta + border_dyad)

  res <- list()
  res[[paste0(model_name_prefix, " Natural (RD)")]] <- m_rd
  res[[paste0(model_name_prefix, " Natural (DiDC)")]] <- m_didc_full
  res[[paste0(model_name_prefix, " Acad (RD)")]] <- m_rd_acad
  res[[paste0(model_name_prefix, " Acad (DiDC)")]] <- m_didc_full_acad
  res
}

df_prestige_sample <- df |>
  filter(!is.na(delta_top_50_caliber))

cat("Estimating 12 specifications via feols with multi-way clustering...\n")
cat("   - Tuition-only models are restricted to the prestige-observed sample for comparability with caliber and joint models.\n")
df_full <- df
df <- df_prestige_sample
models_tuition <- estimate_models("delta_in_state_tuition", "Tuition")
df <- df_full
models_caliber <- estimate_models("delta_top_50_caliber", "Caliber")
models_joint <- estimate_models("delta_in_state_tuition + delta_top_50_caliber", "Joint")

all_models <- c(models_tuition, models_caliber, models_joint)

cat("\nChecking collinearity for the Full Joint DiDC Specification (Academic Calendar)...\n")
collin_check <- collinearity(all_models[["Joint Acad (DiDC)"]])
print(collin_check)

cat("\nGenerating publication-ready Markdown tables...\n")
coef_map <- c(
  "S_i:delta_in_state_tuition" = "Tuition Gap LATE (S_i x Delta Tuition, $1k)",
  "S_i:delta_top_50_caliber" = "Caliber Gap LATE (S_i x Top 50 Caliber)",
  "S_i" = "Spatial Treatment (S_i)",
  "delta_in_state_tuition" = "Tuition Gap (Delta Policy, $1k)",
  "delta_top_50_caliber" = "Top 50 Caliber Gap (Delta Policy)",
  "Effective_Property_Tax_Rate" = "Effective Property Tax Rate",
  "siitax" = "State Income Tax Liability",
  "fiitax" = "Federal Income Tax Liability",
  "ln_real_gdp_pc" = "Log Real GDP Per Capita",
  "Unemployment_Rate_ZCTA" = "Local Unemployment Rate"
)

table_1_df <- modelsummary(
  models_tuition, output = "data.frame", coef_map = coef_map, stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "adj.r.squared", "FE: segment_id^year"),
  title = "Table 1: Capitalization of Higher Education Tuition Subsidies (2012-2024)"
)
writeLines(knitr::kable(table_1_df[, -1], format = "markdown"), file.path(output_dir, "table_1_tuition_didc.md"))

table_2_df <- modelsummary(
  models_caliber, output = "data.frame", coef_map = coef_map, stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "adj.r.squared", "FE: segment_id^year"),
  title = "Table 2: Capitalization of Higher Education Institutional Caliber (Top 50, 2012-2024)"
)
writeLines(knitr::kable(table_2_df[, -1], format = "markdown"), file.path(output_dir, "table_2_caliber_didc.md"))

table_3_df <- modelsummary(
  models_joint, output = "data.frame", coef_map = coef_map, stars = c("*" = .1, "**" = .05, "***" = .01),
  gof_map = c("nobs", "r.squared", "adj.r.squared", "FE: segment_id^year"),
  title = "Table 3: Joint Capitalization Model (Tuition and Top 50 Caliber, 2012-2024)"
)
writeLines(knitr::kable(table_3_df[, -1], format = "markdown"), file.path(output_dir, "table_3_joint_didc.md"))

# ==============================================================================
# Step 4: RD Plot Generation for Prestige
# ==============================================================================
cat("\nGenerating RD Plots for Prestige Discontinuity...\n")

# Filter for segments where a Top 50 Caliber gap exists
prestige_signal <- df |> filter(abs(delta_top_50_caliber) > 0)

pdf(file.path(output_dir, "rd_plot_prestige.pdf"), width = 8, height = 6)
rdplot(y = prestige_signal$ln_median_ppsf, x = prestige_signal$d_ic, c = 0,
       kernel = "triangular", 
       title = "Local Discontinuity: House Price vs. Top 50 Prestige Access",
       y.label = "log(Price Per SqFt)", x.label = "Distance to Border (km)")
dev.off()

cat(sprintf("\nTask 3.1b Complete. Tables and Prestige RD Plot exported to %s.\n", output_dir))
