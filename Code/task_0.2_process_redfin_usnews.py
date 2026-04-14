import pandas as pd
import numpy as np
import os

# 1. Process Redfin Housing Data
input_path = '/Users/chenchun/Downloads/zip_code_market_tracker.tsv000.gz'
output_path = 'Output/redfin_zip_annual.csv'

print(f"Loading Redfin data from {input_path}...")

chunks_nat = []
chunks_acad = []

try:
    cols_to_use = [
        'PERIOD_BEGIN', 'REGION_TYPE', 'REGION', 
        'MEDIAN_SALE_PRICE', 'MEDIAN_LIST_PRICE', 'MEDIAN_PPSF',
        'HOMES_SOLD', 'NEW_LISTINGS', 'INVENTORY', 
        'MEDIAN_DOM', 'AVG_SALE_TO_LIST', 'SOLD_ABOVE_LIST'
    ]
    
    reader = pd.read_csv(input_path, compression='gzip', sep='\t', usecols=cols_to_use, chunksize=100000)

    for i, chunk in enumerate(reader):
        z_chunk = chunk[chunk['REGION_TYPE'] == 'zip code'].copy()
        
        if not z_chunk.empty:
            dt_col = pd.to_datetime(z_chunk['PERIOD_BEGIN'])
            z_chunk['year'] = dt_col.dt.year
            z_chunk['month'] = dt_col.dt.month
            
            # Academic Year logic: Sept(9) to Dec(12) belongs to year+1. Jan(1) to Aug(8) belongs to year.
            z_chunk['academic_year'] = np.where(z_chunk['month'] >= 9, z_chunk['year'] + 1, z_chunk['year'])
            
            z_chunk['zip_code'] = z_chunk['REGION'].str.extract(r'(\d{5})')
            z_chunk = z_chunk.drop(columns=['PERIOD_BEGIN', 'REGION_TYPE', 'REGION', 'month'])
            
            # For memory efficiency, keep standard variables
            chunks_nat.append(z_chunk.drop(columns=['academic_year']))
            # For academic variables, map them to academic_year
            z_chunk_acad = z_chunk.drop(columns=['year']).rename(columns={'academic_year': 'year'})
            chunks_acad.append(z_chunk_acad)
            
        if (i + 1) % 10 == 0:
            print(f"Processed { (i + 1) * 100000 } rows...")

    print("Combining chunks and aggregating to explicit dual-calendar arrays...")
    df_nat = pd.concat(chunks_nat, ignore_index=True)
    df_acad = pd.concat(chunks_acad, ignore_index=True)

    count_cols = ['HOMES_SOLD', 'NEW_LISTINGS']
    median_cols = [c for c in df_nat.columns if c not in ['zip_code', 'year'] + count_cols]

    agg_dict = {col: 'sum' for col in count_cols}
    agg_dict.update({col: 'median' for col in median_cols})

    print("Aggregating Natural Years (Jan-Dec)...")
    df_annual = df_nat.groupby(['zip_code', 'year']).agg(agg_dict).reset_index()
    
    print("Aggregating Academic Years (Sept-Aug)...")
    df_annual_acad = df_acad.groupby(['zip_code', 'year']).agg(agg_dict).reset_index()
    
    # Rename academic columns properly
    rename_mapping = {col: f"{col}_acad" for col in count_cols + median_cols}
    df_annual_acad.rename(columns=rename_mapping, inplace=True)

    print("Merging Spatial Matrices...")
    df_final = pd.merge(df_annual, df_annual_acad, on=['zip_code', 'year'], how='outer')

    if not os.path.exists('Output'):
        os.makedirs('Output')
        
    df_final.to_csv(output_path, index=False)
    print(f"Success! Redfin dual-calendar zip code panel saved to {output_path}")
    print(f"Total entries: {len(df_final)}")

except Exception as e:
    import traceback
    print(f"An error occurred: {str(e)}")
    traceback.print_exc()