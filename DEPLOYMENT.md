# BLM PLSS Vector Tiles - Deployment Guide

## Local Testing ✓ Complete

Successfully tested lambda locally with 961MB MBTiles file containing:
- 56 state boundaries
- 10,000 townships
- 134,000 sections
- Coverage: Full US extent (-179° to 179°, -14° to 71°)
- Zoom levels: 0-14

## AWS Deployment Steps

### 1. Configure AWS Credentials

Run:
```bash
aws configure
```

Provide:
- AWS Access Key ID
- AWS Secret Access Key  
- Default region (recommend: `us-east-1`)
- Default output format: `json`

### 2. Preview Infrastructure with Terraform Plan

```bash
cd terraform
terraform plan -var="mbtiles_file=../blm-plss-cadastral.mbtiles"
```

This will show:
- S3 bucket creation for MBTiles storage
- Lambda function deployment
- Lambda Function URL (public HTTPS endpoint)
- CloudFront CDN distribution
- IAM roles and policies

### 3. Deploy Infrastructure

```bash
cd terraform
terraform apply -var="mbtiles_file=../blm-plss-cadastral.mbtiles"
```

Type `yes` when prompted.

**Note**: The 961MB MBTiles file will be uploaded to S3. This may take a few minutes depending on your connection.

### 4. Get Deployment Outputs

After successful deployment:
```bash
terraform output
```

You'll receive:
- `lambda_function_url` - Direct Lambda endpoint (not cached)
- `cloudfront_url` - CloudFront CDN URL (cached, recommended)
- `tile_url_template` - Full tile URL pattern for map applications
- `metadata_url` - TileJSON metadata endpoint

### 5. Test Deployed Endpoints

Test metadata:
```bash
curl https://YOUR_CLOUDFRONT_DOMAIN/metadata.json | jq
```

Test a tile (example):
```bash
curl https://YOUR_CLOUDFRONT_DOMAIN/0/0/0.pbf --output test-tile.pbf
file test-tile.pbf  # Should show: gzip compressed data
```

### 6. Use in Mapping Applications

Add to MapLibre GL JS:
```javascript
map.addSource('plss', {
  type: 'vector',
  tiles: ['https://YOUR_CLOUDFRONT_DOMAIN/{z}/{x}/{y}.pbf'],
  minzoom: 0,
  maxzoom: 14
});

map.addLayer({
  'id': 'sections',
  'type': 'line',
  'source': 'plss',
  'source-layer': 'plss_section',
  'paint': {
    'line-color': '#888',
    'line-width': 1
  }
});
```

## Cost Estimates

- **S3 Storage**: ~$0.023/GB/month → ~$22/month for 961GB
- **Lambda**: Free tier covers 1M requests/month
- **CloudFront**: Free tier covers 1TB data transfer/month
- **Total estimated**: ~$22-30/month (depending on usage)

## Clean Up Resources

To destroy all infrastructure:
```bash
cd terraform
terraform destroy -var="mbtiles_file=../blm-plss-cadastral.mbtiles"
```

## Next Steps

Once deployed, you can:
1. Download remaining PLSS data (layer 3: plss_intersected)
2. Regenerate MBTiles with all 4 layers
3. Update S3 file manually or re-run `terraform apply`

---

**Status**: Ready to deploy! Configure AWS credentials and run terraform apply.
