terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.secondary]
    }
  }
}

provider "aws" {
  alias  = "secondary"
  region = "ap-northeast-1" # Tokyo

  default_tags {
    tags = {
      Project     = "DR-Test"
      Environment = "Test"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  name_prefix = "tokyo-dr"
}

module "vpc" {
  source = "../../modules/vpc"

  providers = {
    aws = aws.secondary
  }

  name_prefix                = local.name_prefix
  vpc_cidr                   = "10.1.0.0/16"
  public_subnet_cidr         = "10.1.1.0/24"
  private_subnet_cidr        = "10.1.2.0/24"
  availability_zone          = data.aws_availability_zones.available.names[0]
  availability_zone_secondary = data.aws_availability_zones.available.names[1]

  tags = {
    Region = "Tokyo"
    Role   = "DR"
  }
}

data "aws_availability_zones" "available" {
  provider = aws.secondary
  state    = "available"
}

locals {
  user_data = templatefile("${path.root}/../application/user_data.sh", {
    db_host     = module.rds.db_address
    db_port     = tostring(module.rds.db_port)
    db_name     = var.db_name
    db_user     = var.db_username
    db_password = var.db_password
    region      = "tokyo"
    is_replica  = "true"
  })
}

module "ec2" {
  source = "../../modules/ec2"

  providers = {
    aws = aws.secondary
  }

  name_prefix      = local.name_prefix
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_id
  instance_type    = var.instance_type
  user_data        = base64encode(local.user_data)

  tags = {
    Region = "Tokyo"
    Role   = "DR"
  }
}

module "rds" {
  source = "../../modules/rds"

  providers = {
    aws = aws.secondary
  }

  name_prefix                = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.ec2.web_security_group_id]
  is_replica                  = true
  replicate_source_db         = var.primary_rds_arn
  instance_class              = var.rds_instance_class
  publicly_accessible         = var.rds_publicly_accessible
  # Read Replica는 Primary의 자격 증명을 상속받으므로 db_username과 db_password 불필요
  db_username                 = "" # Read Replica에서는 사용하지 않음
  db_password                 = "" # Read Replica에서는 사용하지 않음

  tags = {
    Region = "Tokyo"
    Role   = "DR"
  }
}

