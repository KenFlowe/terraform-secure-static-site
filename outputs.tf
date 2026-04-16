output "cloudfront_url" {
  description = "CloudFront URL — use this before DNS propagates"
  value       = module.frontend.cloudfront_url
}

output "website_url" {
  description = "Your public website URL"
  value       = "https://${var.domain_name}"
}

output "frontend_bucket_name" {
  description = "S3 bucket name — upload your build artifacts here"
  value       = module.frontend.frontend_bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — needed for cache invalidation after deployments"
  value       = module.frontend.cloudfront_distribution_id
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = module.frontend.waf_arn
}
