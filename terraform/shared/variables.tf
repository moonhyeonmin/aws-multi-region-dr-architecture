variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
  default     = "dr-test.local"
}

variable "primary_ip" {
  description = "Primary IP address"
  type        = string
}

variable "secondary_ip" {
  description = "Secondary IP address"
  type        = string
}

