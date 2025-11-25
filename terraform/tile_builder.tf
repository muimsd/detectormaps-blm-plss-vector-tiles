# ECR Repository for tile builder image
resource "aws_ecr_repository" "tile_builder" {
  name                 = "blm-plss-tile-builder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name = "BLM PLSS Tile Builder Repository"
  }
}

resource "aws_ecs_cluster" "tile_builder" {
  name = "blm-plss-tile-builder-cluster"

  tags = {
    Name = "BLM PLSS Tile Builder"
  }
}

resource "aws_cloudwatch_log_group" "tile_builder" {
  name              = "/ecs/blm-plss-tile-builder"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution_role_builder" {
  name = "blm-plss-tile-builder-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_builder" {
  role       = aws_iam_role.ecs_task_execution_role_builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role_builder" {
  name = "blm-plss-tile-builder-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy_builder" {
  name = "blm-plss-tile-builder-task-policy"
  role = aws_iam_role.ecs_task_role_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::blm-plss-tiles-production-221082193991/layers/*",
          "arn:aws:s3:::blm-plss-tiles-production-221082193991/geojson/*"
        ]
      }
    ]
  })
}

# Default VPC resources for networking
resource "aws_default_vpc" "default" {}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-east-1b"
}

resource "aws_security_group" "tile_builder" {
  name        = "blm-plss-tile-builder-sg"
  description = "Security group for tile builder tasks"
  vpc_id      = aws_default_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "blm-plss-tile-builder-sg"
  }
}

resource "aws_ecs_task_definition" "tile_builder" {
  family                   = "blm-plss-tile-builder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "16384"  # 16 vCPU
  memory                   = "65536"  # 64 GB RAM
  execution_role_arn       = aws_iam_role.ecs_task_execution_role_builder.arn
  task_role_arn            = aws_iam_role.ecs_task_role_builder.arn

  ephemeral_storage {
    size_in_gib = 200  # 200 GB for source + output
  }

  container_definitions = jsonencode([
    {
      name      = "tile-builder"
      image     = "${aws_ecr_repository.tile_builder.repository_url}:latest"
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.tile_builder.name
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

  depends_on = [aws_cloudwatch_log_group.tile_builder]
}

output "tile_builder_cluster_name" {
  description = "ECS cluster name for tile builder"
  value       = aws_ecs_cluster.tile_builder.name
}

output "tile_builder_ecr_repository" {
  description = "ECR repository URL for tile builder image"
  value       = aws_ecr_repository.tile_builder.repository_url
}

output "tile_builder_task_definition" {
  description = "Task definition ARN for tile builder"
  value       = aws_ecs_task_definition.tile_builder.arn
}

output "tile_builder_security_group_id" {
  description = "Security group ID for tile builder tasks"
  value       = aws_security_group.tile_builder.id
}
