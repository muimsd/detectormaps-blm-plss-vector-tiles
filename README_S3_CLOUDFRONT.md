# BLM PLSS Vector Tiles - S3 + CloudFront Architecture

This project serves BLM PLSS (Public Land Survey System) vector tiles directly from S3 via CloudFront.

## Architecture

```
S3 Bucket (tiles/{z}/{x}/{y}.pbf) → CloudFront (HTTPS + Caching) → Users
```

**Benefits:**
- ✅ No compute costs (no ECS/Fargate)
- ✅ Fastest response times (edge caching)
- ✅ Cheapest solution (~$2-10/month for S3 + CloudFront)
- ✅ Unlimited scalability
- ✅ HTTPS with CORS support

**Cost Estimate:**
- S3 storage (tiles): ~$5-15/month (depends on total tile count)
- CloudFront data transfer: ~$1-20/month (depends on traffic)
- **Total: ~$6-35/month** (vs ~$170/month for ECS Fargate)

## Setup Instructions

### Prerequisites

```bash
# Install Python dependencies
pip install -r requirements.txt

# Download MBTiles file to local machine (if not already done)
aws s3 cp s3://blm-plss-tiles-production-221082193991/blm-plss-cadastral.mbtiles . \
  --profile detectormaps --region us-east-1
```

### Step 1: Extract Tiles from MBTiles and Upload to S3

```bash
# Extract all tiles and upload to S3 (this will take some time)
python extract_tiles_to_s3.py \
  blm-plss-cadastral.mbtiles \
  blm-plss-tiles-production-221082193991 \
  --prefix tiles \
  --workers 50 \
  --profile detectormaps

# Example output:
# Found 1,234,567 tiles in blm-plss-cadastral.mbtiles
# Uploading tiles: 100%|████████████| 1234567/1234567 [15:23<00:00, 1337.89tiles/s]
#
# Upload complete!
#   Uploaded: 1,234,567 tiles
#   Failed: 0 tiles
```

**Note:** This process will:
- Read all tiles from the SQLite MBTiles file
- Convert TMS coordinates to XYZ (standard web mercator)
- Upload each tile to S3 as `tiles/{z}/{x}/{y}.pbf`
- Set proper content-type, encoding, and cache headers
- Use 50 parallel threads for faster upload (adjust `--workers` as needed)

**Time estimate:** For ~1-2 million tiles, expect 15-30 minutes with 50 workers.

### Step 2: Update Infrastructure with Terraform

```bash
cd terraform

# Review changes (CloudFront origin change from ALB to S3)
terraform plan

# Apply changes
terraform apply -auto-approve
```

This will:
- Update CloudFront distribution origin to point to S3 bucket
- Add S3 bucket policy to allow CloudFront OAC access
- Update tile URL output

### Step 3: Update demo.html

```javascript
// Update the tile URL in demo.html
const CLOUDFRONT_URL = 'https://d38r6gz80i2tvd.cloudfront.net';
const TILES_URL = CLOUDFRONT_URL + '/tiles/{z}/{x}/{y}.pbf';  // Note: /tiles/ not /data/tiles/
```

### Step 4: Test Tiles

```bash
# Test a tile via CloudFront
curl -I https://d38r6gz80i2tvd.cloudfront.net/tiles/4/4/6.pbf

# Should return:
# HTTP/2 200
# content-type: application/x-protobuf
# content-encoding: gzip
# access-control-allow-origin: *
# x-cache: Hit from cloudfront  (after first request)
```

### Step 5: Clean Up Old ECS Resources (Optional)

Once tiles are working from S3, you can remove the ECS Fargate infrastructure to save costs:

```bash
cd terraform

# Remove ECS service, task definition, ALB, and related resources
terraform destroy \
  -target=aws_ecs_service.tileserver \
  -target=aws_ecs_task_definition.tileserver \
  -target=aws_lb.tileserver \
  -target=aws_lb_listener.tileserver \
  -target=aws_lb_target_group.tileserver \
  -target=aws_security_group.alb \
  -target=aws_ecr_repository.tileserver \
  -target=aws_cloudwatch_log_group.tileserver \
  -auto-approve

# Then remove the tileserver.tf file
rm tileserver.tf
```

## Usage

Access tiles at:
```
https://d38r6gz80i2tvd.cloudfront.net/tiles/{z}/{x}/{y}.pbf
```

Example MapLibre GL JS configuration:
```javascript
const map = new maplibregl.Map({
  container: 'map',
  style: {
    version: 8,
    sources: {
      'blm-plss': {
        type: 'vector',
        tiles: ['https://d38r6gz80i2tvd.cloudfront.net/tiles/{z}/{x}/{y}.pbf'],
        minzoom: 0,
        maxzoom: 14
      }
    },
    layers: [
      // Your layer definitions
    ]
  }
});
```

## Troubleshooting

### Tiles return 403 Forbidden
- Check S3 bucket policy allows CloudFront OAC access
- Verify CloudFront distribution has correct Origin Access Control configured

### Tiles return 404 Not Found
- Verify tiles were uploaded to S3 with correct path: `tiles/{z}/{x}/{y}.pbf`
- Check S3 bucket: `aws s3 ls s3://blm-plss-tiles-production-221082193991/tiles/4/4/ --profile detectormaps`

### Slow tile loading
- Check CloudFront cache hit ratio in CloudFront metrics
- First request to each tile will be slower (cache miss), subsequent requests should be fast (cache hit)

## Maintenance

### Re-extract tiles from updated MBTiles

If you update the MBTiles file:

```bash
# Download updated MBTiles
aws s3 cp s3://blm-plss-tiles-production-221082193991/blm-plss-cadastral.mbtiles . \
  --profile detectormaps --region us-east-1

# Re-extract and upload
python extract_tiles_to_s3.py \
  blm-plss-cadastral.mbtiles \
  blm-plss-tiles-production-221082193991 \
  --prefix tiles \
  --workers 50 \
  --profile detectormaps

# Invalidate CloudFront cache (optional, if you want immediate updates)
aws cloudfront create-invalidation \
  --distribution-id E22EK3AZBGB9QL \
  --paths "/tiles/*" \
  --profile detectormaps
```

## Cost Optimization

To minimize costs:
- Use CloudFront `PriceClass_100` (US, Canada, Europe only) - already configured
- Set high `max-age` for tiles (1 year) - already configured
- Monitor CloudFront data transfer and adjust price class if needed
- Consider using CloudFront Functions for tile URL rewriting if needed

## Infrastructure Costs

Current monthly costs (estimated):
- S3 storage: ~$5-15 (depends on tile count and size)
- S3 requests: ~$0.50 (first million GET requests free)
- CloudFront data transfer: ~$1-20 (depends on traffic, first 1TB/month is cheap)
- CloudFront requests: ~$0.10-1 (depends on traffic)

**Total: ~$6-35/month**

Previous ECS Fargate costs: ~$170-220/month

**Savings: ~85-95% cost reduction**
