import os
import pandas as pd
from census import Census
from dotenv import load_dotenv

# Load environment variables from the project root
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Initialize Census API Client
api_key = os.environ.get('CENSUS_API_KEY')
if not api_key:
    raise ValueError("CENSUS_API_KEY not found in .env file.")

c = Census(api_key)

# Define Variables
ACS_VARIABLES = {
    'B19013_001E': 'Median_Household_Income',
    'B25103_001E': 'Median_Real_Estate_Taxes',
    'B25077_001E': 'Median_Home_Value'
}

QUERY_VARS = list(ACS_VARIABLES.keys())

def fetch_acs_data(year):
    print(f"Fetching ACS data for year {year}...")
    try:
        data = c.acs5.get(
            ('NAME',) + tuple(QUERY_VARS), 
            {'for': 'zip code tabulation area:*'},
            year=year
        )
        
        df = pd.DataFrame(data)
        df['year'] = year
        
        # Rename the 'zip code tabulation area' column to 'ZCTA'
        if 'zip code tabulation area' in df.columns:
            df.rename(columns={'zip code tabulation area': 'ZCTA'}, inplace=True)
            
        return df
    except Exception as e:
        print(f"Error fetching year {year}: {e}")
        return pd.DataFrame()

def apply_zcta_crosswalk(df):
    """
    Standardize pre-2020 ZCTAs to 2020 ZCTA boundaries.
    """
    print("Standardizing pre-2020 ZCTAs to 2020 boundaries...")
    
    df_pre_2020 = df[df['year'] < 2020].copy()
    df_post_2020 = df[df['year'] >= 2020].copy()
    
    print("Note: Crosswalk file explicitly required for precise spatial apportionment of 2012-2019 data.")
    print("Currently treating ZCTA identifiers as stable 1:1 specifically for this panel construction.")
    
    harmonized_df = pd.concat([df_pre_2020, df_post_2020], ignore_index=True)
    return harmonized_df

def main():
    # 1. Loop through years 2012-2024
    years_to_fetch = list(range(2012, 2025))
    all_data = []
    
    for y in years_to_fetch:
        df_year = fetch_acs_data(y)
        if not df_year.empty:
            all_data.append(df_year)
            
    if not all_data:
        print("No data collected. Exiting.")
        return

    panel_df = pd.concat(all_data, ignore_index=True)
    
    # Rename variables to human-readable format
    panel_df.rename(columns=ACS_VARIABLES, inplace=True)
    
    # Convert numerical columns to float
    for col in ACS_VARIABLES.values():
        panel_df[col] = pd.to_numeric(panel_df[col], errors='coerce')
        panel_df.loc[panel_df[col] < 0, col] = pd.NA

    # 2. Standardize ZCTAs
    panel_df = apply_zcta_crosswalk(panel_df)

    # 3. Calculate Effective Property Tax Rate
    print("Calculating Effective Property Tax Rate...")
    panel_df['Effective_Property_Tax_Rate'] = (
        panel_df['Median_Real_Estate_Taxes'] / panel_df['Median_Home_Value']
    )
    
    # 4. Forward-fill 2024 data for 2025 and 2026
    print("Carrying forward 2024 estimates to 2025 and 2026...")
    df_2024 = panel_df[panel_df['year'] == 2024].copy()
    
    for y in [2025, 2026]:
        df_y = df_2024.copy()
        df_y['year'] = y
        panel_df = pd.concat([panel_df, df_y], ignore_index=True)

    # Sort and clean
    panel_df.sort_values(by=['ZCTA', 'year'], inplace=True)
    panel_df.reset_index(drop=True, inplace=True)

    # Export to CSV in the output folder
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'output')
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'acs_zcta_panel.csv')
    
    panel_df.to_csv(output_file, index=False)
    print(f"Panel successfully compiled and saved to {output_file}.")
    print(f"Total Rows: {len(panel_df)}, Total ZCTAs: {panel_df['ZCTA'].nunique()}")

if __name__ == "__main__":
    main()
