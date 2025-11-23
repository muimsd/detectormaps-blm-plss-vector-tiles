output "s3_bucket_name" {
  description = "Name of the S3 bucket storing MBTiles"
  value       = aws_s3_bucket.mbtiles.id
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.tile_server.function_name
}

output "lambda_function_url" {
  description = "Direct Lambda function URL (not cached)"
  value       = aws_lambda_function_url.tile_server.function_url
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (cached)"
  value       = aws_cloudfront_distribution.tiles.domain_name
}

output "cloudfront_url" {
  description = "Full CloudFront URL for accessing tiles"
  value       = "https://${aws_cloudfront_distribution.tiles.domain_name}"
}

output "tile_url_template" {
  description = "Tile URL template for use in mapping applications"
  value       = "https://${aws_cloudfront_distribution.tiles.domain_name}/{z}/{x}/{y}.pbf"
}

output "metadata_url" {
  description = "TileJSON metadata URL"
  value       = "https://${aws_cloudfront_distribution.tiles.domain_name}/metadata.json"
}

output "tileserver_url" {
  description = "TileServer ALB URL"
  value       = "http://${aws_lb.tileserver.dns_name}"
}

output "tileserver_ecr_url" {
  description = "TileServer ECR repository URL"
  value       = aws_ecr_repository.tileserver.repository_url
}
