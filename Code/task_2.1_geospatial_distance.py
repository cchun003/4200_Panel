import os
import requests
import zipfile
import pandas as pd
import geopandas as gpd
from shapely.geometry import Point

# ==========================================
# Configuration and Setup
# ==========================================
# Identify project root relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

DATA_DIR = os.path.join(PROJECT_ROOT, "Data")
SHAPEFILE_DIR = os.path.join(DATA_DIR, "Shapefiles")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "Output")

# Create directories if they don't exist
os.makedirs(SHAPEFILE_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Census TIGER/Line URLs (2020 ZCTAs and 2022 States)
STATE_SHP_URL = "https://www2.census.gov/geo/tiger/TIGER2022/STATE/tl_2022_us_state.zip"
ZCTA_SHP_URL = "https://www2.census.gov/geo/tiger/TIGER2020/ZCTA520/tl_2020_us_zcta520.zip"

# Albers Equal Area Conic (Contiguous US) - Natively measures in meters
TARGET_CRS = "EPSG:5070"

# FIPS codes to exclude to isolate the contiguous lower 48 states
# Excludes: AK(02), HI(15), PR(72), VI(78), GU(66), AS(60), MP(69)
NON_CONTIGUOUS_FIPS = ['02', '15', '72', '78', '66', '60', '69']

# ==========================================
# Step 1: Programmatic Shapefile Sourcing
# ==========================================
def download_and_extract(url, extract_to):
    """Downloads and extracts a zip file if it doesn't already exist."""
    zip_path = os.path.join(extract_to, url.split('/')[-1])
    
    if not os.path.exists(zip_path):
        print(f"Downloading {url}...")
        response = requests.get(url, stream=True)
        with open(zip_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"Extracting to {extract_to}...")
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_to)
    else:
        print(f"Using cached shapefile from {zip_path}")
        
    # Return the path to the main .shp file
    shp_file = [f for f in os.listdir(extract_to) if f.endswith('.shp') and url.split('/')[-1].split('.')[0] in f][0]
    return os.path.join(extract_to, shp_file)

state_shp_path = download_and_extract(STATE_SHP_URL, SHAPEFILE_DIR)
zcta_shp_path = download_and_extract(ZCTA_SHP_URL, SHAPEFILE_DIR)

# ==========================================
# Step 2: Geospatial Ingestion & Reprojection
# ==========================================
print("Loading geometries and reprojecting to EPSG:5070...")
states_gdf = gpd.read_file(state_shp_path)
zctas_gdf = gpd.read_file(zcta_shp_path)

# Filter for contiguous lower 48 states
states_gdf = states_gdf[~states_gdf['STATEFP'].isin(NON_CONTIGUOUS_FIPS)]

# Reproject to Albers Equal Area Conic
states_gdf = states_gdf.to_crs(TARGET_CRS)
zctas_gdf = zctas_gdf.to_crs(TARGET_CRS)

# Calculate ZCTA centroids on RAW geometries
zctas_gdf['geometry'] = zctas_gdf.geometry.centroid

# Load Crosswalk to assign ZCTAs to states
crosswalk_path = os.path.join(DATA_DIR, "zcta_state_crosswalk.csv")
if os.path.exists(crosswalk_path):
    # Use header=0 and skiprows=[1] to skip the Geocorr text description row
    crosswalk = pd.read_csv(crosswalk_path, header=0, skiprows=[1], dtype={'zcta': str}, encoding='latin-1')
    # Clean zcta strings to ensure proper matching with Census GEOIDs
    crosswalk['zcta'] = crosswalk['zcta'].str.strip().str.zfill(5) 
    zctas_gdf = zctas_gdf.merge(crosswalk, left_on='GEOID20', right_on='zcta', how='inner')
else:
    raise FileNotFoundError(f"Missing crosswalk file: {crosswalk_path}")

# ==========================================
# Step 3: Extracting Border Dyads
# ==========================================
print("Computing geometric intersections for all state border dyads...")
border_records = []

# Iterate over all combinations of states to find borders
for i, state1 in states_gdf.iterrows():
    for j, state2 in states_gdf.iterrows():
        if i < j:  # Process each pair only once
            if state1.geometry.touches(state2.geometry) or state1.geometry.intersects(state2.geometry):
                # Extract the boundary LineString
                intersection = state1.geometry.intersection(state2.geometry)
                
                # Keep only valid line geometries (ignores point intersections)
                if intersection.geom_type in ['LineString', 'MultiLineString']:
                    # Directional Normalization: Sort alphabetically
                    dyad_states = sorted([state1['STUSPS'], state2['STUSPS']])
                    state_A, state_B = dyad_states[0], dyad_states[1]
                    
                    border_records.append({
                        'border_dyad': f"{state_A}-{state_B}",
                        'state_A': state_A, # S_i = 1
                        'state_B': state_B, # S_i = 0
                        'geometry': intersection
                    })

borders_gdf = gpd.GeoDataFrame(border_records, crs=TARGET_CRS)

# ==========================================
# Step 4: Comprehensive Distance Calculation & Normalization
# ==========================================
print("Calculating distances to ALL relevant borders and applying Directional Normalization...")
final_results = []

# Process state by state 
for state_abbr in states_gdf['STUSPS'].unique():
    # Filter ZCTAs belonging to this state
    state_zctas = zctas_gdf[zctas_gdf['stab'] == state_abbr]
    
    # Filter ALL borders that this state shares
    state_borders = borders_gdf[(borders_gdf['state_A'] == state_abbr) | (borders_gdf['state_B'] == state_abbr)]
    
    if state_zctas.empty or state_borders.empty:
        continue

    # For every border this state shares, calculate the distance to all ZCTAs in the state
    for idx, border_row in state_borders.iterrows():
        # Calculate Euclidean distance from each ZCTA centroid to this specific border line
        # Note: geopandas .distance() automatically aligns indices and computes point-to-line distances
        distances = state_zctas.geometry.distance(border_row.geometry)
        
        # Construct a temporary dataframe for this specific State-Border pairing
        temp_df = state_zctas[['zcta', 'stab']].copy()
        temp_df['border_dyad'] = border_row['border_dyad']
        temp_df['state_A'] = border_row['state_A']
        temp_df['state_B'] = border_row['state_B']
        temp_df['dist_meters'] = distances
        
        final_results.append(temp_df)

# Combine all pairwise results
output_df = pd.concat(final_results, ignore_index=True)

# Convert meters to Kilometers
output_df['dist_km'] = output_df['dist_meters'] / 1000.0

# Apply Directional Normalization
# state_A is alphabetically first, so it gets S_i = 1 and positive d_ic
output_df['S_i'] = output_df.apply(lambda row: 1 if row['stab'] == row['state_A'] else 0, axis=1)
output_df['d_ic'] = output_df.apply(lambda row: row['dist_km'] if row['S_i'] == 1 else -row['dist_km'], axis=1)

# ==========================================
# Step 5: Export Panel 
# ==========================================
print("Exporting expanded pairwise results to Output directory...")
columns_to_export = ['zcta', 'stab', 'border_dyad', 'S_i', 'dist_km', 'd_ic']

# Note: We no longer drop duplicates by ZCTA, because a single ZCTA 
# legitimately has multiple valid distances (one for each shared border).
export_df = output_df[columns_to_export]

output_path = os.path.join(OUTPUT_DIR, "zcta_distance_panel.csv")
export_df.to_csv(output_path, index=False)
print(f"Task 2.1 Complete. Expanded panel exported to: {output_path}")