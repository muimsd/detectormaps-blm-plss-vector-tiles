#!/bin/bash
set -e

echo "=== BLM PLSS GDB to MBTiles Conversion on ECS ==="
echo "Starting conversion process..."

# Run the GDB conversion
python3 convert_gdb_in_ecs.py

echo "✓ Conversion and upload complete!"
