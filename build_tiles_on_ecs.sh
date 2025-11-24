#!/bin/bash
set -e

echo "=== BLM PLSS Vector Tiles Builder - AWS ECS ==="
echo "Starting at: $(date)"
echo ""

# Configuration
S3_BUCKET="s3://blm-plss-tiles-production-221082193991"
DATA_DIR="/build/data"
OUTPUT_FILE="blm-plss-cadastral-optimized.mbtiles"

# Create data directory
mkdir -p "$DATA_DIR"

# Step 1: Download source GDB files from S3
echo "Step 1: Downloading source data from S3..."
aws s3 cp "${S3_BUCKET}/ilmocplss.gdb/" "${DATA_DIR}/ilmocplss.gdb/" --recursive
aws s3 cp "${S3_BUCKET}/BOC_cb_2017_US_State_500k.gdb/" "${DATA_DIR}/BOC_cb_2017_US_State_500k.gdb/" --recursive

echo "Source data downloaded. File listing:"
du -sh "${DATA_DIR}"/*
echo ""

# Step 2: Build States layer (z0-z6 only)
echo "Step 2: Building states layer (z0-z6)..."
echo "This layer provides context at low zoom levels."
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

echo "States layer complete. Size: $(du -h states.mbtiles | cut -f1)"
echo ""

# Step 3: Build Townships layer (z7-z14)
echo "Step 3: Building townships layer (z7-z14)..."
echo "85,896 features, average 93 km² per polygon."
tippecanoe \
    -o townships.mbtiles \
    -Z7 -z14 \
    --layer=townships \
    --simplification=10 \
    --maximum-tile-bytes=200000 \
    --drop-densest-as-needed \
    --detect-shared-borders \
    --force \
    "${DATA_DIR}/ilmocplss.gdb" PLSSTownship

echo "Townships layer complete. Size: $(du -h townships.mbtiles | cut -f1)"
echo ""

# Step 4: Build Sections layer (z10-z14)
echo "Step 4: Building sections layer (z10-z14)..."
echo "2,776,408 features, average 2.5 km² per polygon."
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

echo "Sections layer complete. Size: $(du -h sections.mbtiles | cut -f1)"
echo ""

# Step 5: Build Intersected parcels layer (z12-z14)
echo "Step 5: Building intersected parcels layer (z12-z14)..."
echo "27,338,029 features, average 0.26 km² per polygon."
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

echo "Intersected layer complete. Size: $(du -h intersected.mbtiles | cut -f1)"
echo ""

# Step 6: Merge all layers into single MBTiles
echo "Step 6: Merging all layers with tile-join..."
echo "This ensures each layer only appears at its designated zoom levels."
tile-join \
    -o "${OUTPUT_FILE}" \
    --no-tile-size-limit \
    --force \
    states.mbtiles \
    townships.mbtiles \
    sections.mbtiles \
    intersected.mbtiles

echo "Merge complete!"
echo ""

# Step 7: Show statistics
echo "Step 7: Final MBTiles statistics..."
echo "File size: $(du -h ${OUTPUT_FILE} | cut -f1)"
echo ""

if command -v sqlite3 &> /dev/null; then
    echo "Tile count and average size by zoom level:"
    sqlite3 "${OUTPUT_FILE}" "SELECT 
        zoom_level, 
        COUNT(*) as tiles,
        ROUND(AVG(LENGTH(tile_data))/1024.0, 2) as avg_kb,
        ROUND(MAX(LENGTH(tile_data))/1024.0, 2) as max_kb,
        ROUND(SUM(LENGTH(tile_data))/1024.0/1024.0, 2) as total_mb
    FROM tiles 
    GROUP BY zoom_level 
    ORDER BY zoom_level;"
    echo ""
fi

# Step 8: Upload to S3
echo "Step 8: Uploading optimized MBTiles to S3..."
aws s3 cp "${OUTPUT_FILE}" "${S3_BUCKET}/" \
    --metadata "build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ),builder=ecs-fargate"

echo ""
echo "=== Build Complete ==="
echo "Finished at: $(date)"
echo "Output: ${S3_BUCKET}/${OUTPUT_FILE}"
echo ""
echo "Next steps:"
echo "1. Update ECS tileserver environment variable to use: ${OUTPUT_FILE}"
echo "2. Restart ECS tileserver task to download new file"
echo "3. Test tiles at different zoom levels to verify sizes"

# Clean up temporary files
rm -f states.mbtiles townships.mbtiles sections.mbtiles intersected.mbtiles

echo ""
echo "Build container exiting successfully."
