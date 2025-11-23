#!/usr/bin/env python3
"""
Convert BLM National PLSS GDB to MBTiles with 4 layers
"""
import subprocess
import os
import sys

PLSS_GDB_PATH = "/Volumes/external/Downloads/BLM_NATL_PLSS.gdb/ilmocplss.gdb"
STATES_GDB_PATH = "/Volumes/external/Downloads/BLM_NATL_PLSS.gdb/BOC_cb_2017_US_State_500k.gdb"
OUTPUT_DIR = "/Volumes/external/projects/freelance/detectormaps/blm-plss-vector-tiles"
OUTPUT_FILE = "blm-plss-cadastral.mbtiles"

# Define the layers to extract from each GDB (only existing layers)
PLSS_LAYERS = {
    "PLSSFirstDivision": "plss_township",      # Townships
    "PLSSTownship": "plss_township_alt",       # Alternative township layer
    "PLSSIntersected": "plss_intersected",     # Intersected areas
}

STATES_LAYERS = {
    "cb_2017_us_state_500k": "state_boundaries"  # US State boundaries
}

def check_gdal():
    """Check if GDAL/OGR is installed"""
    try:
        subprocess.run(["ogrinfo", "--version"], check=True, capture_output=True)
        print("✓ GDAL/OGR is installed")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("✗ GDAL/OGR is not installed")
        print("Install with: brew install gdal")
        return False

def check_tippecanoe():
    """Check if tippecanoe is installed"""
    try:
        subprocess.run(["tippecanoe", "--version"], check=True, capture_output=True)
        print("✓ Tippecanoe is installed")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("✗ Tippecanoe is not installed")
        print("Install with: brew install tippecanoe")
        return False

def list_gdb_layers(gdb_path):
    """List all layers in the GDB"""
    print(f"\nListing layers in {gdb_path}...")
    try:
        result = subprocess.run(
            ["ogrinfo", gdb_path],
            check=True,
            capture_output=True,
            text=True
        )
        print(result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error listing layers: {e}")
        return False

def convert_layer_to_geojson(gdb_path, layer_name, output_name):
    """Convert a single GDB layer to GeoJSON"""
    geojson_file = f"{OUTPUT_DIR}/{output_name}.geojson"
    
    print(f"\nConverting {layer_name} to {output_name}.geojson...")
    
    cmd = [
        "ogr2ogr",
        "-f", "GeoJSON",
        "-t_srs", "EPSG:4326",  # Convert to WGS84
        geojson_file,
        gdb_path,
        layer_name
    ]
    
    try:
        subprocess.run(cmd, check=True)
        
        # Get file size
        size = os.path.getsize(geojson_file)
        size_mb = size / (1024 * 1024)
        print(f"✓ Created {geojson_file} ({size_mb:.1f} MB)")
        return geojson_file
    except subprocess.CalledProcessError as e:
        print(f"✗ Error converting {layer_name}: {e}")
        return None

def create_mbtiles(geojson_files):
    """Create MBTiles from all GeoJSON files"""
    output_path = f"{OUTPUT_DIR}/{OUTPUT_FILE}"
    
    # Remove existing MBTiles if it exists
    if os.path.exists(output_path):
        print(f"\nRemoving existing {OUTPUT_FILE}...")
        os.remove(output_path)
    
    print(f"\nCreating MBTiles with {len(geojson_files)} layers...")
    
    cmd = [
        "tippecanoe",
        "-o", output_path,
        "-z14",  # Max zoom level
        "-Z0",   # Min zoom level
        "-l", "plss",  # Base layer name (will be overridden by each file)
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

def cleanup_geojson(geojson_files):
    """Remove temporary GeoJSON files"""
    print("\nCleaning up temporary GeoJSON files...")
    for geojson_file, _ in geojson_files:
        try:
            os.remove(geojson_file)
            print(f"✓ Removed {geojson_file}")
        except Exception as e:
            print(f"✗ Error removing {geojson_file}: {e}")

def main():
    print("=" * 70)
    print("BLM National PLSS GDB to MBTiles Converter")
    print("=" * 70)
    
    # Check prerequisites
    if not check_gdal():
        sys.exit(1)
    
    if not check_tippecanoe():
        sys.exit(1)
    
    # Check if GDB exists
    if not os.path.exists(PLSS_GDB_PATH):
        print(f"\n✗ PLSS GDB not found at {PLSS_GDB_PATH}")
        sys.exit(1)
    
    if not os.path.exists(STATES_GDB_PATH):
        print(f"\n✗ States GDB not found at {STATES_GDB_PATH}")
        sys.exit(1)
    
    print(f"\n✓ Found PLSS GDB at {PLSS_GDB_PATH}")
    print(f"✓ Found States GDB at {STATES_GDB_PATH}")
    
    # List layers from both GDBs
    print("\n--- PLSS Layers ---")
    list_gdb_layers(PLSS_GDB_PATH)
    
    print("\n--- State Layers ---")
    list_gdb_layers(STATES_GDB_PATH)
    
    # Ask user to confirm layer names
    print("\nWill convert these PLSS layers:")
    for gdb_layer, output_name in PLSS_LAYERS.items():
        print(f"  - {gdb_layer} → {output_name}")
    
    print("\nWill convert these State layers:")
    for gdb_layer, output_name in STATES_LAYERS.items():
        print(f"  - {gdb_layer} → {output_name}")
    
    response = input("\nProceed? (y/n): ")
    if response.lower() != 'y':
        print("Aborted.")
        sys.exit(0)
    
    # Convert PLSS layers to GeoJSON
    geojson_files = []
    for gdb_layer, output_name in PLSS_LAYERS.items():
        geojson_file = convert_layer_to_geojson(PLSS_GDB_PATH, gdb_layer, output_name)
        if geojson_file:
            geojson_files.append((geojson_file, output_name))
    
    # Convert State layers to GeoJSON
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
    
    # Cleanup
    cleanup_geojson(geojson_files)
    
    print("\n" + "=" * 70)
    print("CONVERSION COMPLETE!")
    print("=" * 70)
    print(f"MBTiles file: {mbtiles_path}")
    print(f"\nTo upload to S3:")
    print(f"  AWS_PROFILE=detectormaps aws s3 cp {mbtiles_path} \\")
    print(f"    s3://blm-plss-tiles-production-221082193991/blm-plss-cadastral.mbtiles")
    print("\n" + "=" * 70)

if __name__ == "__main__":
    main()
