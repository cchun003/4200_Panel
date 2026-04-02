import os
import pandas as pd
import geopandas as gpd
from shapely.geometry import LineString, MultiLineString
from shapely.ops import substring, unary_union
import warnings

# Suppress pandas warning about chained assignments
warnings.filterwarnings('ignore')

# ==========================================
# Configuration and Setup
# Identify project root relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

DATA_DIR = os.path.join(PROJECT_ROOT, "Data")
SHAPEFILE_DIR = os.path.join(DATA_DIR, "Shapefiles")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "Output")

TARGET_CRS = "EPSG:5070" # Albers Equal Area Conic (meters)
TARGET_SEGMENT_LENGTH_M = 50000.0 # 50 kilometers in meters

# Input files generated from Task 2.1
PANEL_INPUT_PATH = os.path.join(OUTPUT_DIR, "zcta_distance_panel.csv")
STATE_SHP_PATH = os.path.join(SHAPEFILE_DIR, "tl_2022_us_state.shp")
ZCTA_SHP_PATH = os.path.join(SHAPEFILE_DIR, "tl_2020_us_zcta520.shp")

# ==========================================
# Step 1: Data Ingestion
# ==========================================
print("Loading spatial data and Task 2.1 panel...")
panel_df = pd.read_csv(PANEL_INPUT_PATH, dtype={'zcta': str})
states_gdf = gpd.read_file(STATE_SHP_PATH).to_crs(TARGET_CRS)
zctas_gdf = gpd.read_file(ZCTA_SHP_PATH).to_crs(TARGET_CRS)

zctas_gdf['geometry'] = zctas_gdf.geometry.centroid
zcta_centroids = zctas_gdf[['GEOID20', 'geometry']].rename(columns={'GEOID20': 'zcta'})

# ==========================================
# Step 2: Clean Boundary Extraction (Sliver Removal)
# ==========================================
print("Extracting and cleaning state boundaries to remove slivers...")
NON_CONTIGUOUS_FIPS = ['02', '15', '72', '78', '66', '60', '69']
states_gdf = states_gdf[~states_gdf['STATEFP'].isin(NON_CONTIGUOUS_FIPS)]

border_geoms = []
for i, state1 in states_gdf.iterrows():
    for j, state2 in states_gdf.iterrows():
        if i < j:
            if state1.geometry.touches(state2.geometry) or state1.geometry.intersects(state2.geometry):
                # Use a tiny buffer to capture shared boundaries and then intersect
                intersection = state1.geometry.intersection(state2.geometry)
                
                if not intersection.is_empty:
                    # HEURISTIC: Dissolve tiny fragments and slivers
                    # We only care about LineStrings longer than 100 meters to avoid noise
                    if intersection.geom_type == 'MultiLineString':
                        lines = [l for l in intersection.geoms if l.length > 100]
                        intersection = MultiLineString(lines) if lines else None
                    elif intersection.geom_type == 'LineString':
                        intersection = intersection if intersection.length > 100 else None
                    
                    if intersection:
                        dyad_states = sorted([state1['STUSPS'], state2['STUSPS']])
                        border_geoms.append({
                            'border_dyad': f"{dyad_states[0]}-{dyad_states[1]}",
                            'geometry': intersection
                        })

borders_gdf = gpd.GeoDataFrame(border_geoms, crs=TARGET_CRS)

# ==========================================
# Step 3: Robust Segmentation (Option B)
# ==========================================
print("Partitioning boundaries into equal ~50km segments...")

def segment_line(geom, dyad_name, target_len):
    segments = []
    # Merge MultiLineStrings into the fewest possible continuous lines
    merged_geom = unary_union(geom)
    
    lines = []
    if merged_geom.geom_type == 'MultiLineString':
        lines = list(merged_geom.geoms)
    elif merged_geom.geom_type == 'LineString':
        lines = [merged_geom]

    seg_idx = 1
    for line in lines:
        L = line.length
        n_segments = max(1, int(round(L / target_len)))
        step = L / n_segments
        
        for i in range(n_segments):
            sub_line = substring(line, i * step, (i + 1) * step)
            segments.append({
                'border_dyad': dyad_name,
                'segment_id': f"{dyad_name}_{str(seg_idx).zfill(3)}",
                'geometry': sub_line
            })
            seg_idx += 1
    return segments

all_segments = []
for _, row in borders_gdf.iterrows():
    all_segments.extend(segment_line(row['geometry'], row['border_dyad'], TARGET_SEGMENT_LENGTH_M))

segments_gdf = gpd.GeoDataFrame(all_segments, crs=TARGET_CRS)

# ==========================================
# Step 4: Spatial Mapping & De-duplication
# ==========================================
print("Mapping ZCTAs and resolving duplicates...")
panel_gdf = panel_df.merge(zcta_centroids, on='zcta', how='left')
panel_gdf = gpd.GeoDataFrame(panel_gdf, geometry='geometry', crs=TARGET_CRS)

mapped_results = []
for dyad in panel_gdf['border_dyad'].unique():
    dyad_zctas = panel_gdf[panel_gdf['border_dyad'] == dyad]
    dyad_segs = segments_gdf[segments_gdf['border_dyad'] == dyad][['segment_id', 'geometry']]
    
    if not dyad_segs.empty:
        # Join ZCTAs to the nearest 50km segment of the correct dyad
        mapped = gpd.sjoin_nearest(dyad_zctas, dyad_segs, how='left')
        mapped_results.append(mapped)

final_panel = pd.concat(mapped_results, ignore_index=True)

# CRITICAL FIX: Remove the 352 exact duplicates found in validation
final_panel = final_panel.drop_duplicates(subset=['zcta', 'segment_id'])

# ==========================================
# Step 5: Export
# ==========================================
cols = ['zcta', 'stab', 'border_dyad', 'segment_id', 'S_i', 'dist_km', 'd_ic']
output_path = os.path.join(OUTPUT_DIR, "zcta_distance_segment_panel.csv")
final_panel[cols].to_csv(output_path, index=False)

print(f"Refined Task 2.2 Complete. Cleaned panel saved to: {output_path}")