output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.web.public_ip
}

output "instance_public_dns" {
  description = "EC2 instance public DNS"
  value       = aws_instance.web.public_dns
}

output "web_security_group_id" {
  description = "Web security group ID"
  value       = aws_security_group.web.id
}

output "db_access_security_group_id" {
  description = "Database access security group ID"
  value       = aws_security_group.db_access.id
}

