output "seoul_ec2_ip" {
  description = "Seoul EC2 public IP"
  value       = module.seoul.ec2_public_ip
}

output "seoul_ec2_dns" {
  description = "Seoul EC2 public DNS"
  value       = module.seoul.ec2_public_dns
}

output "tokyo_ec2_ip" {
  description = "Tokyo EC2 public IP"
  value       = module.tokyo.ec2_public_ip
}

output "tokyo_ec2_dns" {
  description = "Tokyo EC2 public DNS"
  value       = module.tokyo.ec2_public_dns
}

output "seoul_rds_endpoint" {
  description = "Seoul RDS endpoint"
  value       = module.seoul.rds_endpoint
}

output "tokyo_rds_endpoint" {
  description = "Tokyo RDS endpoint"
  value       = module.tokyo.rds_endpoint
}

output "route53_domain" {
  description = "Route 53 domain name"
  value       = module.route53.domain_name
}

output "route53_name_servers" {
  description = "Route 53 name servers"
  value       = module.route53.hosted_zone_name_servers
}

