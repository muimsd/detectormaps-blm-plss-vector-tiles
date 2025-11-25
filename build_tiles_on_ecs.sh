#!/bin/bash
set -e

echo "=== BLM PLSS Vector Tiles Builder - AWS ECS ==="
echo "Starting at: $(date)"
echo ""

# Configuration
S3_BUCKET="s3://blm-plss-tiles-production-221082193991"
DATA_DIR="/build/data"
OUTPUT_FILE="blm-plss-cadastral-optimized.mbtiles"
GDB_DOWNLOAD_URL="https://www.arcgis.com/sharing/rest/content/items/283939812bc34c11bad695a1c8152faf/data"

# Create data directory
mkdir -p "$DATA_DIR"

# Step 1: Download and extract source GDB files
echo "Step 1: Downloading source data from ArcGIS..."
echo "URL: $GDB_DOWNLOAD_URL"
curl -L "$GDB_DOWNLOAD_URL" -o /tmp/plss_data.zip

echo "Extracting GDB files..."
unzip -q /tmp/plss_data.zip -d "$DATA_DIR"
rm /tmp/plss_data.zip

echo "Source data extracted. Contents:"
ls -lh "$DATA_DIR"
du -sh "${DATA_DIR}"/*
echo ""

# Step 2: Build States layer (z0-z6 only)
echo "Step 2: Building states layer (z0-z6)..."
echo "56 state features for context at low zoom levels."
tippecanoe \
    -o states.mbtiles \
    -Z0 -z6 \
    --layer=states \
    --simplification=20 \
    --maximum-tile-bytes=50000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/BOC_cb_2017_US_State_500k.gdb"

echo "States MBTiles complete. Size: $(du -h states.mbtiles | cut -f1)"

# Convert to PMTiles
echo "Converting states to PMTiles..."
pmtiles convert states.mbtiles states.pmtiles
echo "States PMTiles complete. Size: $(du -h states.pmtiles | cut -f1)"
echo ""

# Step 3: Build Townships layer (z8-z14)
echo "Step 3: Building townships layer (z8-z14)..."
echo "85,896 features, average 93 km² per polygon (6 miles × 6 miles)."
tippecanoe \
    -o townships.mbtiles \
    -Z8 -z14 \
    --layer=townships \
    --simplification=10 \
    --maximum-tile-bytes=200000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/ilmocplss.gdb" PLSSTownship

echo "Townships MBTiles complete. Size: $(du -h townships.mbtiles | cut -f1)"

# Convert to PMTiles
echo "Converting townships to PMTiles..."
pmtiles convert townships.mbtiles townships.pmtiles
echo "Townships PMTiles complete. Size: $(du -h townships.pmtiles | cut -f1)"
echo ""

# Step 4: Build Sections layer (z10-z14)
echo "Step 4: Building sections layer (z10-z14)..."
echo "2,776,408 features, average 2.5 km² per polygon (1 mile × 1 mile)."
tippecanoe \
    -o sections.mbtiles \
    -Z10 -z14 \
    --layer=sections \
    --simplification=5 \
    --maximum-tile-bytes=300000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/ilmocplss.gdb" PLSSFirstDivision

echo "Sections MBTiles complete. Size: $(du -h sections.mbtiles | cut -f1)"

# Convert to PMTiles
echo "Converting sections to PMTiles..."
pmtiles convert sections.mbtiles sections.pmtiles
echo "Sections PMTiles complete. Size: $(du -h sections.pmtiles | cut -f1)"
echo ""

# Step 5: Build Intersected parcels layer (z12-z14)
echo "Step 5: Building intersected parcels layer (z12-z14)..."
echo "27,338,029 features, average 0.26 km² per polygon (quarter sections, lots)."
echo "This is the most detailed layer and will take the longest..."
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
    "${DATA_DIR}/ilmocplss.gdb" PLSSIntersected

echo "Intersected MBTiles complete. Size: $(du -h intersected.mbtiles | cut -f1)"

# Convert to PMTiles
echo "Converting intersected to PMTiles..."
pmtiles convert intersected.mbtiles intersected.pmtiles
echo "Intersected PMTiles complete. Size: $(du -h intersected.pmtiles | cut -f1)"
echo ""

# Step 6: Show statistics for each layer
echo "Step 6: Layer statistics..."
echo ""

for layer in states townships sections intersected; do
    echo "=== ${layer} Statistics ==="
    echo "MBTiles size: $(du -h ${layer}.mbtiles | cut -f1)"
    echo "PMTiles size: $(du -h ${layer}.pmtiles | cut -f1)"
    
    if command -v sqlite3 &> /dev/null; then
        echo "Tile count by zoom level:"
        sqlite3 "${layer}.mbtiles" "SELECT 
            zoom_level, 
            COUNT(*) as tiles,
            ROUND(AVG(LENGTH(tile_data))/1024.0, 2) as avg_kb,
            ROUND(MAX(LENGTH(tile_data))/1024.0, 2) as max_kb
        FROM tiles 
        GROUP BY zoom_level 
        ORDER BY zoom_level;"
    fi
    echo ""
done

# Step 7: Upload all layers to S3
echo "Step 7: Uploading all layers (MBTiles and PMTiles) to S3..."
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
METADATA="build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ),builder=ecs-fargate,build-id=${TIMESTAMP}"

for layer in states townships sections intersected; do
    echo "Uploading ${layer}..."
    aws s3 cp "${layer}.mbtiles" "${S3_BUCKET}/layers/${layer}.mbtiles" --metadata "${METADATA}"
    aws s3 cp "${layer}.pmtiles" "${S3_BUCKET}/layers/${layer}.pmtiles" --metadata "${METADATA}"
done

echo ""
echo "=== Build Complete ==="
echo "Finished at: $(date)"
echo "Build ID: ${TIMESTAMP}"
echo ""
echo "Outputs uploaded to S3:"
echo "  ${S3_BUCKET}/layers/states.mbtiles (z0-z6)"
echo "  ${S3_BUCKET}/layers/states.pmtiles (z0-z6)"
echo "  ${S3_BUCKET}/layers/townships.mbtiles (z8-z14)"
echo "  ${S3_BUCKET}/layers/townships.pmtiles (z8-z14)"
echo "  ${S3_BUCKET}/layers/sections.mbtiles (z10-z14)"
echo "  ${S3_BUCKET}/layers/sections.pmtiles (z10-z14)"
echo "  ${S3_BUCKET}/layers/intersected.mbtiles (z12-z14)"
echo "  ${S3_BUCKET}/layers/intersected.pmtiles (z12-z14)"
echo ""
echo "Each layer is available in both MBTiles and PMTiles format."
echo "PMTiles can be served directly from S3 without a server."

# Clean up temporary MBTiles files (keep PMTiles for potential reuse)
rm -f states.mbtiles townships.mbtiles sections.mbtiles intersected.mbtiles

echo ""
echo "Build container exiting successfully."
