# BLM PLSS Vector Tiles - ECS Deployment

This guide explains how to deploy the download process on AWS ECS to bypass local network restrictions.

## Architecture

1. **Docker Container**: Runs the download script in AWS ECS Fargate
2. **S3 Bucket**: Stores the generated MBTiles file
3. **Lambda Function**: Serves vector tiles from S3
4. **CloudFront**: CDN for caching tiles globally

## Quick Start

### Prerequisites

- AWS CLI configured: `aws configure`
- Docker installed and running
- Terraform installed

### Deploy Everything

Run the automated deployment script:

```bash
./deploy-ecs.sh
```

This will:
1. ✓ Check AWS credentials
2. ✓ Create S3 bucket, ECR repository, and ECS cluster
3. ✓ Build and push Docker image
4. ✓ Run ECS Fargate task to download all PLSS data
5. ✓ Monitor progress via CloudWatch Logs
6. ✓ Upload MBTiles to S3 when complete

The download process runs on a 4 vCPU / 8 GB Fargate task and may take 1-3 hours depending on BLM server speed.

### Monitor Progress

View logs in real-time:
```bash
aws logs tail /ecs/blm-plss-tiles-downloader --follow
```

Check task status:
```bash
aws ecs list-tasks --cluster blm-plss-tiles-cluster
```

### Deploy Lambda After Download Completes

Once the ECS task finishes and MBTiles is in S3:

```bash
cd terraform
terraform apply
```

This deploys:
- Lambda function
- Lambda Function URL
- CloudFront distribution

Get your endpoints:
```bash
terraform output
```

## Manual Steps (Alternative)

If you prefer manual control:

### 1. Create Infrastructure

```bash
cd terraform
terraform init
terraform apply -target=aws_s3_bucket.mbtiles \
                -target=aws_ecr_repository.downloader \
                -target=aws_ecs_cluster.main
```

### 2. Build and Push Docker Image

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Build image
docker build -t blm-plss-downloader .

# Tag and push
ECR_REPO=$(cd terraform && terraform output -raw ecr_repository_url)
docker tag blm-plss-downloader:latest ${ECR_REPO}:latest
docker push ${ECR_REPO}:latest
```

### 3. Run ECS Task

```bash
cd terraform
aws ecs run-task \
    --cluster $(terraform output -raw ecs_cluster_name) \
    --task-definition $(terraform output -raw ecs_task_definition) \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json ecs_subnet_ids | jq -r '.[0]')],securityGroups=[$(terraform output -raw ecs_security_group_id)],assignPublicIp=ENABLED}"
```

### 4. Deploy Lambda

After task completes:

```bash
cd terraform
terraform apply
```

## Cost Estimates

### One-Time Download (ECS Fargate)
- **Fargate Task**: ~$0.12/hour × 2 hours = $0.24
- **Data Transfer Out**: Free (stays in AWS)
- **ECR Storage**: $0.10/GB/month (minimal for one image)

### Ongoing Tile Server
- **S3 Storage**: ~$0.023/GB/month for MBTiles file
- **Lambda**: Free tier covers 1M requests/month
- **CloudFront**: Free tier covers 1TB transfer/month
- **Total**: ~$20-30/month depending on usage

## Troubleshooting

### Task fails to start
- Check ECS task logs in CloudWatch
- Verify ECR image was pushed successfully
- Ensure security group allows outbound HTTPS

### Download is slow
- BLM server performance varies
- Typical download time: 1-3 hours for full dataset
- Progress is logged every batch

### Out of memory
- Increase task memory in `terraform/ecs.tf`
- Current: 8192 MB (8 GB)

## Clean Up

Remove all resources:

```bash
cd terraform
terraform destroy
```

This will delete:
- S3 bucket and MBTiles file
- ECR repository and images
- ECS cluster and tasks
- Lambda function
- CloudFront distribution

---

**Ready to deploy!** Run `./deploy-ecs.sh` to start.
