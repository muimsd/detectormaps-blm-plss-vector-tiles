output "s3_bucket_name" {
  description = "Name of the S3 bucket storing MBTiles"
  value       = aws_s3_bucket.mbtiles.id
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
  value       = "https://${aws_cloudfront_distribution.tiles.domain_name}/tiles/{z}/{x}/{y}.pbf"
}

output "ecr_repository_url" {
  description = "ECR repository URL for downloader"
  value       = aws_ecr_repository.downloader.repository_url
}
