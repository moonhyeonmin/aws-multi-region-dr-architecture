output "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "hosted_zone_name_servers" {
  description = "Route 53 name servers"
  value       = aws_route53_zone.main.name_servers
}

output "domain_name" {
  description = "Domain name"
  value       = var.domain_name
}

