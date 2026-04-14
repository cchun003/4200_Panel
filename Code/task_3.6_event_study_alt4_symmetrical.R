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
# ALTERNATIVE 4: SYMMETRICAL ENTRY VS EXIT PARTITIONING
# -------------------------------------------------------------
# We partition the panel dyads into pure 'Prestige Gainers' vs pure 'Prestige Losers'.
# A gainer goes 0 -> 1. A loser goes 1 -> 0.

dyad_type <- df_full |>
  arrange(border_dyad, year) |>
  group_by(border_dyad) |>
  summarize(
    baseline = first(delta_top_50_caliber),
    has_gain = any(abs(delta_top_50_caliber) > abs(baseline)),
    has_loss = any(abs(delta_top_50_caliber) < abs(baseline))
  )

gain_dyads <- dyad_type |> filter(has_gain & !has_loss) |> pull(border_dyad)
loss_dyads <- dyad_type |> filter(!has_gain & has_loss) |> pull(border_dyad)

cat(sprintf("Identified %d strict Gain Dyads and %d strict Loss Dyads.\n", length(gain_dyads), length(loss_dyads)))

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

df_model <- df_full |> 
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
form_binned_acad <- as.formula(paste("ln_median_ppsf_acad ~ S_i * F3_top50 + S_i * F2_top50 + S_i * F1_top50 + S_i * delta_top_50_caliber + S_i * L1_top50 +", covariates, "| segment_id^year"))

# Plotting Helper Function
generate_binned_plot <- function(data_subset, title_text, output_file, color_hex) {
  m_bin <- feols(form_binned_acad, data = data_subset, cluster = ~ zcta + border_dyad)
  res_bin <- broom::tidy(m_bin, conf.int=T, conf.level=0.95)
  plot_data <- res_bin |>
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
  
  p <- ggplot(plot_data, aes(x = time, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.6) +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
    geom_point(size = 3, color = color_hex) +
    geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2, color = color_hex, linewidth = 0.8) +
    theme_minimal(base_size = 14) +
    labs(
      title = title_text,
      subtitle = "Binned post-t=1 isolated vector.",
      x = "Years Relative to Policy Shift (Binned post t=1)",
      y = "Spatial LATE Housing Premium"
    ) +
    scale_x_continuous(breaks = -3:1, labels=c("t-3", "t-2", "t-1", "t=0", "t=1+")) +
    theme(plot.title = element_text(face = "bold", size=14), panel.grid.minor = element_blank())
  
  ggsave(file.path(proj_root, "Output", output_file), plot = p, width = 8, height = 5, bg="white")
  cat(sprintf("Saved: %s\n", paste0("Output/", output_file)))
}

cat("\nEstimating Entry Models...\n")
generate_binned_plot(df_model |> filter(border_dyad %in% gain_dyads), 
                     "Alt 4: Prestige Entry (0 to 1 Gain Curve)", 
                     "event_study_alt4_entry.pdf", 
                     "#9467bd")

cat("\nEstimating Exit Models...\n")
generate_binned_plot(df_model |> filter(border_dyad %in% loss_dyads), 
                     "Alt 4: Prestige Exit (1 to 0 Loss Curve)", 
                     "event_study_alt4_exit.pdf", 
                     "#e377c2")
