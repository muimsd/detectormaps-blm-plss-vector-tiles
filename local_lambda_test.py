"""Local test harness for tile_server.lambda_handler.
Tests with the actual MBTiles file if available, or creates minimal test data.
"""
import os
import sqlite3
import json
from types import SimpleNamespace
from pathlib import Path

# Check for actual MBTiles file
ACTUAL_MBTILES = Path('blm-plss-cadastral.mbtiles')
MBTILES_PATH = '/tmp/tiles.mbtiles'

if ACTUAL_MBTILES.exists():
    print(f"Using actual MBTiles file: {ACTUAL_MBTILES}")
    print(f"File size: {ACTUAL_MBTILES.stat().st_size / (1024**2):.2f} MB")
    # Copy to /tmp for lambda to use
    import shutil
    shutil.copy(ACTUAL_MBTILES, MBTILES_PATH)
else:
    print("Creating minimal test MBTiles...")
    # Ensure /tmp/tiles.mbtiles exists with minimal schema
    if not os.path.exists(MBTILES_PATH):
        conn = sqlite3.connect(MBTILES_PATH)
        cur = conn.cursor()
        cur.execute('CREATE TABLE metadata (name TEXT, value TEXT)')
        cur.execute('CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)')
        # Insert minimal metadata
        metadata = {
            'name': 'Local Test Tiles',
            'description': 'Test MBTiles for local lambda harness',
            'version': '1.0.0',
            'format': 'pbf',
            'minzoom': '0',
            'maxzoom': '0',
            'bounds': json.dumps([-180, -85.0511, 180, 85.0511]),
            'center': json.dumps([-98.5795, 39.8283, 4]),
            'json': json.dumps([])
        }
        for k, v in metadata.items():
            cur.execute('INSERT INTO metadata (name, value) VALUES (?, ?)', (k, v))
        conn.commit()
        conn.close()

# Environment variables expected by lambda
os.environ['MBTILES_BUCKET'] = 'dummy-bucket'
os.environ['MBTILES_KEY'] = 'dummy.mbtiles'
os.environ['SKIP_S3_DOWNLOAD'] = '1'

# Load tile_server module manually since directory name 'lambda' conflicts with keyword
import importlib.util
import pathlib
module_path = pathlib.Path(__file__).parent / 'lambda' / 'tile_server.py'
spec = importlib.util.spec_from_file_location('tile_server_mod', str(module_path))
if spec is None or spec.loader is None:
    raise RuntimeError('Failed to create spec for tile_server.py')
tile_server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tile_server)

# Simulate API Gateway HTTP API event for metadata.json
event = {
    'rawPath': '/metadata.json',
    'headers': {
        'host': 'localhost'
    }
}

response = tile_server.lambda_handler(event, SimpleNamespace())
print('\n=== Metadata Endpoint Test ===')
print('Status:', response['statusCode'])
print('Headers:', response['headers'])
body = json.loads(response['body'])
print('TileJSON name:', body.get('name'))
print('TileJSON format:', body.get('format'))
print('TileJSON bounds:', body.get('bounds'))
print('TileJSON zoom range:', f"{body.get('minzoom')}-{body.get('maxzoom')}")
print('Vector layers:', len(body.get('vector_layers', [])))
print('\n✓ Local lambda test passed!')
