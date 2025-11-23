#!/usr/bin/env python3
"""
Extract tiles from MBTiles and upload to S3 as individual objects.
This allows Lambda to serve tiles without downloading the entire MBTiles file.
"""

import sqlite3
import boto3
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

# Configuration
MBTILES_PATH = "blm-plss-cadastral.mbtiles"
S3_BUCKET = "blm-plss-tiles-production-221082193991"
S3_PREFIX = "tiles/"  # Store tiles in tiles/ prefix
MAX_WORKERS = 20  # Parallel uploads

s3_client = boto3.client('s3', region_name='us-east-1')


def upload_tile(tile_data):
    """Upload a single tile to S3."""
    z, x, y, data = tile_data
    
    # MBTiles uses TMS, so flip Y for XYZ
    xyz_y = (2 ** z) - 1 - y
    
    # S3 key: tiles/z/x/y.pbf
    s3_key = f"{S3_PREFIX}{z}/{x}/{xyz_y}.pbf"
    
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=data,
            ContentType='application/x-protobuf',
            ContentEncoding='gzip',
            CacheControl='public, max-age=31536000'  # 1 year cache
        )
        return True
    except Exception as e:
        print(f"Error uploading {s3_key}: {e}")
        return False


def extract_and_upload():
    """Extract all tiles from MBTiles and upload to S3."""
    
    if not os.path.exists(MBTILES_PATH):
        print(f"Error: {MBTILES_PATH} not found")
        print("Please run this script from the directory containing the MBTiles file")
        return
    
    print(f"Opening {MBTILES_PATH}...")
    conn = sqlite3.connect(MBTILES_PATH)
    cursor = conn.cursor()
    
    # Get total tile count
    cursor.execute("SELECT COUNT(*) FROM tiles")
    total_tiles = cursor.fetchone()[0]
    print(f"Found {total_tiles:,} tiles to upload")
    
    # Get metadata for TileJSON
    cursor.execute("SELECT name, value FROM metadata")
    metadata = {row[0]: row[1] for row in cursor.fetchall()}
    
    # Upload metadata.json
    print("Uploading metadata...")
    import json
    
    # Helper to parse metadata values
    def parse_metadata_value(value, default):
        if value is None:
            return default
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return value if value else default
    
    tilejson = {
        "tilejson": "3.0.0",
        "name": metadata.get("name", "BLM PLSS CadNSDI"),
        "description": metadata.get("description", "BLM National Public Land Survey System"),
        "version": metadata.get("version", "1.0.0"),
        "format": metadata.get("format", "pbf"),
        "minzoom": int(metadata.get("minzoom", 0)),
        "maxzoom": int(metadata.get("maxzoom", 14)),
        "bounds": parse_metadata_value(metadata.get("bounds"), [-180, -85.0511, 180, 85.0511]),
        "center": parse_metadata_value(metadata.get("center"), [-98.5795, 39.8283, 4]),
        "tiles": [f"https://d38r6gz80i2tvd.cloudfront.net/{S3_PREFIX}{{z}}/{{x}}/{{y}}.pbf"],
        "vector_layers": parse_metadata_value(metadata.get("json"), [])
    }
    
    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key="metadata.json",
        Body=json.dumps(tilejson, indent=2),
        ContentType='application/json',
        CacheControl='public, max-age=86400'
    )
    
    # Fetch all tiles
    cursor.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles")
    
    # Upload tiles in parallel
    print(f"Uploading tiles to s3://{S3_BUCKET}/{S3_PREFIX}...")
    
    uploaded = 0
    failed = 0
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = []
        
        # Submit all upload tasks
        for row in cursor:
            futures.append(executor.submit(upload_tile, row))
        
        # Track progress
        with tqdm(total=total_tiles, unit='tiles') as pbar:
            for future in as_completed(futures):
                if future.result():
                    uploaded += 1
                else:
                    failed += 1
                pbar.update(1)
                pbar.set_postfix({'uploaded': uploaded, 'failed': failed})
    
    conn.close()
    
    print(f"\nUpload complete!")
    print(f"Uploaded: {uploaded:,} tiles")
    print(f"Failed: {failed:,} tiles")
    print(f"\nTiles URL template: https://d38r6gz80i2tvd.cloudfront.net/{S3_PREFIX}{{z}}/{{x}}/{{y}}.pbf")
    print(f"Metadata URL: https://d38r6gz80i2tvd.cloudfront.net/metadata.json")


if __name__ == '__main__':
    extract_and_upload()
