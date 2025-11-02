output "db_instance_id" {
  description = "RDS instance identifier"
  value       = var.is_replica ? aws_db_instance.replica[0].id : aws_db_instance.primary[0].id
}

output "db_endpoint" {
  description = "RDS endpoint"
  value       = var.is_replica ? aws_db_instance.replica[0].endpoint : aws_db_instance.primary[0].endpoint
}

output "db_address" {
  description = "RDS address"
  value       = var.is_replica ? aws_db_instance.replica[0].address : aws_db_instance.primary[0].address
}

output "db_port" {
  description = "RDS port"
  value       = var.is_replica ? aws_db_instance.replica[0].port : aws_db_instance.primary[0].port
}

output "db_arn" {
  description = "RDS ARN"
  value       = var.is_replica ? aws_db_instance.replica[0].arn : aws_db_instance.primary[0].arn
}

