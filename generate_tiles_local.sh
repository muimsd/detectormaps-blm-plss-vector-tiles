#!/bin/bash
set -e

echo "=== BLM PLSS Vector Tiles Generator - One-Time Build ==="
echo "This script generates optimized tiles without persistent infrastructure."
echo ""
echo "Usage: $0 [--upload-to-s3]"
echo ""

# Configuration
OUTPUT_DIR="./output"
GDB_DOWNLOAD_URL="https://www.arcgis.com/sharing/rest/content/items/283939812bc34c11bad695a1c8152faf/data"
UPLOAD_TO_S3="${1:-}"

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Step 1: Download and extract source GDB files
echo "Step 1: Downloading source data from ArcGIS..."
curl -L "$GDB_DOWNLOAD_URL" -o plss_data.zip 2>/dev/null

echo "Extracting GDB files..."
unzip -q plss_data.zip
rm plss_data.zip

echo "Source data extracted. Contents:"
du -sh *
echo ""

# Step 2: Build States layer (z0-z6 only)
echo "Step 2: Building states layer (z0-z6)..."
tippecanoe \
    -o states.mbtiles \
    -Z0 -z6 \
    --layer=states \
    --simplification=20 \
    --maximum-tile-bytes=50000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    BOC_cb_2017_US_State_500k.gdb

echo "States MBTiles: $(du -h states.mbtiles | cut -f1)"
echo "Converting to PMTiles..."
pmtiles convert states.mbtiles states.pmtiles
echo "States PMTiles: $(du -h states.pmtiles | cut -f1)"
echo ""

# Step 3: Build Townships layer (z8-z14)
echo "Step 3: Building townships layer (z8-z14)..."
echo "85,896 features, average 93 km² per polygon"
tippecanoe \
    -o townships.mbtiles \
    -Z8 -z14 \
    --layer=townships \
    --simplification=10 \
    --maximum-tile-bytes=200000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    ilmocplss.gdb PLSSTownship

echo "Townships MBTiles: $(du -h townships.mbtiles | cut -f1)"
echo "Converting to PMTiles..."
pmtiles convert townships.mbtiles townships.pmtiles
echo "Townships PMTiles: $(du -h townships.pmtiles | cut -f1)"
echo ""

# Step 4: Build Sections layer (z10-z14)
echo "Step 4: Building sections layer (z10-z14)..."
echo "2,776,408 features, average 2.5 km² per polygon"
tippecanoe \
    -o sections.mbtiles \
    -Z10 -z14 \
    --layer=sections \
    --simplification=5 \
    --maximum-tile-bytes=300000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    ilmocplss.gdb PLSSFirstDivision

echo "Sections MBTiles: $(du -h sections.mbtiles | cut -f1)"
echo "Converting to PMTiles..."
pmtiles convert sections.mbtiles sections.pmtiles
echo "Sections PMTiles: $(du -h sections.pmtiles | cut -f1)"
echo ""

# Step 5: Build Intersected parcels layer (z12-z14)
echo "Step 5: Building intersected parcels layer (z12-z14)..."
echo "27,338,029 features, average 0.26 km² per polygon"
echo "This will take the longest..."
tippecanoe \
    -o intersected.mbtiles \
    -Z12 -z14 \
    --layer=intersected \
    --simplification=2 \
    --maximum-tile-bytes=500000 \
    --drop-densest-as-needed \
    --coalesce-densest-as-needed \
    --detect-shared-borders \
    --force \
    ilmocplss.gdb PLSSIntersected

echo "Intersected MBTiles: $(du -h intersected.mbtiles | cut -f1)"
echo "Converting to PMTiles..."
pmtiles convert intersected.mbtiles intersected.pmtiles
echo "Intersected PMTiles: $(du -h intersected.pmtiles | cut -f1)"
echo ""

# Step 6: Show statistics for each layer
echo "Step 6: Layer statistics..."
echo ""

for layer in states townships sections intersected; do
    echo "=== ${layer} Statistics ==="
    if command -v sqlite3 &> /dev/null; then
        echo "Tile count by zoom level:"
        sqlite3 "${layer}.mbtiles" "SELECT 
            zoom_level, 
            COUNT(*) as tiles,
            ROUND(AVG(LENGTH(tile_data))/1024.0, 2) as avg_kb,
            ROUND(MAX(LENGTH(tile_data))/1024.0, 2) as max_kb
        FROM tiles 
        GROUP BY zoom_level 
        ORDER BY zoom_level;" | head -20
    fi
    echo ""
done

# Step 7: Optional S3 upload
if [ "$UPLOAD_TO_S3" == "--upload-to-s3" ]; then
    echo "Step 7: Uploading all layers to S3..."
    S3_BUCKET="s3://blm-plss-tiles-production-221082193991/layers"
    TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
    METADATA="build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ),builder=local,build-id=${TIMESTAMP}"
    
    for layer in states townships sections intersected; do
        echo "Uploading ${layer}..."
        aws s3 cp "${layer}.mbtiles" "${S3_BUCKET}/${layer}.mbtiles" --metadata "${METADATA}" --profile detectormaps
        aws s3 cp "${layer}.pmtiles" "${S3_BUCKET}/${layer}.pmtiles" --metadata "${METADATA}" --profile detectormaps
    done
    echo "Upload complete!"
else
    echo "Step 7: Upload to S3"
    echo "To upload these tiles to S3, run:"
    echo "  $0 --upload-to-s3"
    echo ""
fi

# Step 8: Summary
echo ""
echo "=== Build Complete ==="
echo ""
echo "Output files in: $(pwd)"
echo ""
ls -lh *.mbtiles *.pmtiles 2>/dev/null | awk '{print $9, "(" $5 ")"}'
echo ""
echo "Layer specifications:"
echo "  - states.{mbtiles,pmtiles}: z0-z6 (56 features)"
echo "  - townships.{mbtiles,pmtiles}: z8-z14 (85,896 features)"
echo "  - sections.{mbtiles,pmtiles}: z10-z14 (2,776,408 features)"
echo "  - intersected.{mbtiles,pmtiles}: z12-z14 (27,338,029 features)"
echo ""
echo "Total MBTiles size: $(du -sh . | cut -f1)"
