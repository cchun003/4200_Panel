import pandas as pd
import numpy as np
import re
import os

def validate_panel():
    # Identify path relative to this script
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
    file_path = os.path.join(PROJECT_ROOT, "Output", "zcta_distance_segment_panel.csv")
    
    print(f"--- Starting Data Integrity Validation ---")
    print(f"Target File: {file_path}\n")
    
    if not os.path.exists(file_path):
        print(f"[FAIL] File not found: {file_path}")
        return

    # Load data, forcing zcta to string to check for dropped leading zeros
    df = pd.read_csv(file_path, dtype={'zcta': str})
    total_rows = len(df)
    print(f"Records loaded: {total_rows}")
    
    issues_found = 0

    # 1. Identifier Integrity
    print("\n1. Checking Identifier Integrity...")
    null_cols = df[['zcta', 'stab', 'border_dyad']].isnull().sum()
    if null_cols.sum() > 0:
        print(f"[FAIL] Null values detected:\n{null_cols[null_cols > 0]}")
        issues_found += 1
    else:
        print("[PASS] No null values in key identifiers.")

    invalid_zctas = df[~df['zcta'].str.match(r'^\d{5}$', na=False)]
    if not invalid_zctas.empty:
        print(f"[FAIL] Found {len(invalid_zctas)} ZCTAs missing leading zeros or improperly formatted.")
        issues_found += 1
    else:
        print("[PASS] All ZCTAs are strict 5-character strings.")

    # 2. Treatment Logic (S_i and d_ic)
    print("\n2. Checking Treatment Logic (Directional Normalization)...")
    logic_errors = df[
        ((df['S_i'] == 1) & (df['d_ic'] < 0)) | 
        ((df['S_i'] == 0) & (df['d_ic'] > 0))
    ]
    if not logic_errors.empty:
        print(f"[FAIL] Found {len(logic_errors)} rows where S_i does not match the sign of d_ic.")
        issues_found += 1
    else:
        print("[PASS] S_i indicators match d_ic signs.")

    dist_mismatch = df[~np.isclose(df['dist_km'], df['d_ic'].abs(), atol=1e-5)]
    if not dist_mismatch.empty:
        print(f"[FAIL] Found {len(dist_mismatch)} rows where dist_km != abs(d_ic).")
        issues_found += 1
    else:
        print("[PASS] Absolute distances match.")

    # 3. Fixed-Effect Bin Viability
    print("\n3. Checking Fixed-Effect Bin Viability...")
    segment_counts = df.groupby('segment_id')['zcta'].nunique()
    sparse_segments = segment_counts[segment_counts < 10]
    if not sparse_segments.empty:
        print(f"[WARNING] Found {len(sparse_segments)} segments with fewer than 10 unique ZCTAs. This may reduce statistical power in fixed-effects estimation.")
    else:
        print("[PASS] All segments contain >= 10 unique ZCTAs.")

    # 4. R Compatibility
    print("\n4. Checking R Compatibility...")
    invalid_chars_regex = r'[^a-zA-Z0-9_\-]'
    
    bad_dyads = df[df['border_dyad'].astype(str).str.contains(invalid_chars_regex, regex=True)]
    bad_segments = df[df['segment_id'].astype(str).str.contains(invalid_chars_regex, regex=True)]
    
    if not bad_dyads.empty or not bad_segments.empty:
        print(f"[FAIL] Found special characters/spaces in border_dyad or segment_id.")
        issues_found += 1
    else:
        print("[PASS] All string identifiers are safe for R factor conversion.")

    # 5. Multi-Border Duplication
    print("\n5. Checking Duplication Logic...")
    exact_duplicates = df[df.duplicated(subset=['zcta', 'segment_id'], keep=False)]
    if not exact_duplicates.empty:
        print(f"[FAIL] Found {len(exact_duplicates)} perfectly duplicated ZCTA-to-Segment mappings.")
        issues_found += 1
    else:
        print("[PASS] No exact duplicate mappings found (valid multi-border overlaps preserved).")

    # Final Verdict
    print("\n========================================")
    if issues_found == 0:
        print("✅ VALIDATION PASSED: The dataset is structurally sound and ready for R.")
    else:
        print(f"❌ VALIDATION FAILED: {issues_found} critical issue category/categories detected. Please review the logs above.")
    print("========================================\n")

if __name__ == "__main__":
    validate_panel()