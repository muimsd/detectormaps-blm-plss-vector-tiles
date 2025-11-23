# S3 bucket for storing MBTiles
resource "aws_s3_bucket" "mbtiles" {
  bucket = "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "mbtiles" {
  bucket = aws_s3_bucket.mbtiles.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "mbtiles" {
  bucket = aws_s3_bucket.mbtiles.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# MBTiles will be uploaded by ECS task
# Not uploading from local to avoid long wait times

# Data source for current AWS account
data "aws_caller_identity" "current" {}
