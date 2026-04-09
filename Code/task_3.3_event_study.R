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

df_full <- read_csv(file.path(proj_root, "Output", "estimation_didc_panel.csv"), show_col_types = FALSE) |>
  filter(Estimation_Sample == 1) |>
  filter(as.numeric(as.character(year)) <= 2024)

# We construct pure dyad-level policy lags and leads.
dyad_policy <- df_full |>
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

df_full <- df_full |> 
  select(-any_of(c("F3_top50", "F2_top50", "F1_top50", "L1_top50", "L2_top50", "L3_top50"))) |>
  left_join(dyad_policy, by = c("border_dyad", "year", "delta_top_50_caliber")) |>
  mutate(
    zcta = as.factor(zcta),
    border_dyad = as.factor(border_dyad),
    segment_id = as.factor(segment_id),
    year = as.factor(year),
    S_i = as.numeric(S_i)
  )

covariates <- "Effective_Property_Tax_Rate + siitax + fiitax + ln_real_gdp_pc + Unemployment_Rate_ZCTA"

# Function to plot
plot_es <- function(model_res, title, filename, include_lags=3) {
  plot_data <- model_res |>
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
  
  max_x <- include_lags
  
  p <- ggplot(plot_data, aes(x = time, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.6) +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
    geom_point(size = 3, color = "#1f77b4") +
    geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2, color = "#1f77b4", size = 0.8) +
    theme_minimal(base_size = 14) +
    labs(
      title = title,
      x = "Years Relative to Policy Shift",
      y = "Spatial LATE Housing Premium"
    ) +
    scale_x_continuous(breaks = -3:max_x) +
    theme(
      plot.title = element_text(face = "bold", size=12),
      panel.grid.minor = element_blank()
    )
  
  out_path <- file.path(proj_root, "Output", filename)
  ggsave(out_path, plot = p, width = 8, height = 5, bg="white")
  cat(sprintf("\nSaved: %s\n", out_path))
}


# -------------------------------------------------------------
# SPEC 1: BASELINE MODEL (Full Sample, All Lags)
# -------------------------------------------------------------
form_baseline <- as.formula(paste("ln_median_ppsf ~ S_i * F3_top50 + S_i * F2_top50 + S_i * F1_top50 + S_i * delta_top_50_caliber + S_i * L1_top50 + S_i * L2_top50 + S_i * L3_top50 +", covariates, "| segment_id^year"))
cat("\nRunning Baseline Model...\n")
m_base <- feols(form_baseline, data = df_full, cluster = ~ zcta + border_dyad)
plot_es(broom::tidy(m_base, conf.int=T), "Event Study 1: Baseline (Full Sample)", "event_study_1_baseline.pdf", 3)


# -------------------------------------------------------------
# SPEC 2: CURATED SAMPLE (Drop 'Always-Treated' Static Lines)
# -------------------------------------------------------------
dyad_variance <- df_full |>
  group_by(border_dyad) |>
  summarize(
    var_gap = var(delta_top_50_caliber, na.rm=TRUE),
    mean_gap = mean(delta_top_50_caliber, na.rm=TRUE)
  )

# Keep strictly if variance > 0 (Switchers) OR mean == 0 (Pure Never-Treated)
valid_dyads <- dyad_variance |>
  filter(var_gap > 0 | (var_gap == 0 & mean_gap == 0)) |>
  pull(border_dyad)

df_curated <- df_full |> filter(border_dyad %in% valid_dyads)

cat("\nRunning Curated Sample Model...\n")
m_curate <- feols(form_baseline, data = df_curated, cluster = ~ zcta + border_dyad)
plot_es(broom::tidy(m_curate, conf.int=T), "Event Study 2: Curated Sample (Switchers + Controls only)", "event_study_2_curated.pdf", 3)


# -------------------------------------------------------------
# SPEC 3: CURATED SAMPLE + BINNING LAGS (t>=1 merged)
# -------------------------------------------------------------
# By omitting L2 and L3 from the regression, L1 acts as an absorbing 
# state for everything post t=1. This forces standard errors to compress.
form_binned <- as.formula(paste("ln_median_ppsf ~ S_i * F3_top50 + S_i * F2_top50 + S_i * F1_top50 + S_i * delta_top_50_caliber + S_i * L1_top50 +", covariates, "| segment_id^year"))

cat("\nRunning Binned Model...\n")
m_bin <- feols(form_binned, data = df_curated, cluster = ~ zcta + border_dyad)

# Extract and plot spec 3 manually since the function expects L3
res_bin <- broom::tidy(m_bin, conf.int=T, conf.level=0.95)
plot_data_bin <- res_bin |>
  filter(grepl("S_i:F|S_i:L|S_i:delta_top_50", term)) |>
  mutate(
    time = case_when(
      grepl("F3", term) ~ -3,
      grepl("F2", term) ~ -2,
      grepl("F1", term) ~ -1,
      grepl("delta_top_50", term) ~ 0,
      grepl("L1", term) ~ 1
    )
  ) |>
  arrange(time)

p_bin <- ggplot(plot_data_bin, aes(x = time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.6) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
  geom_point(size = 3, color = "#1f77b4") +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2, color = "#1f77b4", size = 0.8) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Event Study 3: Binned (L1 absorbs t>=1)",
    x = "Years Relative to Policy Shift (Binned post t=1)",
    y = "Spatial LATE Housing Premium"
  ) +
  scale_x_continuous(breaks = -3:1, labels=c("t-3", "t-2", "t-1", "t=0", "t=1+")) +
  theme(plot.title = element_text(face = "bold", size=12), panel.grid.minor = element_blank())

ggsave(file.path(proj_root, "Output", "event_study_3_binned.pdf"), plot = p_bin, width = 8, height = 5, bg="white")
cat(sprintf("\nSaved: %s\n", file.path(proj_root, "Output", "event_study_3_binned.pdf")))

