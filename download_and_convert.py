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


def get_layer_max_record_count(layer_id):
    """Get the maxRecordCount from the layer metadata."""
    url = f"{BASE_URL}/{layer_id}"
    params = {'f': 'json'}
    
    try:
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        metadata = response.json()
        max_count = metadata.get('maxRecordCount', 1000)
        print(f"  Layer {layer_id} maxRecordCount: {max_count}")
        return max_count
    except Exception as e:
        print(f"  Warning: Could not fetch maxRecordCount, using default 1000. Error: {e}")
        return 1000


def download_geojson(layer_id, output_file):
    """Download GeoJSON for a specific layer from the MapServer."""
    print(f"Downloading layer {layer_id}: {LAYERS[layer_id]['name']}...")
    
    # Check if file already exists and is complete
    if output_file.exists():
        try:
            with open(output_file, 'r') as f:
                existing_data = json.load(f)
                feature_count = len(existing_data.get('features', []))
                if feature_count > 0:
                    print(f"  Layer already downloaded with {feature_count} features, skipping...")
                    return feature_count
        except (json.JSONDecodeError, FileNotFoundError):
            print(f"  Existing file corrupted, re-downloading...")
    
    # Get the max record count from layer metadata
    max_record_count = get_layer_max_record_count(layer_id)
    
    # Query all features with pagination
    url = f"{BASE_URL}/{layer_id}/query"
    all_features = []
    offset = 0
    max_retries = 3
    
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
        
        # Retry logic for server errors
        data = None
        for attempt in range(max_retries):
            try:
                response = requests.get(url, params=params, timeout=300)
                response.raise_for_status()
                data = response.json()
                break
            except (requests.exceptions.HTTPError, requests.exceptions.Timeout) as e:
                if attempt < max_retries - 1:
                    print(f"    Retry {attempt + 1}/{max_retries} due to: {e}")
                    import time
                    time.sleep(2 ** attempt)  # Exponential backoff
                else:
                    print(f"    Failed after {max_retries} retries, stopping this layer")
                    break
        
        if data is None or 'features' not in data or len(data['features']) == 0:
            break
            
        all_features.extend(data['features'])
        print(f"    Total so far: {len(all_features)} features")
        
        # Save progress every 10k features in case of interruption
        if len(all_features) % 10000 < max_record_count:
            temp_geojson = {
                "type": "FeatureCollection",
                "features": all_features
            }
            temp_file = str(output_file) + '.tmp'
            with open(temp_file, 'w') as f:
                json.dump(temp_geojson, f)
        
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
    
    # Remove temp file if it exists
    temp_file = str(output_file) + '.tmp'
    if Path(temp_file).exists():
        Path(temp_file).unlink()
    
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
