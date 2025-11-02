output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Primary private subnet ID"
  value       = aws_subnet.private.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for RDS subnet group)"
  value       = [aws_subnet.private.id, aws_subnet.private_secondary.id]
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

