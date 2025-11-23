#!/usr/bin/env python3
"""
Convert MBTiles to PMTiles format for cloud-optimized tile serving.
PMTiles can be served directly from S3 without Lambda or tile extraction.
"""

import subprocess
import os
import boto3

# Configuration
MBTILES_FILE = "blm-plss-cadastral.mbtiles"
PMTILES_FILE = "blm-plss-cadastral.pmtiles"
S3_BUCKET = "blm-plss-tiles-production-221082193991"
S3_KEY = "blm-plss-cadastral.pmtiles"

s3_client = boto3.client('s3', region_name='us-east-1')


def download_mbtiles_from_s3():
    """Download MBTiles from S3 if not exists locally."""
    if os.path.exists(MBTILES_FILE):
        print(f"{MBTILES_FILE} already exists locally")
        return
    
    print(f"Downloading {MBTILES_FILE} from S3...")
    s3_client.download_file(S3_BUCKET, MBTILES_FILE, MBTILES_FILE)
    print("Download complete")


def convert_to_pmtiles():
    """Convert MBTiles to PMTiles using pmtiles CLI."""
    print(f"Converting {MBTILES_FILE} to {PMTILES_FILE}...")
    
    # Check if pmtiles is installed
    try:
        subprocess.run(['pmtiles', '--version'], check=True, capture_output=True)
    except FileNotFoundError:
        print("ERROR: pmtiles CLI not found")
        print("Install it with: npm install -g pmtiles")
        print("Or download from: https://github.com/protomaps/go-pmtiles/releases")
        return False
    
    # Convert
    cmd = ['pmtiles', 'convert', MBTILES_FILE, PMTILES_FILE]
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print(f"Conversion complete: {PMTILES_FILE}")
        return True
    else:
        print(f"Conversion failed: {result.stderr}")
        return False


def upload_to_s3():
    """Upload PMTiles to S3."""
    print(f"Uploading {PMTILES_FILE} to s3://{S3_BUCKET}/{S3_KEY}...")
    
    file_size = os.path.getsize(PMTILES_FILE)
    print(f"File size: {file_size / (1024**3):.2f} GB")
    
    def progress_callback(bytes_transferred):
        percent = (bytes_transferred / file_size) * 100
        print(f"Uploaded: {percent:.1f}%", end='\r')
    
    s3_client.upload_file(
        PMTILES_FILE,
        S3_BUCKET,
        S3_KEY,
        Callback=progress_callback,
        ExtraArgs={
            'ContentType': 'application/octet-stream',
            'CacheControl': 'public, max-age=31536000'
        }
    )
    
    print(f"\nUpload complete!")
    print(f"PMTiles URL: https://d38r6gz80i2tvd.cloudfront.net/{S3_KEY}")


def main():
    """Main conversion workflow."""
    print("=== MBTiles to PMTiles Conversion ===\n")
    
    # Step 1: Download MBTiles if needed
    # download_mbtiles_from_s3()  # Uncomment if you need to download
    
    # Step 2: Convert
    if not convert_to_pmtiles():
        return
    
    # Step 3: Upload
    upload_to_s3()
    
    print("\n=== Conversion Complete ===")
    print(f"PMTiles can now be served directly from S3!")
    print(f"URL: https://d38r6gz80i2tvd.cloudfront.net/{S3_KEY}")


if __name__ == '__main__':
    main()
