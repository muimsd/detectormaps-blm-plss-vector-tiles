# PMTiles Converter ECS Task Definition
resource "aws_ecs_task_definition" "pmtiles_converter" {
  family                   = "blm-plss-pmtiles-converter"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "16384"  # 16 vCPU
  memory                   = "73728"  # 72 GB (must be compatible with CPU)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  ephemeral_storage {
    size_in_gib = 200
  }

  container_definitions = jsonencode([
    {
      name      = "converter"
      image     = "${aws_ecr_repository.downloader.repository_url}:pmtiles"
      essential = true

      environment = [
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.mbtiles.bucket
        },
        {
          name  = "MBTILES_KEY"
          value = "blm-plss-cadastral.mbtiles"
        },
        {
          name  = "PMTILES_KEY"
          value = "blm-plss-cadastral.pmtiles"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/blm-plss-pmtiles-converter"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "converter"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  tags = {
    Name        = "blm-plss-pmtiles-converter"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }
}

# CloudWatch Log Group for PMTiles Converter
resource "aws_cloudwatch_log_group" "pmtiles_converter" {
  name              = "/ecs/blm-plss-pmtiles-converter"
  retention_in_days = 7

  tags = {
    Name        = "blm-plss-pmtiles-converter-logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }
}

# Output the task definition ARN
output "pmtiles_converter_task_definition_arn" {
  description = "ARN of the PMTiles converter task definition"
  value       = aws_ecs_task_definition.pmtiles_converter.arn
}

output "pmtiles_converter_task_family" {
  description = "Family name of the PMTiles converter task"
  value       = aws_ecs_task_definition.pmtiles_converter.family
}
