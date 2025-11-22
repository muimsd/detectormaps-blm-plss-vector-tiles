# BLM PLSS Vector Tiles Server

This project downloads cadastral data from the BLM National Public Land Survey System (PLSS) CadNSDI MapServer, converts it to vector tiles (MBTiles format), and deploys a serverless tile server on AWS using Lambda and CloudFront.

## Features

- **4 Data Layers**: State Boundaries, PLSS Township, PLSS Section, and PLSS Intersected
- **Vector Tiles**: Efficient Mapbox Vector Tile (MVT) format served as Protocol Buffers
- **Serverless Architecture**: AWS Lambda for tile serving, S3 for storage
- **Global CDN**: CloudFront distribution for fast worldwide access
- **TileJSON Support**: Standard metadata endpoint for mapping libraries
- **Infrastructure as Code**: Complete Terraform configuration

## Architecture

```
┌─────────────┐
│   Client    │
│ (Web Map)   │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│   CloudFront    │ (CDN Cache)
│  Distribution   │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Lambda URL     │ (Tile Server)
│   Function      │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│   S3 Bucket     │ (MBTiles Storage)
│ blm-plss-tiles  │
└─────────────────┘
```

## Prerequisites

### Local Development
- Python 3.9+
- [Tippecanoe](https://github.com/felt/tippecanoe) - for converting GeoJSON to MBTiles
  ```bash
  # macOS
  brew install tippecanoe
  
  # Linux
  git clone https://github.com/felt/tippecanoe.git
  cd tippecanoe
  make -j
  sudo make install
  ```

### AWS Deployment
- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform >= 1.0

## Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd blm-plss-vector-tiles
   ```

2. **Install Python dependencies**
   ```bash
   pip install -r requirements.txt
   ```

## Usage

### Step 1: Download and Convert Data

Run the download script to fetch GeoJSON from all 4 layers and convert to MBTiles:

```bash
python download_and_convert.py
```

This will:
- Download all features from each layer (with pagination)
- Save individual GeoJSON files to `data/` directory
- Create a single `blm-plss-cadastral.mbtiles` file with 4 source layers

**Note**: The download may take significant time depending on the data size.

### Step 2: Deploy to AWS with Terraform

Initialize Terraform:
```bash
cd terraform
terraform init
```

Review the deployment plan:
```bash
terraform plan
```

Deploy the infrastructure:
```bash
terraform apply
```

Type `yes` when prompted to confirm.

### Step 3: Access Your Tiles

After deployment, Terraform will output several URLs:

```
cloudfront_url = "https://d111111abcdef8.cloudfront.net"
metadata_url = "https://d111111abcdef8.cloudfront.net/metadata.json"
tile_url_template = "https://d111111abcdef8.cloudfront.net/{z}/{x}/{y}.pbf"
```

## Using the Tiles

### Mapbox GL JS

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>BLM PLSS Tiles</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src='https://api.mapbox.com/mapbox-gl-js/v3.0.0/mapbox-gl.js'></script>
    <link href='https://api.mapbox.com/mapbox-gl-js/v3.0.0/mapbox-gl.css' rel='stylesheet' />
    <style>
        body { margin: 0; padding: 0; }
        #map { position: absolute; top: 0; bottom: 0; width: 100%; }
    </style>
</head>
<body>
<div id="map"></div>
<script>
    const map = new mapboxgl.Map({
        container: 'map',
        style: {
            version: 8,
            sources: {
                'plss': {
                    type: 'vector',
                    tiles: ['https://YOUR-CLOUDFRONT-DOMAIN/{z}/{x}/{y}.pbf'],
                    minzoom: 0,
                    maxzoom: 14
                }
            },
            layers: [
                {
                    'id': 'state-boundaries',
                    'type': 'line',
                    'source': 'plss',
                    'source-layer': 'state_boundaries',
                    'paint': {
                        'line-color': '#000000',
                        'line-width': 2
                    }
                },
                {
                    'id': 'townships',
                    'type': 'line',
                    'source': 'plss',
                    'source-layer': 'plss_township',
                    'paint': {
                        'line-color': '#0066cc',
                        'line-width': 1
                    }
                },
                {
                    'id': 'sections',
                    'type': 'line',
                    'source': 'plss',
                    'source-layer': 'plss_section',
                    'paint': {
                        'line-color': '#00cc66',
                        'line-width': 0.5
                    }
                }
            ]
        },
        center: [-98.5795, 39.8283],
        zoom: 4
    });
</script>
</body>
</html>
```

### OpenLayers

```javascript
import VectorTileLayer from 'ol/layer/VectorTile';
import VectorTileSource from 'ol/source/VectorTile';
import MVT from 'ol/format/MVT';

const layer = new VectorTileLayer({
  source: new VectorTileSource({
    format: new MVT(),
    url: 'https://YOUR-CLOUDFRONT-DOMAIN/{z}/{x}/{y}.pbf'
  })
});
```

## API Endpoints

### Get Vector Tile
```
GET /{z}/{x}/{y}.pbf
```
Returns a Protocol Buffer encoded vector tile.

**Response Headers**:
- `Content-Type: application/x-protobuf`
- `Content-Encoding: gzip`
- `Cache-Control: public, max-age=2592000`

### Get Metadata (TileJSON)
```
GET /metadata.json
```
Returns TileJSON metadata describing the tileset.

**Response Example**:
```json
{
  "tilejson": "3.0.0",
  "name": "BLM PLSS CadNSDI",
  "description": "BLM National Public Land Survey System",
  "format": "pbf",
  "minzoom": 0,
  "maxzoom": 14,
  "bounds": [-180, -85.0511, 180, 85.0511],
  "tiles": ["https://YOUR-DOMAIN/{z}/{x}/{y}.pbf"],
  "vector_layers": [...]
}
```

## Data Layers

| Layer ID | Layer Name | Description | Geometry Type |
|----------|------------|-------------|---------------|
| 0 | state_boundaries | State Boundaries | Polygon |
| 1 | plss_township | PLSS Township | Polygon |
| 2 | plss_section | PLSS Section | Polygon |
| 3 | plss_intersected | PLSS Intersected | Polygon |

## Costs

### Estimated AWS Costs (Monthly)

- **Lambda**: ~$0.20 per 1M requests (with 1GB memory)
- **S3**: $0.023 per GB stored + $0.005 per 1000 GET requests
- **CloudFront**: $0.085 per GB transferred (first 10TB)

**Typical monthly cost for moderate use**: $5-20

## Configuration

### Terraform Variables

Edit `terraform/variables.tf` or create `terraform.tfvars`:

```hcl
aws_region         = "us-east-1"
environment        = "production"
project_name       = "blm-plss-tiles"
lambda_memory_size = 1024
lambda_timeout     = 30
```

### Tippecanoe Options

Modify `download_and_convert.py` to adjust tile generation:

```python
cmd = [
    "tippecanoe",
    "--maximum-zoom=14",      # Adjust max zoom
    "--minimum-zoom=0",       # Adjust min zoom
    "--drop-densest-as-needed",
    # Add more options...
]
```

## Updating Data

To update the tiles with fresh data:

1. Run the download script again:
   ```bash
   python download_and_convert.py
   ```

2. Redeploy with Terraform:
   ```bash
   cd terraform
   terraform apply
   ```

The new MBTiles file will be uploaded to S3 automatically.

## Cleanup

To remove all AWS resources:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted.

## Troubleshooting

### Lambda Timeout
If tiles are slow to load initially, increase `lambda_timeout` in `variables.tf`.

### Lambda Memory
For large MBTiles files, increase `lambda_memory_size` (default: 1024 MB).

### CloudFront Cache
To clear CloudFront cache after updating tiles:
```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR-DISTRIBUTION-ID \
  --paths "/*"
```

## License

This project is licensed under the MIT License.

## Data Source

Data sourced from:
- **BLM National Public Land Survey System (PLSS) CadNSDI**
- URL: https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer
- Provider: Bureau of Land Management (BLM)

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Support

For issues or questions, please open a GitHub issue.
