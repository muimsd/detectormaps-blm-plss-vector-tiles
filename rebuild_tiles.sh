#!/bin/bash
# Rebuild BLM PLSS vector tiles with proper simplification for lower zoom levels
# This script uses Tippecanoe to create optimized vector tiles from GeoJSON sources

set -e  # Exit on error

echo "=== BLM PLSS Vector Tiles Rebuild ==="
echo ""

# Check if tippecanoe is installed
if ! command -v tippecanoe &> /dev/null; then
    echo "Error: tippecanoe is not installed."
    echo "Install on macOS: brew install tippecanoe"
    echo "Install on Ubuntu: sudo apt-get install tippecanoe"
    exit 1
fi

# Configuration
OUTPUT_FILE="blm-plss-cadastral-optimized.mbtiles"
DATA_DIR="data"

# Check if data directory exists
if [ ! -d "$DATA_DIR" ]; then
    echo "Error: data directory not found: $DATA_DIR"
    echo "Expected GeoJSON files in: $DATA_DIR/"
    exit 1
fi

# Remove old MBTiles file if it exists
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing MBTiles file: $OUTPUT_FILE"
    rm "$OUTPUT_FILE"
fi

echo "Building optimized vector tiles..."
echo ""

# Run tippecanoe with optimization settings
tippecanoe \
    --output="$OUTPUT_FILE" \
    --name="BLM PLSS Cadastral" \
    --attribution="Bureau of Land Management" \
    --layer=plss_township \
    --layer=plss_section \
    --layer=plss_intersected \
    --layer=state_boundaries \
    --minimum-zoom=0 \
    --maximum-zoom=14 \
    --drop-densest-as-needed \
    --extend-zooms-if-still-dropping \
    --simplification=10 \
    --buffer=5 \
    --maximum-tile-bytes=500000 \
    --maximum-tile-features=200000 \
    --base-zoom=14 \
    --force \
    --read-parallel \
    --no-tile-size-limit \
    "$DATA_DIR/state_boundaries.geojson" \
    "$DATA_DIR/plss_township.geojson" \
    "$DATA_DIR/plss_section.geojson"

echo ""
echo "=== Build Complete ==="
echo "Output file: $OUTPUT_FILE"
echo ""

# Show file size
FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo "File size: $FILE_SIZE"
echo ""

# Show some stats using sqlite3
if command -v sqlite3 &> /dev/null; then
    echo "Tile statistics:"
    sqlite3 "$OUTPUT_FILE" "SELECT 
        zoom_level, 
        COUNT(*) as tile_count,
        ROUND(AVG(LENGTH(tile_data))/1024.0, 2) as avg_kb,
        ROUND(MAX(LENGTH(tile_data))/1024.0, 2) as max_kb
    FROM tiles 
    GROUP BY zoom_level 
    ORDER BY zoom_level;"
    echo ""
fi

echo "To upload to S3:"
echo "  aws s3 cp $OUTPUT_FILE s3://blm-plss-tiles-production-221082193991/ --profile detectormaps --region us-east-1"
echo ""
echo "To test locally:"
echo "  tileserver-gl-light $OUTPUT_FILE"
