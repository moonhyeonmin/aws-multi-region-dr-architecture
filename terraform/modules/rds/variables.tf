variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access RDS"
  type        = list(string)
}

variable "is_replica" {
  description = "Whether this is a read replica"
  type        = bool
  default     = false
}

variable "replicate_source_db" {
  description = "Source DB identifier for replica (required if is_replica is true)"
  type        = string
  default     = ""
}

variable "engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "testdb"
}

variable "db_username" {
  description = "Database master username (required for primary, not for replica)"
  type        = string
  default     = ""
}

variable "db_password" {
  description = "Database master password (required for primary, not for replica)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "publicly_accessible" {
  description = "Whether RDS is publicly accessible"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

