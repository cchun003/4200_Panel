library(tidyverse)
library(fixest)
library(broom)
library(ggplot2)

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

df <- read_csv(file.path(proj_root, "Output", "estimation_didc_panel.csv"), show_col_types = FALSE) |>
  filter(Estimation_Sample == 1) |>
  filter(as.numeric(as.character(year)) <= 2024)

# We construct pure dyad-level policy lags and leads.
dyad_policy <- df |>
  select(border_dyad, year, delta_top_50_caliber) |>
  distinct() |>
  arrange(border_dyad, year) |>
  group_by(border_dyad) |>
  mutate(
    F3_top50 = lead(delta_top_50_caliber, 3),
    F2_top50 = lead(delta_top_50_caliber, 2),
    F1_top50 = lead(delta_top_50_caliber, 1),
    L1_top50 = lag(delta_top_50_caliber, 1),
    L2_top50 = lag(delta_top_50_caliber, 2),
    L3_top50 = lag(delta_top_50_caliber, 3)
  ) |>
  ungroup()

df <- df |> 
  select(-any_of(c("F3_top50", "F2_top50", "F1_top50", "L1_top50", "L2_top50", "L3_top50"))) |>
  left_join(dyad_policy, by = c("border_dyad", "year", "delta_top_50_caliber")) |>
  mutate(
    zcta = as.factor(zcta),
    border_dyad = as.factor(border_dyad),
    segment_id = as.factor(segment_id),
    year = as.factor(year),
    S_i = as.numeric(S_i)
  )

# The FEs and Time-Varying Controls
covariates <- "Effective_Property_Tax_Rate + siitax + fiitax + ln_real_gdp_pc + Unemployment_Rate_ZCTA"

# Distributed lag interaction formulation
form <- as.formula(paste(
  "ln_median_ppsf ~",
  "S_i * F3_top50 + S_i * F2_top50 + S_i * F1_top50 +",
  "S_i * delta_top_50_caliber +",
  "S_i * L1_top50 + S_i * L2_top50 + S_i * L3_top50 +",
  covariates,
  "| segment_id^year"
))

cat("\nEstimating Distributed Lag Model (Event Study) with Two-Way Clustering...\n")
model <- feols(form, data = df, cluster = ~ zcta + border_dyad)

# Extract Coefficients for Plotting
res <- broom::tidy(model, conf.int = TRUE, conf.level = 0.95)

# Filter out controls, keep only our interaction parameters
plot_data <- res |>
  filter(grepl("S_i:F|S_i:L|S_i:delta_top_50", term)) |>
  mutate(
    time = case_when(
      grepl("F3", term) ~ -3,
      grepl("F2", term) ~ -2,
      grepl("F1", term) ~ -1,
      grepl("delta_top_50", term) ~ 0,
      grepl("L1", term) ~ 1,
      grepl("L2", term) ~ 2,
      grepl("L3", term) ~ 3
    )
  ) |>
  arrange(time)

cat("\nEvent Study Coefficients:\n")
print(plot_data |> select(time, estimate, conf.low, conf.high, p.value))

# Generate the plot
p <- ggplot(plot_data, aes(x = time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.6) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
  geom_point(size = 3, color = "#1f77b4") +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2, color = "#1f77b4", size = 0.8) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Event Study: Top 50 Prestige Capitalization",
    subtitle = "Parallel trends test using distributed spatial leads (F1-F3) and lags (L1-L3)",
    x = "Years Relative to Policy Shift",
    y = "Spatial LATE Housing Premium (%)"
  ) +
  scale_x_continuous(breaks = -3:3, labels = c("t-3", "t-2", "t-1", "t", "t+1", "t+2", "t+3")) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

# Save
out_path <- file.path(proj_root, "Output", "event_study_caliber.pdf")
ggsave(out_path, plot = p, width = 8, height = 5, bg="white")
cat(sprintf("\nPlot saved successfully to: %s\n", out_path))
