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

# CloudFront distribution for caching tiles from ALB
resource "aws_cloudfront_distribution" "tiles" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "BLM PLSS Vector Tiles Distribution"
  price_class         = "PriceClass_100"  # US, Canada, Europe

  origin {
    domain_name = aws_lb.tileserver.dns_name
    origin_id   = "alb-tileserver"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = aws_lb.tileserver.dns_name
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "alb-tileserver"

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
