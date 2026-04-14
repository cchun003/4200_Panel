# ==============================================================================
# Task 0.4: Trends in State-Level University Prestige
# ==============================================================================
library(tidyverse)
library(ggplot2)

# Load data
csv_path <- "Output/us_news_caliber_panel.csv"
if (!file.exists(csv_path)) {
  stop("Input file not found: Output/us_news_caliber_panel.csv")
}

df <- read_csv(csv_path, show_col_types = FALSE)

# Reshape for multi-panel plotting
df_long <- df %>%
  pivot_longer(cols = starts_with("top_"), names_to = "tier", values_to = "count") %>%
  filter(tier %in% c("top_40", "top_50", "top_60")) %>%
  mutate(tier_label = case_when(
    tier == "top_40" ~ "Top 40 Universities",
    tier == "top_50" ~ "Top 50 Universities",
    tier == "top_60" ~ "Top 60 Universities"
  ))

# Filter for states that ever held a Top 60 slot (to include relevant variation)
df_filtered <- df_long %>%
  group_by(stabbr, tier) %>%
  filter(max(count) > 0) %>%
  ungroup() %>%
  arrange(stabbr, year)

# Create the faceted plot with dodging to stagger overlapping lines
p <- ggplot(df_filtered, aes(x = year, y = count, color = stabbr, group = stabbr)) +
  geom_line(linewidth = 0.8, alpha = 0.7, position = position_dodge(width = 0.5)) +
  geom_point(size = 1.5, position = position_dodge(width = 0.5)) +
  facet_wrap(~tier_label, ncol = 1, scales = "free_y") +
  theme_minimal(base_size = 14) +
  scale_x_continuous(breaks = seq(2012, 2024, 2)) +
  labs(
    title = "Trends in State-Level University Prestige",
    subtitle = "Comparing Top 40, Top 50, and Top 60 tiers (2012-2024)",
    x = "Year",
    y = "Number of Public Universities",
    color = "State"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    strip.text = element_text(face = "bold", size = 12),
    panel.grid.minor = element_blank(),
    legend.position = "right",
    legend.key.size = unit(0.5, "cm")
  )

# Save as PDF
out_path <- "Output/prestige_state_trends.pdf"
ggsave(out_path, plot = p, width = 11, height = 10, device = "pdf")

cat(sprintf("Granular prestige trends plot saved to: %s\n", out_path))
