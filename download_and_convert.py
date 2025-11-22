#!/usr/bin/env python3
"""
Download GeoJSON from BLM PLSS CadNSDI MapServer and convert to MBTiles with multiple source layers.
"""

import os
import json
import requests
from pathlib import Path
import subprocess
import sys

# BLM PLSS CadNSDI MapServer URL
BASE_URL = "https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer"

# Layer definitions
LAYERS = {
    0: {"name": "state_boundaries", "description": "State Boundaries"},
    1: {"name": "plss_township", "description": "PLSS Township"},
    2: {"name": "plss_section", "description": "PLSS Section"},
    3: {"name": "plss_intersected", "description": "PLSS Intersected"}
}

DATA_DIR = Path("data")
OUTPUT_FILE = "blm-plss-cadastral.mbtiles"


def download_geojson(layer_id, output_file):
    """Download GeoJSON for a specific layer from the MapServer."""
    print(f"Downloading layer {layer_id}: {LAYERS[layer_id]['name']}...")
    
    # Query all features with pagination
    url = f"{BASE_URL}/{layer_id}/query"
    
    all_features = []
    offset = 0
    max_record_count = 2000  # Based on service description
    
    while True:
        params = {
            'where': '1=1',
            'outFields': '*',
            'f': 'geojson',
            'resultOffset': offset,
            'resultRecordCount': max_record_count,
            'outSR': '4326'  # WGS84
        }
        
        print(f"  Fetching records {offset} to {offset + max_record_count}...")
        response = requests.get(url, params=params, timeout=300)
        response.raise_for_status()
        
        data = response.json()
        
        if 'features' not in data or len(data['features']) == 0:
            break
            
        all_features.extend(data['features'])
        
        # Check if we got all records
        if len(data['features']) < max_record_count:
            break
            
        offset += max_record_count
    
    # Create complete GeoJSON
    geojson = {
        "type": "FeatureCollection",
        "features": all_features
    }
    
    print(f"  Total features downloaded: {len(all_features)}")
    
    # Save to file
    with open(output_file, 'w') as f:
        json.dump(geojson, f)
    
    print(f"  Saved to {output_file}")
    return len(all_features)


def convert_to_mbtiles():
    """Convert all GeoJSON files to a single MBTiles with multiple source layers."""
    print("\nConverting GeoJSON files to MBTiles...")
    
    # Build tippecanoe command with all layers
    cmd = [
        "tippecanoe",
        "-o", OUTPUT_FILE,
        "--force",  # Overwrite existing file
        "--drop-densest-as-needed",  # Drop features to stay under tile size limits
        "--extend-zooms-if-still-dropping",  # Add zoom levels if needed
        "--maximum-zoom=14",  # Max zoom level
        "--minimum-zoom=0",   # Min zoom level
        "--base-zoom=14",     # Base zoom for feature selection
        "--no-tile-compression",  # Better for CloudFront serving
        "--coalesce-densest-as-needed",  # Combine nearby features
        "--detect-shared-borders",  # Optimize polygon borders
        "--simplification=10",  # Simplify geometries
    ]
    
    # Add each layer with its specific name
    for layer_id, layer_info in LAYERS.items():
        geojson_file = DATA_DIR / f"{layer_info['name']}.geojson"
        if geojson_file.exists():
            cmd.extend([
                f"--layer={layer_info['name']}",
                str(geojson_file)
            ])
    
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    
    print(f"\nMBTiles created: {OUTPUT_FILE}")
    
    # Get file size
    file_size = os.path.getsize(OUTPUT_FILE)
    print(f"File size: {file_size / (1024**2):.2f} MB")


def main():
    """Main function to orchestrate download and conversion."""
    print("BLM PLSS CadNSDI GeoJSON Download and MBTiles Conversion")
    print("=" * 60)
    
    # Check for tippecanoe
    try:
        subprocess.run(["tippecanoe", "--version"], 
                      capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: tippecanoe is not installed.")
        print("Install it with: brew install tippecanoe")
        sys.exit(1)
    
    # Create data directory
    DATA_DIR.mkdir(exist_ok=True)
    
    # Download all layers
    total_features = 0
    for layer_id, layer_info in LAYERS.items():
        geojson_file = DATA_DIR / f"{layer_info['name']}.geojson"
        count = download_geojson(layer_id, geojson_file)
        total_features += count
    
    print(f"\nTotal features downloaded: {total_features}")
    
    # Convert to MBTiles
    convert_to_mbtiles()
    
    print("\n✓ Complete!")


if __name__ == "__main__":
    main()
