"""
AWS Lambda function to serve vector tiles from MBTiles stored in S3.
"""

import json
import os
import sqlite3
import boto3
import base64
from urllib.parse import unquote

s3_client = boto3.client('s3')

BUCKET_NAME = os.environ['MBTILES_BUCKET']
MBTILES_KEY = os.environ['MBTILES_KEY']
LOCAL_MBTILES = '/tmp/tiles.mbtiles'


def download_mbtiles():
    """Download MBTiles from S3 if not already cached."""
    if not os.path.exists(LOCAL_MBTILES):
        print(f"Downloading MBTiles from s3://{BUCKET_NAME}/{MBTILES_KEY}")
        s3_client.download_file(BUCKET_NAME, MBTILES_KEY, LOCAL_MBTILES)
        print("Download complete")
    return LOCAL_MBTILES


def get_tile(z, x, y):
    """Get a tile from the MBTiles database."""
    # Download MBTiles if needed
    mbtiles_path = download_mbtiles()
    
    # Connect to database
    conn = sqlite3.connect(mbtiles_path)
    cursor = conn.cursor()
    
    # MBTiles uses TMS tile coordinates (Y is flipped)
    tms_y = (2 ** z) - 1 - y
    
    # Query for tile
    cursor.execute(
        "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
        (z, x, tms_y)
    )
    
    result = cursor.fetchone()
    conn.close()
    
    if result:
        return result[0]
    return None


def get_metadata():
    """Get metadata from MBTiles."""
    mbtiles_path = download_mbtiles()
    
    conn = sqlite3.connect(mbtiles_path)
    cursor = conn.cursor()
    
    cursor.execute("SELECT name, value FROM metadata")
    metadata = {row[0]: row[1] for row in cursor.fetchall()}
    
    conn.close()
    return metadata


def lambda_handler(event, context):
    """
    Handle Lambda requests for vector tiles.
    
    Routes:
    - GET /{z}/{x}/{y}.pbf - Get vector tile
    - GET /metadata.json - Get TileJSON metadata
    """
    
    try:
        # Handle direct invocation or API Gateway
        if 'rawPath' in event:
            path = event['rawPath']
        elif 'path' in event:
            path = event['path']
        else:
            path = event.get('resource', '')
        
        path = unquote(path).strip('/')
        
        # Metadata endpoint
        if path == 'metadata.json' or path == 'metadata':
            metadata = get_metadata()
            
            # Build TileJSON
            tilejson = {
                "tilejson": "3.0.0",
                "name": metadata.get("name", "BLM PLSS CadNSDI"),
                "description": metadata.get("description", "BLM National Public Land Survey System"),
                "version": metadata.get("version", "1.0.0"),
                "format": metadata.get("format", "pbf"),
                "minzoom": int(metadata.get("minzoom", 0)),
                "maxzoom": int(metadata.get("maxzoom", 14)),
                "bounds": json.loads(metadata.get("bounds", "[-180, -85.0511, 180, 85.0511]")),
                "center": json.loads(metadata.get("center", "[-98.5795, 39.8283, 4]")),
                "tiles": [
                    f"https://{event.get('headers', {}).get('host', 'example.com')}/{'{z}/{x}/{y}.pbf'}"
                ],
                "vector_layers": json.loads(metadata.get("json", "[]"))
            }
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Cache-Control': 'public, max-age=86400'
                },
                'body': json.dumps(tilejson)
            }
        
        # Tile endpoint
        if '.pbf' in path or '.mvt' in path:
            # Parse z/x/y from path
            parts = path.replace('.pbf', '').replace('.mvt', '').split('/')
            
            if len(parts) >= 3:
                z = int(parts[-3])
                x = int(parts[-2])
                y = int(parts[-1])
                
                tile_data = get_tile(z, x, y)
                
                if tile_data:
                    return {
                        'statusCode': 200,
                        'headers': {
                            'Content-Type': 'application/x-protobuf',
                            'Content-Encoding': 'gzip',
                            'Access-Control-Allow-Origin': '*',
                            'Cache-Control': 'public, max-age=2592000'  # 30 days
                        },
                        'body': base64.b64encode(tile_data).decode('utf-8'),
                        'isBase64Encoded': True
                    }
                else:
                    # No tile at this location
                    return {
                        'statusCode': 204,
                        'headers': {
                            'Access-Control-Allow-Origin': '*',
                            'Cache-Control': 'public, max-age=86400'
                        },
                        'body': ''
                    }
        
        # Invalid path
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Not found'})
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
