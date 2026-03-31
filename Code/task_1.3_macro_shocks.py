import os
import requests
import pandas as pd
import json
import time
from dotenv import load_dotenv

# Load environment variables
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

BEA_API_KEY = os.environ.get("BEA_API_KEY")
BLS_API_KEY = os.environ.get("BLS_API_KEY")

if not BEA_API_KEY or not BLS_API_KEY:
    raise ValueError("Missing BEA_API_KEY or BLS_API_KEY in .env file.")

YEARS = [str(y) for y in range(2012, 2025)] # 2012 to 2024
YEAR_STR = ",".join(YEARS)

def fetch_bea_gdp():
    """
    Fetch Real GDP by County (CAGDP9) from BEA API.
    """
    print("Fetching Real GDP (CAGDP9) from BEA API...")
    url = (
        f"https://apps.bea.gov/api/data?&UserID={BEA_API_KEY}"
        f"&method=GetData&datasetname=Regional&TableName=CAGDP9"
        f"&LineCode=1&GeoFips=COUNTY&Year={YEAR_STR}&ResultFormat=JSON"
    )
    
    response = requests.get(url)
    if response.status_code != 200:
        raise ConnectionError(f"BEA API returned status code {response.status_code}")
        
    data = response.json()
    try:
        results = data['BEAAPI']['Results']['Data']
    except KeyError:
        print("BEA API Error or No Data:", data)
        return pd.DataFrame()
        
    df = pd.DataFrame(results)
    
    # Clean the BEA dataframe
    df = df[['GeoFips', 'TimePeriod', 'DataValue']].copy()
    df.rename(columns={
        'GeoFips': 'FIPS', 
        'TimePeriod': 'year', 
        'DataValue': 'Real_GDP_County'
    }, inplace=True)
    
    # Filter out state-wide summaries (which end in 000) or regions
    df = df[df['FIPS'].str.len() == 5]
    df = df[~df['FIPS'].str.endswith('000')]
    
    # Convert types
    df['year'] = df['year'].astype(int)
    # BEA commas
    df['Real_GDP_County'] = pd.to_numeric(df['Real_GDP_County'].astype(str).str.replace(',', ''), errors='coerce')
    
    return df

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

def fetch_bls_unemployment(fips_list):
    """
    Batch query the BLS API for Local Area Unemployment Statistics (LAUS).
    Series format: LAUCN + FIPS + 0000000003 (Unemployment Rate)
    BLS limits to 50 series per request.
    """
    print(f"Fetching BLS LAUS Data for {len(fips_list)} counties...")
    
    # Configure resilient connection pool to handle timeouts
    session = requests.Session()
    
    # Load optional proxy from .env to bypass BLS geo-firewall
    bls_proxy = os.environ.get("BLS_PROXY")
    if bls_proxy:
        print(f"  [Network] Routing BLS traffic securely through local proxy: {bls_proxy}")
        session.proxies.update({'http': bls_proxy, 'https': bls_proxy})
    else:
        # Pre-flight check to instantly detect BLS Geoblocking
        try:
            requests.get("https://api.bls.gov", timeout=3)
        except requests.exceptions.RequestException:
            print("\n🚨 U.S. BLS FIREWALL BLOCK DETECTED 🚨")
            print("Your IP address is actively being dropped by the BLS server.")
            print("To proceed, add your VPN proxy port to the .env file (e.g., BLS_PROXY=http://127.0.0.1:7890)\n")
            return pd.DataFrame()

    retries = Retry(total=5, backoff_factor=1, status_forcelist=[ 500, 502, 503, 504 ])
    session.mount('https://', HTTPAdapter(max_retries=retries))
    
    bls_url = 'https://api.bls.gov/publicAPI/v2/timeseries/data/'
    headers = {'Content-type': 'application/json'}
    all_data = []

    # Map for easy decoding later
    series_to_fips = {}
    series_list = []
    for f in fips_list:
        sid = f"LAUCN{f}0000000003"
        series_list.append(sid)
        series_to_fips[sid] = f

    # Chunk the series list into batches of 50
    chunks = [series_list[i:i + 50] for i in range(0, len(series_list), 50)]
    
    for idx, chunk in enumerate(chunks):
        if idx > 0 and idx % 10 == 0:
            print(f"  Processed {idx} / {len(chunks)} API chunks...")
            
        payload = {
            "seriesid": chunk,
            "startyear": "2012",
            "endyear": "2024",
            "registrationkey": BLS_API_KEY,
            "annualaverage": True
        }
        
        try:
            resp = session.post(bls_url, data=json.dumps(payload), headers=headers, timeout=20)
            if resp.status_code == 200:
                res_json = resp.json()
                if 'Results' in res_json and 'series' in res_json['Results']:
                    for s in res_json['Results']['series']:
                        sid = s['seriesID']
                        fips = series_to_fips[sid]
                        for item in s['data']:
                            if item['period'] == 'M13':
                                all_data.append({
                                    'FIPS': fips,
                                    'year': int(item['year']),
                                    'Unemployment_Rate': float(item['value'])
                                })
        except requests.exceptions.RequestException as e:
            # Terminate early on critical disconnects rather than hanging for 60 iterations
            print(f"  Critical Network Failure on Chunk {idx}. Breaking loop.")
            break
            
        time.sleep(1.5)
        
    return pd.DataFrame(all_data)

def apply_population_weighted_crosswalk(df_county):
    """
    Exact ZCTA-to-County Allocation Logic (Population Weighted).
    Applies the MCDC Geocorr 2022 crosswalk logic to mathematically apportion 
    intensive attributes (Unemployment Rates) and extensive attributes (GDP).
    """
    print("Applying exact population-weighted crosswalk logic using Geocorr...")
    cw_path = os.path.join(os.path.dirname(__file__), '..', 'Data', 'zcta_county_crosswalk.csv')
    
    if not os.path.exists(cw_path):
        print(f"Crosswalk file not found at {cw_path}. Falling back to 1:1 FIPS=ZCTA map.")
        df_mapped = df_county.copy()
        df_mapped['ZCTA'] = df_mapped['FIPS']
        return df_mapped

    # Skip the second row containing the data descriptions to prevent type errors
    # Added encoding='latin-1' to parse special geographical characters (e.g., Doña Ana County)
    cw = pd.read_csv(cw_path, header=0, skiprows=[1], dtype={'zcta': str, 'county': str}, encoding='latin-1')
    
    # Filter out blank ZCTAs representing unpopulated geographical boundaries
    cw = cw[cw['zcta'].str.strip() != '']
    cw = cw.dropna(subset=['zcta', 'county'])
    
    # Clean geographic identifiers to match stringent 5-digit strings
    cw['FIPS'] = cw['county'].str.zfill(5)
    cw['ZCTA'] = cw['zcta'].str.zfill(5)
    
    # Ensure numerical dtypes for demographic indicators
    cw['pop20'] = pd.to_numeric(cw['pop20'], errors='coerce').fillna(0)
    cw['afact'] = pd.to_numeric(cw['afact'], errors='coerce').fillna(0)
    
    # Conduct inner mathematical merge mapping County control variables onto relational geometries
    print("  Merging boundary datasets...")
    merged = pd.merge(df_county, cw[['ZCTA', 'FIPS', 'pop20', 'afact']], on='FIPS', how='inner')
    
    print("  Calculating Structural Matrices...")
    # 1. Intensive Variable Allocation (Unemployment Rate)
    # Unemployment relies on 'afact' weighting, capturing the ZCTA-to-County share inherently
    if 'Unemployment_Rate' in merged.columns:
        merged['Weighted_Unemp'] = merged['Unemployment_Rate'] * merged['afact']
    else:
        merged['Weighted_Unemp'] = pd.NA
        
    # 2. Extensive Variable Allocation (Real GDP)
    # Extensive mapping relies on the inverse relative function: Country-to-ZCTA internal population density share
    county_pop = cw.groupby('FIPS')['pop20'].sum().reset_index().rename(columns={'pop20': 'County_Total_Pop'})
    merged = pd.merge(merged, county_pop, on='FIPS', how='left')
    
    # Guard against divide-by-zero on unpopulated county geometries gracefully
    merged['County_to_ZCTA_Share'] = merged['pop20'] / merged['County_Total_Pop'].replace(0, pd.NA)
    
    if 'Real_GDP_County' in merged.columns:
        merged['Weighted_GDP'] = merged['Real_GDP_County'] * merged['County_to_ZCTA_Share']
    else:
        merged['Weighted_GDP'] = pd.NA

    # 3. Aggregation Matrix
    print("  Coalescing into pure discrete ZCTA-Year panel arrays...")
    zcta_panel = merged.groupby(['ZCTA', 'year']).agg(
        Real_GDP_ZCTA=('Weighted_GDP', 'sum'),
        Unemployment_Rate_ZCTA=('Weighted_Unemp', 'sum')
    ).reset_index()
    
    # Re-normalize missing data bounds that defaulted to 0 upon matrix array sum functionality
    if 'Real_GDP_County' not in df_county.columns:
        zcta_panel['Real_GDP_ZCTA'] = pd.NA
    if 'Unemployment_Rate' not in df_county.columns:
        zcta_panel['Unemployment_Rate_ZCTA'] = pd.NA
        
    return zcta_panel

def main():
    # 1. Fetch GDP from BEA
    df_gdp = fetch_bea_gdp()
    if df_gdp.empty:
        print("Failed to pull BEA data. Exiting.")
        return
        
    # Extract active unique FIPS codes from the BEA data 
    active_fips = df_gdp['FIPS'].unique().tolist()
    
    # 2. Fetch BLS LAUS Unemployment data iteratively
    df_laus = fetch_bls_unemployment(active_fips)
    
    if df_laus.empty:
        print("Failed to pull valid BLS LAUS data. Relying on GDP only.")
        df_county = df_gdp
    else:    
        # 3. Merge macroeconomic datasets
        df_county = pd.merge(df_gdp, df_laus, on=['FIPS', 'year'], how='left')

    # 4. Programmatic Allocation (Option B)
    df_zcta_macro = apply_population_weighted_crosswalk(df_county)
    
    # Drop intermediate FIPS if desired
    if 'FIPS' in df_zcta_macro.columns and 'ZCTA' in df_zcta_macro.columns:
        df_zcta_macro.drop(columns=['FIPS'], inplace=True)
        
    # Group by ZCTA and year to coalesce duplicates just in case
    df_zcta_macro = df_zcta_macro.groupby(['ZCTA', 'year']).mean().reset_index()
    
    # 5. Forward-fill 2024 data to 2025 and 2026
    print("Forward-filling 2024 to 2025 and 2026...")
    df_2024 = df_zcta_macro[df_zcta_macro['year'] == 2024].copy()
    
    for y in [2025, 2026]:
        df_y = df_2024.copy()
        df_y['year'] = y
        df_zcta_macro = pd.concat([df_zcta_macro, df_y], ignore_index=True)

    df_zcta_macro.sort_values(by=['ZCTA', 'year'], inplace=True)
    
    # 6. Save Macro panel
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'output')
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'macro_zcta_panel.csv')
    
    df_zcta_macro.to_csv(output_file, index=False)
    print(f"Macroeconomic panel saved to {output_file}")

if __name__ == "__main__":
    main()
