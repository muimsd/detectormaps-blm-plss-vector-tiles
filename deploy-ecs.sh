#!/bin/bash
set -e

echo "=== BLM PLSS Vector Tiles - ECS Deployment ==="
echo ""

# Use detectormaps AWS profile
export AWS_PROFILE=detectormaps

# Check AWS credentials
echo "1. Checking AWS credentials (profile: detectormaps)..."
aws sts get-caller-identity > /dev/null 2>&1 || {
    echo "Error: AWS profile 'detectormaps' not configured."
    echo "Available profiles:"
    aws configure list-profiles
    exit 1
}
echo "✓ AWS credentials configured"
echo ""

# Get AWS account and region
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region --profile detectormaps || echo "us-east-1")
echo "AWS Account: $AWS_ACCOUNT"
echo "AWS Region: $AWS_REGION"
echo ""

# Initialize Terraform
echo "2. Initializing Terraform..."
cd terraform
export AWS_PROFILE=detectormaps
terraform init
echo ""

# Apply Terraform to create infrastructure
echo "3. Creating AWS infrastructure (S3, ECR, ECS, Lambda)..."
terraform apply -auto-approve \
    -target=aws_s3_bucket.mbtiles \
    -target=aws_ecr_repository.downloader \
    -target=aws_ecs_cluster.main \
    -target=aws_ecs_task_definition.downloader
echo ""

# Get ECR repository URL
ECR_REPO=$(terraform output -raw ecr_repository_url)
echo "ECR Repository: $ECR_REPO"
echo ""

# Build and push Docker image
echo "4. Building and pushing Docker image..."
cd ..

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION --profile detectormaps | \
    docker login --username AWS --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build image
echo "Building Docker image..."
docker build -t blm-plss-downloader .

# Tag and push
echo "Tagging and pushing to ECR..."
docker tag blm-plss-downloader:latest ${ECR_REPO}:latest
docker push ${ECR_REPO}:latest
echo ""

# Run ECS task
echo "5. Running ECS download task..."
cd terraform

CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
TASK_DEF=$(terraform output -raw ecs_task_definition)
SUBNET_IDS=$(terraform output -json ecs_subnet_ids | jq -r '.[]' | paste -sd ',' -)
SG_ID=$(terraform output -raw ecs_security_group_id)

echo "Starting ECS Fargate task..."
TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --task-definition $TASK_DEF \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region $AWS_REGION \
    --query 'tasks[0].taskArn' \
    --output text)

echo "✓ Task started: $TASK_ARN"
echo ""

# Monitor task
echo "6. Monitoring task logs (this will take a while - downloading all PLSS data)..."
echo "Press Ctrl+C to stop monitoring (task will continue running)"
echo ""

# Wait a bit for task to start
sleep 10

# Stream logs
aws logs tail /ecs/blm-plss-tiles-downloader \
    --follow \
    --region $AWS_REGION \
    --format short || true

echo ""
echo "=== Deployment Status ==="
echo "Check task status with:"
echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --region $AWS_REGION"
echo ""
echo "Once complete, deploy Lambda with:"
echo "  cd terraform && terraform apply"
echo ""
