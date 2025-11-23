#!/bin/bash
set -e

echo "Downloading MBTiles from S3..."
aws s3 cp s3://${S3_BUCKET}/${MBTILES_KEY} /data/tiles.mbtiles --region us-east-1

echo "Starting tile server..."
tileserver-gl-light --port 8080 --public_url ${PUBLIC_URL:-http://localhost:8080} /data/tiles.mbtiles
