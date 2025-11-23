# CloudFront distribution for caching tiles
resource "aws_cloudfront_distribution" "tiles" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "BLM PLSS Vector Tiles Distribution"
  price_class         = "PriceClass_100"  # US, Canada, Europe

  origin {
    domain_name = replace(replace(aws_lambda_function_url.tile_server.function_url, "https://", ""), "/", "")
    origin_id   = "lambda-tile-server"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "lambda-tile-server"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 2592000  # 30 days
    max_ttl                = 31536000  # 1 year
    compress               = true
  }

  # Cache behavior for metadata (shorter cache)
  ordered_cache_behavior {
    path_pattern     = "metadata.json"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "lambda-tile-server"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400  # 1 day
    max_ttl                = 604800  # 7 days
    compress               = true
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
