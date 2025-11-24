#!/bin/bash
set -e

echo "=== Running Tile Builder on AWS ECS ==="
echo ""

# Configuration
AWS_REGION="us-east-1"
AWS_PROFILE="detectormaps"
CLUSTER_NAME="blm-plss-tiles-production"
TASK_DEF="blm-plss-tile-builder"

# Get subnet and security group IDs from Terraform
cd terraform
SUBNET_A=$(terraform output -raw public_subnet_a_id 2>/dev/null || echo "")
SUBNET_B=$(terraform output -raw public_subnet_b_id 2>/dev/null || echo "")
SECURITY_GROUP=$(terraform output -raw tileserver_security_group_id 2>/dev/null || echo "")
cd ..

# Fallback: query AWS if Terraform outputs not available
if [ -z "$SUBNET_A" ]; then
    echo "Getting subnet and security group from AWS..."
    SUBNET_A=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=blm-plss-tiles-public-a" \
        --query 'Subnets[0].SubnetId' \
        --output text \
        --profile $AWS_PROFILE \
        --region $AWS_REGION)
    
    SUBNET_B=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=blm-plss-tiles-public-b" \
        --query 'Subnets[0].SubnetId' \
        --output text \
        --profile $AWS_PROFILE \
        --region $AWS_REGION)
    
    SECURITY_GROUP=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=blm-plss-tiles-tileserver-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --profile $AWS_PROFILE \
        --region $AWS_REGION)
fi

echo "Cluster: $CLUSTER_NAME"
echo "Task Definition: $TASK_DEF"
echo "Subnets: $SUBNET_A, $SUBNET_B"
echo "Security Group: $SECURITY_GROUP"
echo ""

# Run the task
echo "Starting tile builder task..."
TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --launch-type FARGATE \
    --task-definition $TASK_DEF \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A,$SUBNET_B],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'tasks[0].taskArn' \
    --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
    echo "ERROR: Failed to start task"
    exit 1
fi

echo "Task started successfully!"
echo "Task ARN: $TASK_ARN"
echo ""

# Extract task ID
TASK_ID=$(echo $TASK_ARN | awk -F/ '{print $NF}')

echo "Monitoring task status..."
echo "You can view logs at:"
echo "https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups/log-group/\$252Fecs\$252Fblm-plss-tile-builder/log-events/tile-builder\$252F$TASK_ID"
echo ""

# Wait for task to start running
echo "Waiting for task to start running..."
for i in {1..30}; do
    STATUS=$(aws ecs describe-tasks \
        --cluster $CLUSTER_NAME \
        --tasks $TASK_ARN \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        --query 'tasks[0].lastStatus' \
        --output text)
    
    echo "Status: $STATUS"
    
    if [ "$STATUS" == "RUNNING" ]; then
        echo ""
        echo "Task is now RUNNING!"
        echo ""
        echo "Expected build time: 2-4 hours for 27M+ features"
        echo ""
        echo "To check status:"
        echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --profile $AWS_PROFILE --region $AWS_REGION"
        echo ""
        echo "To stream logs:"
        echo "  aws logs tail /ecs/blm-plss-tile-builder --follow --profile $AWS_PROFILE --region $AWS_REGION"
        break
    fi
    
    if [ "$STATUS" == "STOPPED" ]; then
        echo ""
        echo "ERROR: Task stopped before running. Check CloudWatch logs for errors."
        exit 1
    fi
    
    sleep 5
done

echo ""
echo "Once complete, the optimized MBTiles will be uploaded to:"
echo "  s3://blm-plss-tiles-production-221082193991/blm-plss-cadastral-optimized.mbtiles"
