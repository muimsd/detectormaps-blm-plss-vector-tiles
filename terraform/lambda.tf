# IAM role for Lambda function
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda to access S3 and CloudWatch Logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mbtiles.arn,
          "${aws_s3_bucket.mbtiles.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.mbtiles.arn
      }
    ]
  })
}

# Package Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function
resource "aws_lambda_function" "tile_server" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-tile-server"
  role            = aws_iam_role.lambda.arn
  handler         = "tile_server.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  memory_size     = var.lambda_memory_size
  timeout         = var.lambda_timeout

  # VPC Configuration for EFS access
  vpc_config {
    subnet_ids         = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # EFS File System Configuration
  file_system_config {
    arn              = aws_efs_access_point.lambda_mbtiles.arn
    local_mount_path = "/mnt/efs"
  }

  environment {
    variables = {
      MBTILES_PATH   = "/mnt/efs/blm-plss-cadastral.mbtiles"
      MBTILES_BUCKET = aws_s3_bucket.mbtiles.id
      MBTILES_KEY    = "blm-plss-cadastral.mbtiles"
    }
  }

  depends_on = [
    aws_efs_mount_target.mbtiles_az1,
    aws_efs_mount_target.mbtiles_az2
  ]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.tile_server.function_name}"
  retention_in_days = 7
}

# Lambda function URL (for public access)
resource "aws_lambda_function_url" "tile_server" {
  function_name      = aws_lambda_function.tile_server.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "HEAD"]
    allow_headers     = ["*"]
    expose_headers    = ["*"]
    max_age          = 86400
  }
}

# Permission for Lambda URL
resource "aws_lambda_permission" "function_url" {
  statement_id           = "AllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.tile_server.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
