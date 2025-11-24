#!/usr/bin/env python3
"""
Extract all tiles from an MBTiles file and upload to S3 in {z}/{x}/{y}.pbf structure.

Usage:
    python extract_tiles_to_s3.py <mbtiles_file> <s3_bucket> [--prefix tiles]
"""

import sqlite3
import sys
import argparse
import boto3
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm


def get_tile_count(mbtiles_path):
    """Get total number of tiles in the MBTiles file."""
    conn = sqlite3.connect(mbtiles_path)
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM tiles")
    count = cursor.fetchone()[0]
    conn.close()
    return count


def extract_and_upload_tiles(mbtiles_path, s3_bucket, prefix="tiles", max_workers=20):
    """
    Extract tiles from MBTiles and upload to S3.
    
    Args:
        mbtiles_path: Path to the MBTiles file
        s3_bucket: S3 bucket name
        prefix: S3 key prefix (default: "tiles")
        max_workers: Number of parallel upload threads
    """
    # Connect to MBTiles database
    conn = sqlite3.connect(mbtiles_path)
    cursor = conn.cursor()
    
    # Get total tile count for progress bar
    total_tiles = get_tile_count(mbtiles_path)
    print(f"Found {total_tiles:,} tiles in {mbtiles_path}")
    
    # Initialize S3 client
    s3_client = boto3.client('s3')
    
    # Fetch all tiles
    cursor.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles")
    
    def upload_tile(tile_data):
        """Upload a single tile to S3."""
        zoom, col, row, data = tile_data
        
        # MBTiles uses TMS (bottom-left origin), convert to XYZ (top-left origin)
        # y_xyz = (2^zoom - 1) - y_tms
        y_xyz = (2 ** zoom - 1) - row
        
        # Construct S3 key: {prefix}/{z}/{x}/{y}.pbf
        s3_key = f"{prefix}/{zoom}/{col}/{y_xyz}.pbf"
        
        try:
            # Upload to S3 with appropriate content type and encoding
            s3_client.put_object(
                Bucket=s3_bucket,
                Key=s3_key,
                Body=data,
                ContentType='application/x-protobuf',
                ContentEncoding='gzip',
                CacheControl='public, max-age=31536000',  # 1 year
            )
            return True
        except Exception as e:
            print(f"Error uploading {s3_key}: {e}", file=sys.stderr)
            return False
    
    # Upload tiles in parallel with progress bar
    uploaded = 0
    failed = 0
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = []
        
        # Submit all upload tasks
        for tile_data in cursor:
            future = executor.submit(upload_tile, tile_data)
            futures.append(future)
        
        # Process completed uploads with progress bar
        with tqdm(total=total_tiles, desc="Uploading tiles", unit="tiles") as pbar:
            for future in as_completed(futures):
                if future.result():
                    uploaded += 1
                else:
                    failed += 1
                pbar.update(1)
    
    conn.close()
    
    print(f"\nUpload complete!")
    print(f"  Uploaded: {uploaded:,} tiles")
    print(f"  Failed: {failed:,} tiles")
    
    return uploaded, failed


def main():
    parser = argparse.ArgumentParser(
        description='Extract tiles from MBTiles file and upload to S3'
    )
    parser.add_argument('mbtiles_file', help='Path to MBTiles file')
    parser.add_argument('s3_bucket', help='S3 bucket name')
    parser.add_argument('--prefix', default='tiles', help='S3 key prefix (default: tiles)')
    parser.add_argument('--workers', type=int, default=20, help='Number of parallel upload threads (default: 20)')
    parser.add_argument('--profile', help='AWS profile name')
    
    args = parser.parse_args()
    
    # Verify MBTiles file exists
    if not Path(args.mbtiles_file).exists():
        print(f"Error: MBTiles file not found: {args.mbtiles_file}", file=sys.stderr)
        sys.exit(1)
    
    # Set AWS profile if provided
    if args.profile:
        import os
        os.environ['AWS_PROFILE'] = args.profile
    
    # Extract and upload tiles
    uploaded, failed = extract_and_upload_tiles(
        args.mbtiles_file,
        args.s3_bucket,
        prefix=args.prefix,
        max_workers=args.workers
    )
    
    if failed > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
