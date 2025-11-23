#!/usr/bin/env python3
"""
Upload MBTiles file from S3 to EFS using an ECS task.
This is a one-time operation to copy the MBTiles file to EFS for Lambda access.
"""

import boto3
import time

ecs = boto3.client('ecs', region_name='us-east-1')
ec2 = boto3.client('ec2', region_name='us-east-1')
efs = boto3.client('efs', region_name='us-east-1')

# Configuration - get from Terraform outputs
CLUSTER_NAME = "blm-plss-tiles-cluster"
SUBNET_IDS = ["subnet-08bfdb854d80db842", "subnet-0ddba38b7025d043c"]
SECURITY_GROUP_ID = "sg-0a2b560f2888c2a29"  # ECS security group
S3_BUCKET = "blm-plss-tiles-production-221082193991"
MBTILES_KEY = "blm-plss-cadastral.mbtiles"
EFS_ID = "fs-07104fb622f68a580"  # From terraform output

# Register EFS upload task definition
task_definition = ecs.register_task_definition(
    family='blm-plss-efs-uploader',
    requiresCompatibilities=['FARGATE'],
    networkMode='awsvpc',
    cpu='1024',  # 1 vCPU
    memory='2048',  # 2 GB
    executionRoleArn='arn:aws:iam::221082193991:role/blm-plss-tiles-ecs-task-execution',
    taskRoleArn='arn:aws:iam::221082193991:role/blm-plss-tiles-ecs-task',
    volumes=[
        {
            'name': 'efs-storage',
            'efsVolumeConfiguration': {
                'fileSystemId': EFS_ID,
                'rootDirectory': '/mbtiles',
                'transitEncryption': 'ENABLED'
            }
        }
    ],
    containerDefinitions=[
        {
            'name': 'uploader',
            'image': 'amazon/aws-cli:latest',
            'essential': True,
            'command': [
                'sh', '-c',
                f'aws s3 cp s3://{S3_BUCKET}/{MBTILES_KEY} /mnt/efs/blm-plss-cadastral.mbtiles && '
                'ls -lh /mnt/efs/ && '
                'echo "Upload complete!"'
            ],
            'mountPoints': [
                {
                    'sourceVolume': 'efs-storage',
                    'containerPath': '/mnt/efs',
                    'readOnly': False
                }
            ],
            'logConfiguration': {
                'logDriver': 'awslogs',
                'options': {
                    'awslogs-group': '/ecs/blm-plss-tiles-efs-uploader',
                    'awslogs-region': 'us-east-1',
                    'awslogs-stream-prefix': 'uploader',
                    'awslogs-create-group': 'true'
                }
            }
        }
    ]
)

print("Task definition registered")
print(f"Task definition ARN: {task_definition['taskDefinition']['taskDefinitionArn']}")

# Run the task
print("\nStarting ECS task to upload MBTiles to EFS...")
response = ecs.run_task(
    cluster=CLUSTER_NAME,
    taskDefinition=task_definition['taskDefinition']['taskDefinitionArn'],
    launchType='FARGATE',
    networkConfiguration={
        'awsvpcConfiguration': {
            'subnets': SUBNET_IDS,
            'securityGroups': [SECURITY_GROUP_ID],
            'assignPublicIp': 'ENABLED'
        }
    }
)

if response['failures']:
    print("Failed to start task:")
    print(response['failures'])
    exit(1)

task_arn = response['tasks'][0]['taskArn']
task_id = task_arn.split('/')[-1]
print(f"Task started: {task_id}")
print(f"\nMonitor logs at: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Fecs$252Fblm-plss-tiles-efs-uploader")
print(f"\nWait for task to complete (this will take ~10 minutes for 64GB file)...")
print(f"Task ARN: {task_arn}")
