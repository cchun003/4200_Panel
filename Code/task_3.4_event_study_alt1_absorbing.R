library(tidyverse)
library(fixest)
library(broom)
library(ggplot2)

cat("Loading estimation panel...\n")
base_dir <- getwd()
proj_root <- base_dir

df_full <- read_csv(file.path(proj_root, "Output", "estimation_didc_panel.csv"), show_col_types = FALSE) |>
  filter(Estimation_Sample == 1) |>
  filter(as.numeric(as.character(year)) <= 2024)

# -------------------------------------------------------------
# ALTERNATIVE 1: ABSORBING STATE TRANSFORMATION
# -------------------------------------------------------------
# We identify the FIRST year the gap changes from its baseline (t=1).
# We then artificially freeze that new gap for all subsequent years, acting as a permanent shock.

dyad_policy <- df_full |>
  select(border_dyad, year, delta_top_50_caliber) |>
  distinct() |>
  arrange(border_dyad, year) |>
  group_by(border_dyad) |>
  mutate(
    shock_indicator = cumsum(abs(diff(c(delta_top_50_caliber[1], delta_top_50_caliber))) > 0),
    absorbing_delta = if_else(shock_indicator > 0, delta_top_50_caliber[min(which(shock_indicator > 0))], delta_top_50_caliber[1]),
    
    # Generate leads and lags off the absorbing delta
    F3_top50 = lead(absorbing_delta, 3),
    F2_top50 = lead(absorbing_delta, 2),
    F1_top50 = lead(absorbing_delta, 1),
    L1_top50 = lag(absorbing_delta, 1),
    L2_top50 = lag(absorbing_delta, 2),
    L3_top50 = lag(absorbing_delta, 3)
  ) |>
  ungroup()

# Retain only standard regression frame
df_model <- df_full |> 
  select(-any_of(c("delta_top_50_caliber"))) |>
  left_join(dyad_policy, by = c("border_dyad", "year")) |>
  mutate(
    zcta = as.factor(zcta),
    border_dyad = as.factor(border_dyad),
    segment_id = as.factor(segment_id),
    year = as.factor(year),
    S_i = as.numeric(S_i)
  )

covariates <- "Effective_Property_Tax_Rate + siitax + fiitax + ln_real_gdp_pc + Unemployment_Rate_ZCTA"
form_binned_acad <- as.formula(paste("ln_median_ppsf_acad ~ S_i * F3_top50 + S_i * F2_top50 + S_i * F1_top50 + S_i * absorbing_delta + S_i * L1_top50 +", covariates, "| segment_id^year"))

cat("\nRunning Absorbing State Binned Model (Academic Calendar)...\n")
m_bin_acad <- feols(form_binned_acad, data = df_model, cluster = ~ zcta + border_dyad)

res_bin_acad <- broom::tidy(m_bin_acad, conf.int=T, conf.level=0.95)
plot_data <- res_bin_acad |>
  filter(grepl("S_i:F|S_i:L|S_i:absorbing_delta", term)) |>
  mutate(
    time = case_when(
      grepl("F3", term) ~ -3,
      grepl("F2", term) ~ -2,
      grepl("F1", term) ~ -1,
      grepl("absorbing_delta", term) ~ 0,
      grepl("L1", term) ~ 1
    )
  ) |>
  arrange(time)

p <- ggplot(plot_data, aes(x = time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.6) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
  geom_point(size = 3, color = "#d62728") +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2, color = "#d62728", linewidth = 0.8) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Alt 1: Absorbing State Model",
    subtitle = "First Reputational Shock permanently overrides transient slippage.",
    x = "Years Relative to Policy Shift (Binned post t=1)",
    y = "Spatial LATE Housing Premium"
  ) +
  scale_x_continuous(breaks = -3:1, labels=c("t-3", "t-2", "t-1", "t=0", "t=1+")) +
  theme(plot.title = element_text(face = "bold", size=14), panel.grid.minor = element_blank())

ggsave(file.path(proj_root, "Output", "event_study_alt1_absorbing.pdf"), plot = p, width = 8, height = 5, bg="white")
cat(sprintf("Saved: %s\n", "Output/event_study_alt1_absorbing.pdf"))
