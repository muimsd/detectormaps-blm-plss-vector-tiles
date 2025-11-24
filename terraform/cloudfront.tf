# CloudFront response headers policy for CORS
resource "aws_cloudfront_response_headers_policy" "cors_policy" {
  name    = "${var.project_name}-cors-policy"
  comment = "CORS policy for BLM PLSS tiles"

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    access_control_max_age_sec = 86400
    origin_override            = true  # Override origin headers to prevent duplicates
  }
}

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "tiles" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for BLM PLSS tiles S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution for caching tiles from S3
resource "aws_cloudfront_distribution" "tiles" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "BLM PLSS Vector Tiles Distribution"
  price_class         = "PriceClass_100"  # US, Canada, Europe

  origin {
    domain_name = aws_s3_bucket.mbtiles.bucket_regional_domain_name
    origin_id   = "s3-tiles"
    
    origin_access_control_id = aws_cloudfront_origin_access_control.tiles.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "s3-tiles"

    forwarded_values {
      query_string = false
      headers      = []

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 2592000  # 30 days
    max_ttl                = 31536000  # 1 year
    compress               = false  # tiles already gzipped

    # Response headers policy for CORS
    response_headers_policy_id = aws_cloudfront_response_headers_policy.cors_policy.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-distribution"
  }
}
