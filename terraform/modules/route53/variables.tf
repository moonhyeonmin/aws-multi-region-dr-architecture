variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the record"
  type        = string
}

variable "primary_ip" {
  description = "Primary IP address for health check and DNS record"
  type        = string
}

variable "secondary_ip" {
  description = "Secondary IP address for health check and DNS record"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

