terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "frontend" {
  source          = "./modules/frontend"
  project_name    = var.project_name
  environment     = var.environment
  domain_name     = var.domain_name
  api_gateway_url = var.api_gateway_url
  waf_rate_limit  = var.waf_rate_limit
  price_class     = var.price_class
  log_retention_days      = var.log_retention_days
  content_security_policy = var.content_security_policy
}
