variable "project_name"            { type = string }
variable "environment"             { type = string }
variable "domain_name"             { type = string }
variable "api_gateway_url"         { type = string }
variable "waf_rate_limit"          { type = number }
variable "price_class"             { type = string }
variable "log_retention_days"      { type = number }
variable "content_security_policy" { type = string }

locals {
  s3_origin_id  = "${var.project_name}-s3-origin"
  api_origin_id = "${var.project_name}-api-origin"
  has_api       = var.api_gateway_url != ""

  default_csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://${var.domain_name}; frame-ancestors 'none';"
  csp         = var.content_security_policy != "" ? var.content_security_policy : local.default_csp
}

# ---------------------------------------------------------------
# Route 53 — existing hosted zone lookup
# ---------------------------------------------------------------
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ---------------------------------------------------------------
# ACM Certificate — SC-8: Transmission confidentiality (TLS)
# Must be in us-east-1 for CloudFront
# ---------------------------------------------------------------
resource "aws_acm_certificate" "cert" {
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------------------------------------------------------------
# S3 — private bucket, no direct public access
# AC-3: Access Enforcement — only CloudFront OAC can read objects
# SC-28: Encryption at rest
# ---------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${var.environment}"

  tags = { Name = "${var.project_name}-frontend-${var.environment}" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AU-2: S3 access logging bucket
resource "aws_s3_bucket" "frontend_logs" {
  bucket = "${var.project_name}-frontend-logs-${var.environment}"
}

resource "aws_s3_bucket_public_access_block" "frontend_logs" {
  bucket                  = aws_s3_bucket.frontend_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "frontend_logs" {
  bucket = aws_s3_bucket.frontend_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_logging" "frontend" {
  bucket        = aws_s3_bucket.frontend.id
  target_bucket = aws_s3_bucket.frontend_logs.id
  target_prefix = "s3-access-logs/"
}

# ---------------------------------------------------------------
# CloudFront Origin Access Control
# AC-3: Only CloudFront can access S3 — no direct bucket URLs
# ---------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac-${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
}

# ---------------------------------------------------------------
# WAF — SC-5, SC-7, SI-3
# ---------------------------------------------------------------
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf-${var.environment}"
  scope       = "CLOUDFRONT"
  description = "WAF protecting ${var.project_name} — OWASP, SQLi, bad inputs, rate limiting"

  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 30
    action { block {} }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf-${var.environment}"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.project_name}-waf-${var.environment}" }
}

# ---------------------------------------------------------------
# Security response headers — SC-8, SI-3
# HSTS, CSP, X-Frame-Options, XSS protection
# ---------------------------------------------------------------
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.project_name}-security-headers-${var.environment}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    content_security_policy {
      content_security_policy = local.csp
      override                = true
    }
  }
}

# ---------------------------------------------------------------
# CloudFront Distribution
# SC-8: TLS enforced, HTTP redirected
# SC-5: WAF attached for DoS protection
# AU-2: Access logging to S3
# ---------------------------------------------------------------
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  price_class         = var.price_class
  http_version        = "http2and3"
  web_acl_id          = aws_wafv2_web_acl.main.arn

  # Origin 1: S3 (SPA)
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Origin 2: API Gateway (optional)
  dynamic "origin" {
    for_each = local.has_api ? [1] : []
    content {
      domain_name = trimsuffix(replace(var.api_gateway_url, "https://", ""), "/")
      origin_id   = local.api_origin_id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Default: S3 SPA
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # /api/* → API Gateway (no cache, only when api_gateway_url is set)
  dynamic "ordered_cache_behavior" {
    for_each = local.has_api ? [1] : []
    content {
      path_pattern           = "/api/*"
      target_origin_id       = local.api_origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      forwarded_values {
        query_string = true
        headers      = ["Accept", "Content-Type", "Authorization"]
        cookies { forward = "none" }
      }

      response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

      min_ttl     = 0
      default_ttl = 0
      max_ttl     = 0
    }
  }

  # SPA routing — serve index.html for 404/403
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = aws_s3_bucket.frontend_logs.bucket_domain_name
    prefix          = "cloudfront-logs/"
    include_cookies = false
  }
}

# ---------------------------------------------------------------
# Route 53 DNS records
# ---------------------------------------------------------------
resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

output "cloudfront_url"             { value = "https://${aws_cloudfront_distribution.frontend.domain_name}" }
output "cloudfront_distribution_id" { value = aws_cloudfront_distribution.frontend.id }
output "frontend_bucket_name"       { value = aws_s3_bucket.frontend.id }
output "waf_arn"                    { value = aws_wafv2_web_acl.main.arn }
