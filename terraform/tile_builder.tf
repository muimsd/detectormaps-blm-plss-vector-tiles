resource "aws_ecs_task_definition" "tile_builder" {
  family                   = "blm-plss-tile-builder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "4096"  # 4 vCPU for faster processing
  memory                   = "16384" # 16 GB RAM for large datasets
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  ephemeral_storage {
    size_in_gib = 200 # Enough for source GDBs + intermediate files
  }

  container_definitions = jsonencode([
    {
      name      = "tile-builder"
      image     = "${aws_ecr_repository.tileserver.repository_url}:builder-latest"
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.tileserver.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "tile-builder"
        }
      }

      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        }
      ]
    }
  ])
}

# CloudWatch Log Group for builder
resource "aws_cloudwatch_log_group" "tile_builder" {
  name              = "/ecs/blm-plss-tile-builder"
  retention_in_days = 7
}

# Output for manual task run command
output "run_tile_builder_command" {
  description = "Command to run the tile builder task"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.tileserver.name} \
      --launch-type FARGATE \
      --task-definition ${aws_ecs_task_definition.tile_builder.family} \
      --network-configuration "awsvpcConfiguration={subnets=[${aws_subnet.public_a.id},${aws_subnet.public_b.id}],securityGroups=[${aws_security_group.tileserver.id}],assignPublicIp=ENABLED}" \
      --region ${var.aws_region} \
      --profile detectormaps
  EOT
}
