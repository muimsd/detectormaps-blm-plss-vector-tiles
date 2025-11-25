output "s3_bucket_name" {
  description = "Name of the S3 bucket storing tiles"
  value       = aws_s3_bucket.mbtiles.id
}


