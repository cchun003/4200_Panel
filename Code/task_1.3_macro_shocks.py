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

def fetch_bea_data():
    """
    Fetch Real GDP (CAGDP9) and Population (CAINC1) to calculate Real GDP per capita.
    """
    print("Fetching Real GDP (CAGDP9) and Population (CAINC1) from BEA API...")
    
    # 1. Fetch Real GDP (Total)
    url_gdp = (
        f"https://apps.bea.gov/api/data?&UserID={BEA_API_KEY}"
        f"&method=GetData&datasetname=Regional&TableName=CAGDP9"
        f"&LineCode=1&GeoFips=COUNTY&Year={YEAR_STR}&ResultFormat=JSON"
    )
    
    # 2. Fetch Population
    url_pop = (
        f"https://apps.bea.gov/api/data?&UserID={BEA_API_KEY}"
        f"&method=GetData&datasetname=Regional&TableName=CAINC1"
        f"&LineCode=2&GeoFips=COUNTY&Year={YEAR_STR}&ResultFormat=JSON"
    )

    def get_bea_df(url, val_name):
        resp = requests.get(url)
        if resp.status_code != 200:
            return pd.DataFrame()
        data = resp.json()
        try:
            results = data['BEAAPI']['Results']['Data']
            df = pd.DataFrame(results)
            df = df[['GeoFips', 'TimePeriod', 'DataValue']].copy()
            df.rename(columns={'GeoFips': 'FIPS', 'TimePeriod': 'year', 'DataValue': val_name}, inplace=True)
            df['year'] = df['year'].astype(int)
            df[val_name] = pd.to_numeric(df[val_name].astype(str).str.replace(',', ''), errors='coerce')
            return df
        except:
            return pd.DataFrame()

    df_gdp = get_bea_df(url_gdp, 'Real_GDP')
    df_pop = get_bea_df(url_pop, 'Population')

    if df_gdp.empty or df_pop.empty:
        print("Error pulling BEA data (GDP or Population).")
        return pd.DataFrame()

    # Merge and calculate per capita
    df = pd.merge(df_gdp, df_pop, on=['FIPS', 'year'], how='inner')
    
    # BEA GDP is typically in thousands of dollars, Population is in persons.
    # We calculate Real GDP per capita (in dollars)
    df['Real_GDP_per_capita_County'] = (df['Real_GDP'] * 1000) / df['Population'].replace(0, pd.NA)
    
    # Filter for valid FIPS
    df = df[df['FIPS'].str.len() == 5]
    df = df[~df['FIPS'].str.endswith('000')]
    
    return df[['FIPS', 'year', 'Real_GDP_per_capita_County']]

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

def fetch_bls_unemployment(fips_list):
    """
    Batch query the BLS API for Local Area Unemployment Statistics (LAUS).
    """
    print(f"Fetching BLS LAUS Data for {len(fips_list)} counties...")
    session = requests.Session()
    bls_proxy = os.environ.get("BLS_PROXY")
    if bls_proxy:
        session.proxies.update({'http': bls_proxy, 'https': bls_proxy})
    else:
        try:
            requests.get("https://api.bls.gov", timeout=3)
        except requests.exceptions.RequestException:
            print("\n🚨 U.S. BLS FIREWALL BLOCK DETECTED 🚨")
            return pd.DataFrame()

    retries = Retry(total=5, backoff_factor=1, status_forcelist=[ 500, 502, 503, 504 ])
    session.mount('https://', HTTPAdapter(max_retries=retries))
    
    bls_url = 'https://api.bls.gov/publicAPI/v2/timeseries/data/'
    headers = {'Content-type': 'application/json'}
    all_data = []

    series_to_fips = {}
    series_list = []
    for f in fips_list:
        sid = f"LAUCN{f}0000000003"
        series_list.append(sid)
        series_to_fips[sid] = f

    chunks = [series_list[i:i + 50] for i in range(0, len(series_list), 50)]
    
    for idx, chunk in enumerate(chunks):
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
                                all_data.append({'FIPS': fips, 'year': int(item['year']), 'Unemployment_Rate': float(item['value'])})
        except:
            break
        time.sleep(1.5)
        
    return pd.DataFrame(all_data)

def apply_intensive_crosswalk(df_county):
    """
    Assign Intensive Regional Environmental Indicators (Unemployment, GDP per Capita)
    to ZCTAs using residency allocation factors (afact).
    """
    print("Applying population-weighted assignment for intensive variables...")
    cw_path = os.path.join(os.path.dirname(__file__), '..', 'Data', 'zcta_county_crosswalk.csv')
    
    if not os.path.exists(cw_path):
        df_mapped = df_county.copy()
        df_mapped['ZCTA'] = df_mapped['FIPS']
        return df_mapped

    cw = pd.read_csv(cw_path, header=0, skiprows=[1], dtype={'zcta': str, 'county': str}, encoding='latin-1')
    cw = cw[cw['zcta'].str.strip() != '']
    cw['FIPS'] = cw['county'].str.zfill(5)
    cw['ZCTA'] = cw['zcta'].str.zfill(5)
    cw['afact'] = pd.to_numeric(cw['afact'], errors='coerce').fillna(0)
    
    merged = pd.merge(df_county, cw[['ZCTA', 'FIPS', 'afact']], on='FIPS', how='inner')
    
    # Apply intensive mapping: ZCTA_Val = Sum( County_Val * afact )
    # Since afact sums to 1 across counties for a given ZCTA, 
    # this correctly represents the 'experienced' environment.
    
    if 'Real_GDP_per_capita_County' in merged.columns:
        merged['Weighted_GDP_pc'] = merged['Real_GDP_per_capita_County'] * merged['afact']
    else:
        merged['Weighted_GDP_pc'] = 0.0

    if 'Unemployment_Rate' in merged.columns:
        merged['Weighted_Unemp'] = merged['Unemployment_Rate'] * merged['afact']
    else:
        merged['Weighted_Unemp'] = 0.0
        
    zcta_panel = merged.groupby(['ZCTA', 'year']).agg(
        Real_GDP_per_capita_ZCTA=('Weighted_GDP_pc', 'sum'),
        Unemployment_Rate_ZCTA=('Weighted_Unemp', 'sum')
    ).reset_index()
    
    return zcta_panel

def main():
    # 1. Fetch Components and calculate GDP per capita
    df_county_gdp = fetch_bea_data()
    if df_county_gdp.empty:
        print("Failed to pull BEA data. Exiting.")
        return
        
    active_fips = df_county_gdp['FIPS'].unique().tolist()
    
    # 2. Fetch BLS LAUS Unemployment data
    df_laus = fetch_bls_unemployment(active_fips)
    
    if df_laus.empty:
        df_county = df_county_gdp
    else:    
        df_county = pd.merge(df_county_gdp, df_laus, on=['FIPS', 'year'], how='left')

    # 3. Intensive Spatial Allocation
    df_zcta_macro = apply_intensive_crosswalk(df_county)
    
    # 4. Forward-fill 2024 to 2025 and 2026
    print("Forward-filling 2024 to 2025 and 2026...")
    df_2024 = df_zcta_macro[df_zcta_macro['year'] == 2024].copy()
    for y in [2025, 2026]:
        df_y = df_2024.copy()
        df_y['year'] = y
        df_zcta_macro = pd.concat([df_zcta_macro, df_y], ignore_index=True)

    df_zcta_macro.sort_values(by=['ZCTA', 'year'], inplace=True)
    
    # 5. Save Macro panel
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'Output')
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'macro_zcta_panel.csv')
    
    df_zcta_macro.to_csv(output_file, index=False)
    print(f"Macroeconomic panel saved to {output_file}")

if __name__ == "__main__":
    main()
