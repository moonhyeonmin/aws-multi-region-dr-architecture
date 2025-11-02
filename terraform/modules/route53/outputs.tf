output "primary_health_check_id" {
  description = "Primary health check ID"
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "Secondary health check ID"
  value       = aws_route53_health_check.secondary.id
}

output "primary_record_name" {
  description = "Primary record name"
  value       = aws_route53_record.primary.name
}

output "secondary_record_name" {
  description = "Secondary record name"
  value       = aws_route53_record.secondary.name
}

