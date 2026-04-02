import pandas as pd
import numpy as np
import os

# 1. Process Redfin Housing Data
# Path to the zip code market tracker file
input_path = '/Users/chenchun/Downloads/zip_code_market_tracker.tsv000.gz'
output_path = 'Output/redfin_zip_annual.csv'

print(f"Loading Redfin data from {input_path}...")

# Use chunking to handle large dataset efficiently (Redfin TSVs can be several GBs)
chunks = []
try:
    # Expanded column list based on potential interest for econometric panel
    # We include prices, price per sqft, time on market (DOM), and inventory/sales counts
    cols_to_use = [
        'PERIOD_BEGIN', 'REGION_TYPE', 'REGION', 
        'MEDIAN_SALE_PRICE', 'MEDIAN_LIST_PRICE', 'MEDIAN_PPSF',
        'HOMES_SOLD', 'NEW_LISTINGS', 'INVENTORY', 
        'MEDIAN_DOM', 'AVG_SALE_TO_LIST', 'SOLD_ABOVE_LIST'
    ]
    
    reader = pd.read_csv(input_path, 
                         compression='gzip', 
                         sep='\t', 
                         usecols=cols_to_use,
                         chunksize=100000)

    for i, chunk in enumerate(reader):
        # Filter for Zip Code level data
        z_chunk = chunk[chunk['REGION_TYPE'] == 'zip code'].copy()
        
        if not z_chunk.empty:
            # Extract Year from PERIOD_BEGIN
            z_chunk['year'] = pd.to_datetime(z_chunk['PERIOD_BEGIN']).dt.year
            
            # Clean zip code string (remove 'Zip Code: ' if present)
            z_chunk['zip_code'] = z_chunk['REGION'].str.extract('(\d{5})')
            
            # Remove original columns no longer needed
            z_chunk = z_chunk.drop(columns=['PERIOD_BEGIN', 'REGION_TYPE', 'REGION'])
            
            chunks.append(z_chunk)
            
        if (i + 1) % 10 == 0:
            print(f"Processed { (i + 1) * 100000 } rows...")

    # Combine all chunks
    print("Combining chunks and aggregating to annual levels...")
    df_redfin = pd.concat(chunks, ignore_index=True)

    # Group by zip code and year to get annual representative values
    # For price variables/ratios/durations, we take the MEDIAN across months
    # For count variables (Sales, Listings), we take the SUM to get annual totals
    
    # Identify count columns to sum vs. median columns
    count_cols = ['HOMES_SOLD', 'NEW_LISTINGS']
    median_cols = [c for c in df_redfin.columns if c not in ['zip_code', 'year'] + count_cols]

    # Aggregate using different functions
    agg_dict = {col: 'sum' for col in count_cols}
    agg_dict.update({col: 'median' for col in median_cols})

    df_annual = df_redfin.groupby(['zip_code', 'year']).agg(agg_dict).reset_index()

    # Save to Output folder
    if not os.path.exists('Output'):
        os.makedirs('Output')
        
    df_annual.to_csv(output_path, index=False)
    print(f"Success! Redfin annual zip code panel saved to {output_path}")
    print(f"Total entries: {len(df_annual)}")
    print("Final variables included: " + ", ".join(df_annual.columns))

except FileNotFoundError:
    print(f"Error: The file {input_path} was not found. Please ensure the path is correct.")
except Exception as e:
    import traceback
    print(f"An error occurred: {str(e)}")
    traceback.print_exc()