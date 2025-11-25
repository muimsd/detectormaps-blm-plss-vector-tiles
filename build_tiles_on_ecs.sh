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

# Process layers sequentially: GeoJSON -> MBTiles -> PMTiles -> S3 upload -> cleanup
# This approach is more memory-efficient and provides clearer progress tracking
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
METADATA="build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ),builder=ecs-fargate,build-id=${TIMESTAMP}"

# ======================================================================
# Step 2: Process States layer (z0-z6)
# ======================================================================
echo ""
echo "=========================================="
echo "Processing States layer (z0-z6)"
echo "=========================================="
echo "56 state features for context at low zoom levels"

echo "Converting States GDB to GeoJSON..."
ogr2ogr -f GeoJSON -t_srs EPSG:4326 "${DATA_DIR}/states.geojson" "${DATA_DIR}/BOC_cb_2017_US_State_500k.gdb"
echo "States GeoJSON: $(du -h "${DATA_DIR}/states.geojson" | cut -f1)"

echo "Building States MBTiles..."
tippecanoe \
    -o states.mbtiles \
    -Z0 -z6 \
    --layer=states \
    --simplification=20 \
    --maximum-tile-bytes=50000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/states.geojson"
echo "States MBTiles: $(du -h states.mbtiles | cut -f1)"

echo "Converting States to PMTiles..."
pmtiles convert states.mbtiles states.pmtiles
if [ $? -eq 0 ]; then
    echo "States PMTiles: $(du -h states.pmtiles | cut -f1)"
else
    echo "ERROR: Failed to convert states.mbtiles to PMTiles"
    exit 1
fi

echo "Uploading States to S3..."
aws s3 cp "${DATA_DIR}/states.geojson" "${S3_BUCKET}/geojson/states.geojson" --metadata "${METADATA}" --no-progress
aws s3 cp states.mbtiles "${S3_BUCKET}/layers/states.mbtiles" --metadata "${METADATA}" --no-progress
aws s3 cp states.pmtiles "${S3_BUCKET}/layers/states.pmtiles" --metadata "${METADATA}" --no-progress
echo "✓ States layer complete! Cleaning up..."
rm -f "${DATA_DIR}/states.geojson" states.mbtiles

# ======================================================================
# Step 3: Process Townships layer (z8-z14)
# ======================================================================
echo ""
echo "=========================================="
echo "Processing Townships layer (z8-z14)"
echo "=========================================="
echo "85,896 features, average 93 km² per polygon (6 miles × 6 miles)"

echo "Converting Townships GDB to GeoJSON..."
ogr2ogr -f GeoJSON -t_srs EPSG:4326 "${DATA_DIR}/townships.geojson" "${DATA_DIR}/ilmocplss.gdb" PLSSTownship
echo "Townships GeoJSON: $(du -h "${DATA_DIR}/townships.geojson" | cut -f1)"

echo "Building Townships MBTiles..."
tippecanoe \
    -o townships.mbtiles \
    -Z8 -z14 \
    --layer=townships \
    --simplification=10 \
    --maximum-tile-bytes=200000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/townships.geojson"
echo "Townships MBTiles: $(du -h townships.mbtiles | cut -f1)"

echo "Converting Townships to PMTiles..."
pmtiles convert townships.mbtiles townships.pmtiles
if [ $? -eq 0 ]; then
    echo "Townships PMTiles: $(du -h townships.pmtiles | cut -f1)"
else
    echo "ERROR: Failed to convert townships.mbtiles to PMTiles"
    exit 1
fi

echo "Uploading Townships to S3..."
aws s3 cp "${DATA_DIR}/townships.geojson" "${S3_BUCKET}/geojson/townships.geojson" --metadata "${METADATA}" --no-progress
aws s3 cp townships.mbtiles "${S3_BUCKET}/layers/townships.mbtiles" --metadata "${METADATA}" --no-progress
aws s3 cp townships.pmtiles "${S3_BUCKET}/layers/townships.pmtiles" --metadata "${METADATA}" --no-progress
echo "✓ Townships layer complete! Cleaning up..."
rm -f "${DATA_DIR}/townships.geojson" townships.mbtiles

# ======================================================================
# Step 4: Process Sections layer (z10-z14)
# ======================================================================
echo ""
echo "=========================================="
echo "Processing Sections layer (z10-z14)"
echo "=========================================="
echo "2,776,408 features, average 2.5 km² per polygon (1 mile × 1 mile)"

echo "Converting Sections GDB to GeoJSON..."
ogr2ogr -f GeoJSON -t_srs EPSG:4326 "${DATA_DIR}/sections.geojson" "${DATA_DIR}/ilmocplss.gdb" PLSSFirstDivision
echo "Sections GeoJSON: $(du -h "${DATA_DIR}/sections.geojson" | cut -f1)"

echo "Building Sections MBTiles..."
tippecanoe \
    -o sections.mbtiles \
    -Z10 -z14 \
    --layer=sections \
    --simplification=5 \
    --maximum-tile-bytes=300000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/sections.geojson"
echo "Sections MBTiles: $(du -h sections.mbtiles | cut -f1)"

echo "Converting Sections to PMTiles..."
pmtiles convert sections.mbtiles sections.pmtiles
if [ $? -eq 0 ]; then
    echo "Sections PMTiles: $(du -h sections.pmtiles | cut -f1)"
else
    echo "ERROR: Failed to convert sections.mbtiles to PMTiles"
    exit 1
fi

echo "Uploading Sections to S3..."
aws s3 cp "${DATA_DIR}/sections.geojson" "${S3_BUCKET}/geojson/sections.geojson" --metadata "${METADATA}" --no-progress
aws s3 cp sections.mbtiles "${S3_BUCKET}/layers/sections.mbtiles" --metadata "${METADATA}" --no-progress
aws s3 cp sections.pmtiles "${S3_BUCKET}/layers/sections.pmtiles" --metadata "${METADATA}" --no-progress
echo "✓ Sections layer complete! Cleaning up..."
rm -f "${DATA_DIR}/sections.geojson" sections.mbtiles

# ======================================================================
# Step 5: Process Intersected parcels layer (z12-z14)
# ======================================================================
echo ""
echo "=========================================="
echo "Processing Intersected layer (z12-z14)"
echo "=========================================="
echo "27,338,029 features, average 0.26 km² per polygon (quarter sections, lots)"
echo "This is the most detailed layer and will take the longest..."

echo "Converting Intersected GDB to GeoJSON..."
ogr2ogr -f GeoJSON -t_srs EPSG:4326 "${DATA_DIR}/intersected.geojson" "${DATA_DIR}/ilmocplss.gdb" PLSSIntersected
echo "Intersected GeoJSON: $(du -h "${DATA_DIR}/intersected.geojson" | cut -f1)"

echo "Building Intersected MBTiles..."
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
    "${DATA_DIR}/intersected.geojson"
echo "Intersected MBTiles: $(du -h intersected.mbtiles | cut -f1)"

echo "Converting Intersected to PMTiles..."
pmtiles convert intersected.mbtiles intersected.pmtiles
if [ $? -eq 0 ]; then
    echo "Intersected PMTiles: $(du -h intersected.pmtiles | cut -f1)"
else
    echo "ERROR: Failed to convert intersected.mbtiles to PMTiles"
    exit 1
fi

echo "Uploading Intersected to S3..."
aws s3 cp "${DATA_DIR}/intersected.geojson" "${S3_BUCKET}/geojson/intersected.geojson" --metadata "${METADATA}" --no-progress
aws s3 cp intersected.mbtiles "${S3_BUCKET}/layers/intersected.mbtiles" --metadata "${METADATA}" --no-progress
aws s3 cp intersected.pmtiles "${S3_BUCKET}/layers/intersected.pmtiles" --metadata "${METADATA}" --no-progress
echo "✓ Intersected layer complete! Cleaning up..."
rm -f "${DATA_DIR}/intersected.geojson" intersected.mbtiles

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
