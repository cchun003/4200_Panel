import pandas as pd
import numpy as np
import os
import warnings

warnings.filterwarnings('ignore')

# ==========================================
# Configuration and Path Setup
# ==========================================
# Resolve paths relative to this script's location for maximum durability
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(BASE_DIR, '..', 'Output')

print("Loading individual panel components from: ", os.path.abspath(OUTPUT_DIR))

# 1. Spatial Boundary Panel
# This provides the ZCTA-to-Segment Mapping and Signed Distances (S_i, d_ic)
spatial_df = pd.read_csv(os.path.join(OUTPUT_DIR, "zcta_distance_segment_panel.csv"), dtype={'zcta': str})

# 2. State-Level Policy Panels
ipeds_df = pd.read_csv(os.path.join(OUTPUT_DIR, "ipeds_tuition_panel.csv"))
usnews_df = pd.read_csv(os.path.join(OUTPUT_DIR, "us_news_caliber_panel.csv"))

# 3. ZCTA-Level Controls and Outcomes
# Note: Using explicit dtypes for ZCTA IDs to prevent precision loss on leading zeros
acs_df = pd.read_csv(os.path.join(OUTPUT_DIR, "acs_zcta_panel.csv"), dtype={'ZCTA': str})
macro_df = pd.read_csv(os.path.join(OUTPUT_DIR, "macro_zcta_panel.csv"), dtype={'ZCTA': str})
taxsim_df = pd.read_csv(os.path.join(OUTPUT_DIR, "taxsim_zcta_panel.csv"), dtype={'ZCTA': str})
redfin_df = pd.read_csv(os.path.join(OUTPUT_DIR, "redfin_zip_annual.csv"), dtype={'zip_code': str})

# Standardize joining keys to lowercase 'zcta' across all source DataFrames
for df in [acs_df, macro_df, taxsim_df]:
    df.rename(columns={'ZCTA': 'zcta'}, inplace=True)
redfin_df.rename(columns={'zip_code': 'zcta'}, inplace=True)

# ==========================================
# Step 1: Compute Dyadic Policy Gaps (State A - State B)
# ==========================================
# The DiDC model is identifying: Y = Beta * (S_i * (Policy_A - Policy_B))
print("Calculating time-varying dyadic policy gaps...")

# Merge IPEDS and US News into a single state-year policy lookup
state_policy_df = pd.merge(ipeds_df, usnews_df, on=['stabbr', 'year'], how='outer')

# Determine temporal coverage (2012-2026 panel environment)
years = sorted(state_policy_df['year'].unique())
dyads = spatial_df['border_dyad'].unique()

dyad_records = []
for dyad in dyads:
    # Dyad format is usually 'StateA-StateB'
    state_a, state_b = dyad.split('-')
    for year in years:
        # Extract specific Year-State vectors
        pol_a = state_policy_df[(state_policy_df['stabbr'] == state_a) & (state_policy_df['year'] == year)]
        pol_b = state_policy_df[(state_policy_df['stabbr'] == state_b) & (state_policy_df['year'] == year)]
        
        if not pol_a.empty and not pol_b.empty:
            pol_a = pol_a.iloc[0]
            pol_b = pol_b.iloc[0]
            
            # Compute Deltas strictly as (State A - State B)
            # State A corresponds to S_i = 1 (the 'treated' side in the alphabetic pair)
            record = {
                'border_dyad': dyad,
                'year': year,
                'delta_in_state_tuition': pol_a['weighted_in_state'] - pol_b['weighted_in_state'],
                'delta_out_of_state_tuition': pol_a['weighted_out_of_state'] - pol_b['weighted_out_of_state'],
            }
            
            # Dynamically calculate all caliber deltas (top_10, top_20, ..., top_150)
            caliber_cols = [c for c in usnews_df.columns if c.startswith('top_')]
            for col in caliber_cols:
                record[f'delta_{col}_caliber'] = pol_a[col] - pol_b[col]
                
            dyad_records.append(record)

dyad_policy_panel = pd.DataFrame(dyad_records)

# ==========================================
# Step 2: Consolidate ZCTA-Level Time Series
# ==========================================
print("Consolidating ZCTA controls and housing outcomes...")

# Merge ACS base with revised Macro (Real GDP per capita) and Taxsim liabilities
zcta_ts = pd.merge(acs_df, macro_df[['zcta', 'year', 'Real_GDP_per_capita_ZCTA', 'Unemployment_Rate_ZCTA']], 
                   on=['zcta', 'year'], how='left')

zcta_ts = pd.merge(zcta_ts, taxsim_df[['zcta', 'year', 'fiitax', 'siitax']], 
                   on=['zcta', 'year'], how='left')

# Merge Redfin Housing Outcomes (Sale Price, PPSF, DOM, Inventory)
zcta_ts = pd.merge(zcta_ts, redfin_df, on=['zcta', 'year'], how='left')

# Drop redundant identifier columns from sub-merges
cols_to_drop = [c for c in zcta_ts.columns if c in ['NAME', 'state', 'stab'] and c != 'zcta']
zcta_ts.drop(columns=cols_to_drop, errors='ignore', inplace=True)

# ==========================================
# Step 3: Assemble the Master Spatial Panel
# ==========================================
print("Assembling the master DiDC spatial panel...")

# Inner join: We only keep ZCTAs that appear in both the spatial segmentation and the time-series
# Note: ZCTAs near tri-state corners are duplicated here for each relevant dyad-segment.
master_df = pd.merge(spatial_df, zcta_ts, on='zcta', how='inner')

# Attach the dyadic policy gaps calculated in Step 1
master_df = pd.merge(master_df, dyad_policy_panel, on=['border_dyad', 'year'], how='inner')

# Calculate the core DiDC interaction terms natively
# Interaction = Treatment_Indicator * (StateA_Policy - StateB_Policy)
master_df['interaction_tuition'] = master_df['S_i'] * master_df['delta_in_state_tuition']
master_df['interaction_caliber'] = master_df['S_i'] * master_df['delta_top_100_caliber']

# Log-transforms for econometric analysis
# Handling potential NULLs/Zeros in housing prices and GDP pc
master_df['ln_median_ppsf'] = np.log(master_df['MEDIAN_PPSF'].replace({0: np.nan}))
master_df['ln_median_sale_price'] = np.log(master_df['MEDIAN_SALE_PRICE'].replace({0: np.nan}))
master_df['ln_median_ppsf_acad'] = np.log(master_df['MEDIAN_PPSF_acad'].replace({0: np.nan}))
master_df['ln_median_sale_price_acad'] = np.log(master_df['MEDIAN_SALE_PRICE_acad'].replace({0: np.nan}))
master_df['ln_real_gdp_pc'] = np.log(master_df['Real_GDP_per_capita_ZCTA'] + 1)

# Ensure clean panel structure (hierarchical sorting)
master_df.sort_values(by=['segment_id', 'zcta', 'year'], inplace=True)

# ==========================================
# Step 4: Export Resulting Master Panel
# ==========================================
output_path = os.path.join(OUTPUT_DIR, "master_didc_panel.csv")
master_df.to_csv(output_path, index=False)

print("-" * 30)
print(f"SUCCESS: Flat master panel integrated and exported to: {os.path.basename(output_path)}")
print(f"Observation Count: {len(master_df)}")
print(f"Time Range: {master_df['year'].min()} - {master_df['year'].max()}")
print(f"Core Variables Included: {', '.join(master_df.columns[:10])} ...")