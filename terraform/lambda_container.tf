# Lambda function using container image with custom SQLite
resource "null_resource" "build_lambda_image" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/../Dockerfile.lambda")
    code_hash       = filemd5("${path.module}/../lambda/tile_server.py")
    requirements_hash = filemd5("${path.module}/../lambda/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/..
      
      # Login to ECR
      aws ecr get-login-password --region ${var.aws_region} --profile detectormaps | \
        docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
      
      # Build image for amd64 with Docker manifest format
      docker buildx build \
        --platform linux/amd64 \
        --provenance=false \
        --sbom=false \
        -f Dockerfile.lambda \
        -t ${aws_ecr_repository.downloader.repository_url}:lambda-container \
        --push \
        .
    EOT
  }
}

# Create Lambda function with container image
resource "aws_lambda_function" "tile_server_container" {
  depends_on = [null_resource.build_lambda_image]
  
  function_name = "${var.project_name}-tile-server-container"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.downloader.repository_url}:lambda-container"
  role          = aws_iam_role.lambda.arn
  
  timeout     = 30
  memory_size = 1024
  
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.mbtiles.id
      MBTILES_URL = "s3://${aws_s3_bucket.mbtiles.id}/blm-plss-cadastral.mbtiles"
    }
  }
}

# Create Function URL for the container-based Lambda
resource "aws_lambda_function_url" "tile_server_container" {
  function_name      = aws_lambda_function.tile_server_container.function_name
  authorization_type = "NONE"
  
  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = ["*"]
    max_age           = 86400
  }
}

# CloudWatch Log Group for container Lambda
resource "aws_cloudwatch_log_group" "lambda_container" {
  name              = "/aws/lambda/${aws_lambda_function.tile_server_container.function_name}"
  retention_in_days = 7
}

# Output the new Lambda URL
output "lambda_container_url" {
  value       = aws_lambda_function_url.tile_server_container.function_url
  description = "URL for the container-based Lambda tile server"
}
