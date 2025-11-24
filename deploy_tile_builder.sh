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
echo "Step 5: Creating ECS task definition with Terraform..."
cd terraform
terraform apply -target=aws_ecs_task_definition.tile_builder -auto-approve
cd ..

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "To run the tile builder task:"
echo ""
echo "aws ecs run-task \\"
echo "  --cluster blm-plss-tiles-production \\"
echo "  --launch-type FARGATE \\"
echo "  --task-definition blm-plss-tile-builder \\"
echo "  --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxx,subnet-yyy],securityGroups=[sg-xxx],assignPublicIp=ENABLED}' \\"
echo "  --region us-east-1 \\"
echo "  --profile detectormaps"
echo ""
echo "Or use the helper script: ./run_tile_builder.sh"
echo ""
echo "Monitor progress in CloudWatch Logs:"
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/\$252Fecs\$252Fblm-plss-tile-builder"
