#!/usr/bin/env python3
"""
Extract tiles from MBTiles in S3 and upload as individual objects.
Designed to run in ECS with sufficient memory.
"""

import sqlite3
import boto3
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
S3_BUCKET = os.environ.get('S3_BUCKET', 'blm-plss-tiles-production-221082193991')
MBTILES_KEY = 'blm-plss-cadastral.mbtiles'
LOCAL_MBTILES = '/tmp/tiles.mbtiles'
TILES_PREFIX = 'tiles/'
MAX_WORKERS = 50  # Parallel uploads

s3_client = boto3.client('s3', region_name='us-east-1')


def download_mbtiles():
    """Download MBTiles from S3."""
    print(f"Downloading {MBTILES_KEY} from S3...")
    
    # Get file size
    response = s3_client.head_object(Bucket=S3_BUCKET, Key=MBTILES_KEY)
    total_size = response['ContentLength']
    print(f"File size: {total_size / (1024**3):.2f} GB")
    
    # Download with progress
    def progress_callback(bytes_transferred):
        percent = (bytes_transferred / total_size) * 100
        print(f"Downloaded: {percent:.1f}%", end='\r')
    
    s3_client.download_file(
        S3_BUCKET,
        MBTILES_KEY,
        LOCAL_MBTILES,
        Callback=progress_callback
    )
    print(f"\nDownload complete: {LOCAL_MBTILES}")


def upload_tile(tile_data):
    """Upload a single tile to S3."""
    z, x, y, data = tile_data
    
    # MBTiles uses TMS, convert to XYZ
    xyz_y = (2 ** z) - 1 - y
    
    s3_key = f"{TILES_PREFIX}{z}/{x}/{xyz_y}.pbf"
    
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=data,
            ContentType='application/x-protobuf',
            ContentEncoding='gzip',
            CacheControl='public, max-age=31536000'
        )
        return True
    except Exception as e:
        print(f"Error uploading {s3_key}: {e}")
        return False


def extract_and_upload():
    """Extract tiles and upload to S3."""
    
    # Download if not exists
    if not os.path.exists(LOCAL_MBTILES):
        download_mbtiles()
    
    print(f"Opening {LOCAL_MBTILES}...")
    conn = sqlite3.connect(LOCAL_MBTILES)
    cursor = conn.cursor()
    
    # Get total count
    cursor.execute("SELECT COUNT(*) FROM tiles")
    total_tiles = cursor.fetchone()[0]
    print(f"Found {total_tiles:,} tiles to upload")
    
    # Upload metadata
    print("Creating metadata.json...")
    cursor.execute("SELECT name, value FROM metadata")
    metadata = {row[0]: row[1] for row in cursor.fetchall()}
    
    import json
    
    def parse_value(value, default):
        if value is None:
            return default
        try:
            return json.loads(value)
        except:
            return value if value else default
    
    tilejson = {
        "tilejson": "3.0.0",
        "name": metadata.get("name", "BLM PLSS"),
        "description": metadata.get("description", "BLM PLSS Cadastral Data"),
        "format": "pbf",
        "minzoom": int(metadata.get("minzoom", 0)),
        "maxzoom": int(metadata.get("maxzoom", 14)),
        "bounds": parse_value(metadata.get("bounds"), [-180, -85, 180, 85]),
        "center": parse_value(metadata.get("center"), [-98, 39, 4]),
        "tiles": [f"https://d38r6gz80i2tvd.cloudfront.net/{TILES_PREFIX}{{z}}/{{x}}/{{y}}.pbf"],
        "vector_layers": parse_value(metadata.get("json"), [])
    }
    
    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key="metadata.json",
        Body=json.dumps(tilejson, indent=2),
        ContentType='application/json',
        CacheControl='public, max-age=86400'
    )
    print("Metadata uploaded")
    
    # Upload tiles
    print(f"Uploading tiles...")
    cursor.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles")
    
    uploaded = 0
    failed = 0
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = []
        
        for row in cursor:
            futures.append(executor.submit(upload_tile, row))
        
        for i, future in enumerate(as_completed(futures), 1):
            if future.result():
                uploaded += 1
            else:
                failed += 1
            
            if i % 1000 == 0:
                print(f"Progress: {i}/{total_tiles} ({i/total_tiles*100:.1f}%) - Uploaded: {uploaded}, Failed: {failed}")
    
    conn.close()
    
    print(f"\nExtraction complete!")
    print(f"Uploaded: {uploaded:,}")
    print(f"Failed: {failed:,}")
    print(f"Tile URL: https://d38r6gz80i2tvd.cloudfront.net/{TILES_PREFIX}{{z}}/{{x}}/{{y}}.pbf")


if __name__ == '__main__':
    try:
        extract_and_upload()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
