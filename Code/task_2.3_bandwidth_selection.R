# ==============================================================================
# Task 2.3: Data-Driven MSE-Optimal Bandwidth Selection
# ==============================================================================
# Dependency: install.packages(c("tidyverse", "rdrobust"))
library(tidyverse)
library(rdrobust)

# Configuration
output_dir <- "Output"
input_file <- file.path(output_dir, "master_didc_panel.csv")
output_file <- file.path(output_dir, "estimation_didc_panel.csv")
baseline_year <- 2012
min_obs_per_side <- 15 # Minimum threshold to attempt segment-level rdrobust

cat("Loading master spatial panel...\n")
master_df <- read_csv(input_file, show_col_types = FALSE)

# Generate target outcome: Natural log of Median Home Value
master_df <- master_df |>
  mutate(ln_median_home_value = log(Median_Home_Value))

# ==============================================================================
# Step 1: Isolate Baseline Year for Optimal h* Calculation
# ==============================================================================
cat(sprintf("Filtering data to baseline year (%d)...\n", baseline_year))

baseline_df <- master_df |>
  filter(year == baseline_year) |>
  filter(!is.na(ln_median_home_value) & !is.na(d_ic))

# Calculate a global bandwidth as an absolute last-resort fallback
cat("Calculating global optimal bandwidth as failsafe...\n")
global_rd <- tryCatch(
  {
    rdbwselect(
      y = baseline_df$ln_median_home_value,
      x = baseline_df$d_ic,
      c = 0, p = 1, kernel = "triangular", masspoints = "adjust"
    )
  },
  error = function(e) {
    NULL
  }
)

global_h_star <- tryCatch(
  {
    if (!is.null(global_rd) && is.matrix(global_rd$bws)) {
      global_rd$bws[1, 1]
    } else {
      50
    }
  },
  error = function(e) 50
)
cat(sprintf("Global fallback bandwidth: %.2f km\n", global_h_star))

# ==============================================================================
# Step 2: Iterative Bandwidth Estimation (Segment with Dyad Fallback)
# ==============================================================================
cat("Iterating through border dyads and segments to calculate local h*...\n")

segment_bws <- list()
dyads <- unique(baseline_df$border_dyad)

for (dyad_name in dyads) {
  dyad_data <- baseline_df |> filter(border_dyad == dyad_name)

  # Attempt dyad-level MSE bandwidth as the primary fallback
  dyad_h_star <- tryCatch(
    {
      rd_out <- rdbwselect(
        y = dyad_data$ln_median_home_value,
        x = dyad_data$d_ic,
        c = 0, p = 1, kernel = "triangular", masspoints = "adjust"
      )
      rd_out$bws[1, "h"]
    },
    warning = function(w) {
      global_h_star
    },
    error = function(e) {
      global_h_star
    }
  )

  # Process each segment within the dyad
  segments <- unique(dyad_data$segment_id)

  for (seg_name in segments) {
    seg_data <- dyad_data |> filter(segment_id == seg_name)

    # Check for sparse bins (Rule 1: Fallback to Dyad)
    n_left <- sum(seg_data$d_ic < 0)
    n_right <- sum(seg_data$d_ic >= 0)

    if (n_left >= min_obs_per_side && n_right >= min_obs_per_side) {
      # Attempt highly localized segment bandwidth
      seg_h_star <- tryCatch(
        {
          rd_out <- rdbwselect(
            y = seg_data$ln_median_home_value,
            x = seg_data$d_ic,
            c = 0, p = 1, kernel = "triangular", masspoints = "adjust"
          )
          rd_out$bws[1, "h"]
        },
        warning = function(w) {
          dyad_h_star
        },
        error = function(e) {
          dyad_h_star
        }
      )
    } else {
      # Sparse segment -> Apply parent dyad bandwidth
      seg_h_star <- dyad_h_star
    }

    # Store result
    segment_bws[[length(segment_bws) + 1]] <- data.frame(
      segment_id = seg_name,
      h_star = seg_h_star
    )
  }
}

# Compile lookup table
bw_lookup <- bind_rows(segment_bws)

# ==============================================================================
# Step 3: Flag Estimation Sample and Export
# ==============================================================================
cat("Applying bandwidths to the full 2012-2026 panel...\n")

final_panel <- master_df |>
  left_join(bw_lookup, by = "segment_id") |>
  mutate(
    # Handle isolated segments that didn't exist in the 2012 slice
    h_star = ifelse(is.na(h_star), global_h_star, h_star),

    # Create the strict RD Estimation Sample flag
    Estimation_Sample = ifelse(abs(d_ic) <= h_star, 1, 0)
  )

# Calculate retention stats
total_obs <- nrow(final_panel)
retained_obs <- sum(final_panel$Estimation_Sample == 1, na.rm = TRUE)
cat(sprintf(
  "\nSummary:\nTotal observations: %d\nInside bandwidth: %d (%.1f%%)\n",
  total_obs, retained_obs, (retained_obs / total_obs) * 100
))

write_csv(final_panel, output_file)
cat(sprintf("\nTask 2.3 complete. Panel saved: %s\n", output_file))
