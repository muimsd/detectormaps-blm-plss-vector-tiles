#!/bin/bash
set -e

echo "=== Building and Deploying Tile Builder to AWS ECS ==="
echo ""

# Configuration
AWS_REGION="us-east-1"
AWS_PROFILE="detectormaps"
ECR_REPO_NAME="blm-plss-tiles-production"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile $AWS_PROFILE --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR Repository: $ECR_URI"
echo ""

# Step 1: Build the Docker image
echo "Step 1: Building Docker image for tile builder (linux/amd64)..."
docker build --platform linux/amd64 -f Dockerfile.tilebuilder -t blm-plss-tile-builder:latest .

# Step 2: Tag for ECR
echo "Step 2: Tagging image for ECR..."
docker tag blm-plss-tile-builder:latest ${ECR_URI}:builder-latest

# Step 3: Login to ECR
echo "Step 3: Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
    docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Step 4: Push to ECR
echo "Step 4: Pushing image to ECR..."
docker push ${ECR_URI}:builder-latest

echo ""
echo "Image pushed successfully!"
echo ""

# Step 5: Apply Terraform to create task definition
echo "Step 5: Applying Terraform configuration..."
cd terraform
terraform init -upgrade
terraform apply -auto-approve
cd ..

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "The tile builder task has been automatically started by Terraform."
echo ""
echo "Monitor progress in CloudWatch Logs:"
terraform -chdir=terraform output -raw tile_builder_cloudwatch_logs
echo ""
echo ""
echo "Expected build time: 3-5 hours for all layers (27M+ features)"
echo ""
echo "Outputs will be uploaded to S3 as separate layers:"
echo "  - states.mbtiles / states.pmtiles (z0-z6)"
echo "  - townships.mbtiles / townships.pmtiles (z8-z14)"
echo "  - sections.mbtiles / sections.pmtiles (z10-z14)"
echo "  - intersected.mbtiles / intersected.pmtiles (z12-z14)"
echo ""
echo "To manually trigger another build later:"
echo ""
terraform -chdir=terraform output -raw run_tile_builder_command
