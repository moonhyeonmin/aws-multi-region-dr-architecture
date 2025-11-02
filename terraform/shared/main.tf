terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2" # Seoul (Route 53 is global, but provider needs a region)

  default_tags {
    tags = {
      Project     = "DR-Test"
      Environment = "Test"
      ManagedBy   = "Terraform"
    }
  }
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name        = "dr-test-zone"
    Environment = "Test"
  }
}

module "route53_failover" {
  source = "../modules/route53"

  name_prefix    = "dr-test"
  hosted_zone_id = aws_route53_zone.main.zone_id
  domain_name    = var.domain_name
  primary_ip     = var.primary_ip
  secondary_ip     = var.secondary_ip

  tags = {
    Environment = "Test"
  }
}

