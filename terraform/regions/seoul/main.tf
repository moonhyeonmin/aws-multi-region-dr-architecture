terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.primary]
    }
  }
}

provider "aws" {
  alias  = "primary"
  region = "ap-northeast-2" # Seoul

  default_tags {
    tags = {
      Project     = "DR-Test"
      Environment = "Test"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  name_prefix = "seoul-primary"
}

module "vpc" {
  source = "../../modules/vpc"

  providers = {
    aws = aws.primary
  }

  name_prefix         = local.name_prefix
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  availability_zone   = data.aws_availability_zones.available.names[0]

  tags = {
    Region = "Seoul"
    Role   = "Primary"
  }
}

data "aws_availability_zones" "available" {
  provider = aws.primary
  state    = "available"
}

locals {
  user_data = templatefile("${path.root}/../application/user_data.sh", {
    db_host     = module.rds.db_address
    db_port     = tostring(module.rds.db_port)
    db_name     = var.db_name
    db_user     = var.db_username
    db_password = var.db_password
    region      = "seoul"
    is_replica  = "false"
  })
}

module "ec2" {
  source = "../../modules/ec2"

  providers = {
    aws = aws.primary
  }

  name_prefix      = local.name_prefix
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_id
  instance_type    = var.instance_type
  user_data        = base64encode(local.user_data)

  tags = {
    Region = "Seoul"
    Role   = "Primary"
  }
}

module "rds" {
  source = "../../modules/rds"

  providers = {
    aws = aws.primary
  }

  name_prefix                   = local.name_prefix
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = [module.vpc.private_subnet_id]
  allowed_security_group_ids    = [module.ec2.web_security_group_id]
  is_replica                    = false
  engine_version                = var.engine_version
  instance_class                = var.rds_instance_class
  allocated_storage             = var.allocated_storage
  db_name                       = var.db_name
  db_username                   = var.db_username
  db_password                   = var.db_password
  publicly_accessible           = var.rds_publicly_accessible

  tags = {
    Region = "Seoul"
    Role   = "Primary"
  }
}

