# ECS Task Definition for TileServer
resource "aws_ecs_task_definition" "tileserver" {
  family                   = "${var.project_name}-tileserver"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "2048"   # 2 vCPU
  memory                  = "8192"   # 8 GB RAM
  execution_role_arn      = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  ephemeral_storage {
    size_in_gib = 200  # Storage for 64GB MBTiles + overhead
  }

  container_definitions = jsonencode([
    {
      name  = "tileserver"
      image = "${aws_ecr_repository.tileserver.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.mbtiles.id
        },
        {
          name  = "MBTILES_KEY"
          value = "blm-plss-cadastral.mbtiles"
        },
        {
          name  = "PUBLIC_URL"
          value = "https://${aws_lb.tileserver.dns_name}"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.tileserver.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "tileserver"
        }
      }
    }
  ])
}

# ECR Repository for TileServer
resource "aws_ecr_repository" "tileserver" {
  name                 = "${var.project_name}-tileserver"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "tileserver" {
  name              = "/ecs/${var.project_name}-tileserver"
  retention_in_days = 7
}

# Application Load Balancer
resource "aws_lb" "tileserver" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]

  enable_deletion_protection = false
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Update ECS security group to allow traffic from ALB
resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks.id
  source_security_group_id = aws_security_group.alb.id
}

# Target Group
resource "aws_lb_target_group" "tileserver" {
  name        = "${var.project_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,404"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
}

# ALB Listener
resource "aws_lb_listener" "tileserver" {
  load_balancer_arn = aws_lb.tileserver.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tileserver.arn
  }
}

# ECS Service
resource "aws_ecs_service" "tileserver" {
  name            = "${var.project_name}-tileserver"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.tileserver.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tileserver.arn
    container_name   = "tileserver"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 600  # 10 minutes for MBTiles download

  depends_on = [aws_lb_listener.tileserver]
}
