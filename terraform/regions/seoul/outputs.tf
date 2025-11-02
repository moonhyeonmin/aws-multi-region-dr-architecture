output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2.instance_id
}

output "ec2_public_ip" {
  description = "EC2 instance public IP"
  value       = module.ec2.instance_public_ip
}

output "ec2_public_dns" {
  description = "EC2 instance public DNS"
  value       = module.ec2.instance_public_dns
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

output "rds_address" {
  description = "RDS address"
  value       = module.rds.db_address
}

output "rds_arn" {
  description = "RDS ARN"
  value       = module.rds.db_arn
}

output "rds_identifier" {
  description = "RDS identifier"
  value       = module.rds.db_instance_id
}

