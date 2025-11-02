variable "db_name" {
  description = "Database name"
  type        = string
  default     = "testdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_publicly_accessible" {
  description = "Whether RDS is publicly accessible"
  type        = bool
  default     = true
}

variable "primary_rds_identifier" {
  description = "Primary RDS identifier for cross-region replica"
  type        = string
}

