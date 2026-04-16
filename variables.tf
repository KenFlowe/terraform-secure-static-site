variable "project_name" {
  description = "Short name for your project — used to prefix all resource names (e.g. 'myapp')"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. 'prod', 'staging', 'dev')"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region — must be us-east-1 for CloudFront ACM certificates"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Root domain name already registered in Route 53 (e.g. 'myapp.com')"
  type        = string
}

variable "api_gateway_url" {
  description = "Optional: API Gateway URL to proxy /api/* requests to. Leave empty for static-only sites."
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "Maximum requests per IP per 5-minute window before WAF blocks (SC-5 DoS protection)"
  type        = number
  default     = 2000
}

variable "price_class" {
  description = "CloudFront price class: PriceClass_100 (US/EU), PriceClass_200 (+ Asia), PriceClass_All"
  type        = string
  default     = "PriceClass_100"
}

variable "log_retention_days" {
  description = "CloudWatch and S3 access log retention period in days"
  type        = number
  default     = 30
}

variable "content_security_policy" {
  description = "Custom Content-Security-Policy header value. Defaults to a strict policy."
  type        = string
  default     = ""
}
