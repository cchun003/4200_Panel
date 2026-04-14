import pandas as pd
import numpy as np

# Load the file
input_path = "Output/estimation_didc_panel.csv"
df = pd.read_csv(input_path)

# Filter for estimation sample
estimation_df = df[df["Estimation_Sample"] == 1]

# Stats
total_obs = len(df)
retained_obs = len(estimation_df)
avg_h_star = estimation_df["h_star"].mean()
min_h_star = estimation_df["h_star"].min()
max_h_star = estimation_df["h_star"].max()
std_h_star = estimation_df["h_star"].std()

# Geographic distribution (across border segments)
num_segments = df["segment_id"].nunique()

print(f"Total Observations: {total_obs:,}")
print(f"Estimation Sample Size: {retained_obs:,} ({retained_obs/total_obs:.2%})")
print(f"Average Bandwidth (h*): {avg_h_star:.2f} km")
print(f"Bandwidth Range: {min_h_star:.2f} - {max_h_star:.2f} km")
print(f"Bandwidth Std Dev: {std_h_star:.2f} km")
print(f"Number of Border Segments: {num_segments:,}")
