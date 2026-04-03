# ==============================================================================
# Task 3.1: Spatial Difference-in-Discontinuities (DiDC) Baseline OLS
# ==============================================================================
# Dependency: install.packages(c("tidyverse", "fixest"))
library(tidyverse)
library(fixest)

# Configuration
output_dir <- "Output"
input_file <- file.path(output_dir, "estimation_didc_panel.csv")

cat("Loading estimation panel (reduced h* sample)...\n")
df <- read_csv(input_file, show_col_types = FALSE) |>
  filter(Estimation_Sample == 1)

# Ensure the log outcomes and GDP columns exist as intended
cat("Defining regression vectors...\n")
df <- df |>
  mutate(
    # Outcome: ln Price Per SqFt
    y = ln_median_ppsf,
    # Standard independent variables (Interactions)
    # Unit: Tuition ($1,000s), Caliber (Count)
    x1 = interaction_tuition / 1000,
    x2 = interaction_caliber,
    # Fixed effect clusters
    fe_id = paste(segment_id, year, sep = "_")
  )

# ==============================================================================
# Step 1: Model Specifications
# ==============================================================================
cat("\nEstimating Spatial DiDC Models...\n")

# Model 1: Pooled OLS (Baseline)
m1 <- feglm(y ~ x1 + x2 + d_ic + S_i, data = df)

# Model 2: Adding Time-Varying Controls
m2 <- feglm(y ~ x1 + x2 + d_ic + S_i + log(Median_Household_Income) + Unemployment_Rate_ZCTA, data = df)

# Model 3: High-Dimensional Fixed Effects (Segment-Year)
# This is the standard spatial DiDC specification
m3 <- feols(y ~ x1 + x2 + d_ic + S_i | fe_id, data = df)

# ==============================================================================
# Step 2: Output Presentation
# ==============================================================================
cat("\n" %+% str_pad(" REGRESSION RESULTS ", 60, "-", "both") %+% "\n")

cat("\n[1] Pooled OLS Specification:\n")
print(summary(m1))

cat("\n[2] Controls Specification:\n")
print(summary(m2))

cat("\n[3] Segment-Year Fixed Effects Specification (Full DiDC):\n")
print(summary(m3))

cat("\n" %+% str_pad("", 60, "-") %+% "\n")
cat("Note: Treatment variables (x1, x2) scaled by $1,000 for tuition.\n")
cat("Task 3.1 Complete.\n")
