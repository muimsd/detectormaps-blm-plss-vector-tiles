#!/usr/bin/env python3
"""
Download BLM PLSS GDB, convert to MBTiles, and upload to S3
Runs in ECS container
"""
import subprocess
import os
import sys
import urllib.request
import zipfile

# URLs for downloads  
# ArcGIS direct download link for BLM PLSS GDB
GDB_ZIP_URL = "https://www.arcgis.com/sharing/rest/content/items/283939812bc34c11bad695a1c8152faf/data"
PLSS_GDB_PATH = "/app/data/ilmocplss.gdb"
STATES_GDB_PATH = "/app/data/BOC_cb_2017_US_State_500k.gdb"
OUTPUT_FILE = "blm-plss-cadastral.mbtiles"
S3_BUCKET = os.environ.get("S3_BUCKET", "blm-plss-tiles-production-221082193991")

# Layers to convert based on GDB structure
# PLSS layers are in ilmocplss.gdb
# State boundaries are in BOC_cb_2017_US_State_500k.gdb
# Layer 0: State Boundaries
# Layer 1: PLSS Township  
# Layer 2: PLSS Section
# Layer 3: PLSS Intersected
PLSS_LAYERS = {
    "PLSSTownship": "plss_township",        # Layer 1
    "PLSSFirstDivision": "plss_section",    # Layer 2
    "PLSSIntersected": "plss_intersected",  # Layer 3
}

STATES_LAYERS = {
    "cb_2017_us_state_500k": "state_boundaries"  # Layer 0
}

def download_gdb():
    """Download and extract GDB"""
    print("=" * 70)
    print("Downloading BLM PLSS GDB...")
    print("=" * 70)
    
    zip_path = "/app/data/BLM_NATL_PLSS.gdb.zip"
    
    # Use curl to download from Dropbox with proper handling
    cmd = [
        "curl",
        "-L",  # Follow redirects
        "-o", zip_path,
        GDB_ZIP_URL
    ]
    
    try:
        subprocess.run(cmd, check=True)
        print("✓ Download complete")
        
        # Verify it's a zip file
        file_size = os.path.getsize(zip_path)
        print(f"✓ Downloaded file size: {file_size / (1024**3):.2f} GB")
    except Exception as e:
        print(f"✗ Download failed: {e}")
        sys.exit(1)
    
    # Extract
    print("\nExtracting GDB...")
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall("/app/data")
        print("✓ Extraction complete")
        
        # List extracted contents
        print("\nInspecting extracted files...")
        result = subprocess.run(["ls", "-lah", "/app/data/"], capture_output=True, text=True)
        print(result.stdout)
        
        # Check GDB structure with ogrinfo
        print("\nChecking GDB with ogrinfo...")
        result = subprocess.run(["ogrinfo", "-so", "-al", PLSS_GDB_PATH], capture_output=True, text=True)
        if result.returncode == 0:
            print("✓ GDB is readable")
            print(result.stdout[:500])  # First 500 chars
        else:
            print("✗ GDB cannot be read:")
            print(result.stderr[:500])
        
        # Remove zip to save space
        os.remove(zip_path)
        print("✓ Cleaned up zip file")
    except Exception as e:
        print(f"✗ Extraction failed: {e}")
        sys.exit(1)

def convert_layer_to_geojson(gdb_path, layer_name, output_name):
    """Convert a single GDB layer to GeoJSON"""
    geojson_file = f"/app/data/{output_name}.geojson"
    
    print(f"\nConverting {layer_name} to {output_name}.geojson...")
    
    cmd = [
        "ogr2ogr",
        "-f", "GeoJSON",
        "-t_srs", "EPSG:4326",
        geojson_file,
        gdb_path,
        layer_name
    ]
    
    try:
        subprocess.run(cmd, check=True, stderr=subprocess.PIPE)
        
        # Get file size
        size = os.path.getsize(geojson_file)
        size_mb = size / (1024 * 1024)
        size_gb = size_mb / 1024
        
        if size_gb > 1:
            print(f"✓ Created {output_name}.geojson ({size_gb:.1f} GB)")
        else:
            print(f"✓ Created {output_name}.geojson ({size_mb:.1f} MB)")
        
        return geojson_file
    except subprocess.CalledProcessError as e:
        print(f"✗ Error converting {layer_name}: {e.stderr.decode() if e.stderr else e}")
        return None

def create_mbtiles(geojson_files):
    """Create MBTiles from all GeoJSON files"""
    output_path = f"/app/data/{OUTPUT_FILE}"
    
    print("\n" + "=" * 70)
    print(f"Creating MBTiles with {len(geojson_files)} layers...")
    print("=" * 70)
    
    cmd = [
        "tippecanoe",
        "-o", output_path,
        "-z14",
        "-Z0",
        "--force",
        "--no-feature-limit",
        "--no-tile-size-limit",
        "--drop-densest-as-needed",
        "--extend-zooms-if-still-dropping",
        "--no-tile-compression"
    ]
    
    # Add all GeoJSON files
    for geojson_file, layer_name in geojson_files:
        cmd.extend(["-L", f"{layer_name}:{geojson_file}"])
    
    try:
        subprocess.run(cmd, check=True)
        
        # Get final file size
        size = os.path.getsize(output_path)
        size_mb = size / (1024 * 1024)
        size_gb = size_mb / 1024
        
        if size_gb > 1:
            print(f"\n✓ Created {OUTPUT_FILE} ({size_gb:.2f} GB)")
        else:
            print(f"\n✓ Created {OUTPUT_FILE} ({size_mb:.1f} MB)")
        
        return output_path
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Error creating MBTiles: {e}")
        return None

def upload_to_s3(mbtiles_path):
    """Upload MBTiles to S3"""
    print("\n" + "=" * 70)
    print("Uploading to S3...")
    print("=" * 70)
    
    s3_path = f"s3://{S3_BUCKET}/{OUTPUT_FILE}"
    
    cmd = [
        "aws", "s3", "cp",
        mbtiles_path,
        s3_path,
        "--no-progress"
    ]
    
    try:
        subprocess.run(cmd, check=True)
        print(f"✓ Uploaded to {s3_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ Upload failed: {e}")
        return False

def main():
    print("\n" + "=" * 70)
    print("BLM PLSS GDB to MBTiles Converter (ECS)")
    print("=" * 70)
    
    # Create data directory
    os.makedirs("/app/data", exist_ok=True)
    
    # Download and extract GDB
    download_gdb()
    
    # Convert layers
    geojson_files = []
    
    print("\n" + "=" * 70)
    print("Converting PLSS Layers")
    print("=" * 70)
    
    for gdb_layer, output_name in PLSS_LAYERS.items():
        geojson_file = convert_layer_to_geojson(PLSS_GDB_PATH, gdb_layer, output_name)
        if geojson_file:
            geojson_files.append((geojson_file, output_name))
    
    print("\n" + "=" * 70)
    print("Converting State Layers")
    print("=" * 70)
    
    for gdb_layer, output_name in STATES_LAYERS.items():
        geojson_file = convert_layer_to_geojson(STATES_GDB_PATH, gdb_layer, output_name)
        if geojson_file:
            geojson_files.append((geojson_file, output_name))
    
    if not geojson_files:
        print("\n✗ No layers were converted successfully")
        sys.exit(1)
    
    print(f"\n✓ Successfully converted {len(geojson_files)} layers")
    
    # Create MBTiles
    mbtiles_path = create_mbtiles(geojson_files)
    
    if not mbtiles_path:
        sys.exit(1)
    
    # Upload to S3
    if not upload_to_s3(mbtiles_path):
        sys.exit(1)
    
    print("\n" + "=" * 70)
    print("CONVERSION COMPLETE!")
    print("=" * 70)
    print(f"MBTiles uploaded to s3://{S3_BUCKET}/{OUTPUT_FILE}")
    print("\n" + "=" * 70)

if __name__ == "__main__":
    main()
