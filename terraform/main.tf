# Main Terraform configuration
# This file coordinates the deployment across regions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  backend "s3" {
    # Configure your S3 backend here, or use local state
    # bucket = "your-terraform-state-bucket"
    # key    = "dr-test/terraform.tfstate"
    # region = "ap-northeast-2"
  }
}

# Variables
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

variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
  default     = "dr-test.local"
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

# Seoul region (Primary)
module "seoul" {
  source = "./regions/seoul"

  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  instance_type        = var.instance_type
  rds_instance_class   = var.rds_instance_class
}

# Tokyo region (DR) - depends on Seoul for RDS identifier
module "tokyo" {
  source = "./regions/tokyo"
  depends_on = [module.seoul]

  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  instance_type          = var.instance_type
  rds_instance_class     = var.rds_instance_class
  primary_rds_identifier = module.seoul.rds_identifier
}

# Route 53 configuration (shared)
module "route53" {
  source = "./shared"
  depends_on = [module.seoul, module.tokyo]

  domain_name   = var.domain_name
  primary_ip    = module.seoul.ec2_public_ip
  secondary_ip  = module.tokyo.ec2_public_ip
}

