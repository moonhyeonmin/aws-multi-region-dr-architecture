terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_route53_health_check" "primary" {
  ip_address        = var.primary_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-primary-hc"
    }
  )
}

resource "aws_route53_health_check" "secondary" {
  ip_address        = var.secondary_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-secondary-hc"
    }
  )
}

resource "aws_route53_record" "primary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier = "primary"
  health_check_id = aws_route53_health_check.primary.id
  records         = [var.primary_ip]
  ttl             = 60

  allow_overwrite = true
}

resource "aws_route53_record" "secondary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id
  records         = [var.secondary_ip]
  ttl             = 60

  allow_overwrite = true
}

