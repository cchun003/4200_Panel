import pandas as pd
import numpy as np

# 1. Load Caliber and Tuition Panels
df_caliber = pd.read_csv('Output/us_news_caliber_panel.csv')
df_tuition = pd.read_csv('Output/ipeds_tuition_panel.csv')

# 2. Process Redfin Housing Data
# Read the compressed.tsv000.gz file directly
# Use chunking if memory limits are an issue, but standard pandas handles ~2-3GB fine
df_redfin = pd.read_csv('neighborhood_market_tracker.tsv000.gz', 
                        compression='gzip', 
                        sep='\t', 
                        usecols=['period_begin', 'region_type', 'region', 'state', 'median_sale_price'])

# Filter for Zip Code level data
df_redfin_zip = df_redfin[df_redfin['region_type'] == 'zip code'].copy()
# Convert dates to extract the year for merging
df_redfin_zip['Year'] = pd.to_datetime(df_redfin_zip['period_begin']).dt.year
# Group to get annual median sale price per zip code
df_redfin_annual = df_redfin_zip.groupby(['region', 'Year'])['median_sale_price'].median().reset_index()

# 3. Load IPEDS Tuition Data (from R script)
df_tuition = pd.read_csv('output/ipeds_tuition_panel.csv')

# 4. Compile the Final Master Panel
# Merge Caliber and Tuition data to create a State-Year master lookup
df_state_policy = pd.merge(df_tuition, df_caliber, how='left', left_on=['stabbr', 'year'], right_on=['State', 'Year'])
df_state_policy['top_150_count'] = df_state_policy['top_150_count'].fillna(0) # 0 if no top universities

# Generate Delta variables (Policy Gaps) based on Directional Normalization (Index vs Control)
# Assuming you have a border dyad mapping dataframe: df_borders = ['dyad_id', 'index_state', 'control_state']
# You would merge the df_state_policy onto df_borders twice (once for index, once for control)

# Example calculation for a merged dyad row:
# df_dyad = df_dyad['weighted_in_state_index'] - df_dyad['weighted_in_state_control']
# df_dyad['delta_Q'] = df_dyad['top_150_count_index'] - df_dyad['top_150_count_control']

# Finally, merge your Redfin housing data with your ZCTA-to-Segment spatial mapping (from Task 2.2) 
# and join it to the state-dyad policy variables.