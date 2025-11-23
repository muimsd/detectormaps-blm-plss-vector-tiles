"""
AWS Lambda function to serve vector tiles from MBTiles on EFS.
"""

import json
import os
import sqlite3
import base64
from urllib.parse import unquote

# MBTiles path on EFS
MBTILES_PATH = os.environ.get('MBTILES_PATH', '/mnt/efs/blm-plss-cadastral.mbtiles')

# Cache the database connection
_db_connection = None


def get_db_connection():
    """Get or create database connection."""
    global _db_connection
    if _db_connection is None:
        if not os.path.exists(MBTILES_PATH):
            print(f"ERROR: MBTiles file not found at {MBTILES_PATH}")
            return None
        _db_connection = sqlite3.connect(MBTILES_PATH)
    return _db_connection


def get_tile(z, x, y):
    """
    Get a tile from MBTiles.
    MBTiles uses TMS scheme, so we need to flip the Y coordinate.
    """
    conn = get_db_connection()
    if not conn:
        return None
    
    # Convert XYZ to TMS
    tms_y = (2 ** z) - 1 - y
    
    cursor = conn.cursor()
    cursor.execute(
        "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?",
        (z, x, tms_y)
    )
    
    row = cursor.fetchone()
    return row[0] if row else None


def get_metadata():
    """Get metadata from MBTiles."""
    conn = get_db_connection()
    if not conn:
        return {
            "name": "BLM PLSS CadNSDI",
            "description": "BLM National Public Land Survey System",
            "format": "pbf",
            "minzoom": "0",
            "maxzoom": "14"
        }
    
    cursor = conn.cursor()
    cursor.execute("SELECT name, value FROM metadata")
    metadata = {row[0]: row[1] for row in cursor.fetchall()}
    return metadata


def lambda_handler(event, context):
    """
    Handle Lambda requests for vector tiles.
    
    Routes:
    - GET /{z}/{x}/{y}.pbf - Get vector tile
    - GET /metadata.json - Get TileJSON metadata
    
    Note: CORS is handled by Lambda Function URL configuration, not in code.
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
            
            # Helper to parse metadata values
            def parse_metadata_value(value, default):
                if value is None:
                    return default
                try:
                    return json.loads(value)
                except (json.JSONDecodeError, TypeError):
                    return value if value else default
            
            # Build TileJSON
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
                "tiles": [
                    f"https://{event.get('headers', {}).get('host', 'example.com')}/{'{z}/{x}/{y}.pbf'}"
                ],
                "vector_layers": parse_metadata_value(metadata.get("json"), [])
            }
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
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
                            'Cache-Control': 'public, max-age=86400'
                        },
                        'body': ''
                    }
        
        # Invalid path
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json'
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
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': str(e)})
        }
