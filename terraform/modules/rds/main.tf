terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-rds-sg"
    }
  )
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-db-subnet-group"
    }
  )
}

resource "aws_db_instance" "primary" {
  count = var.is_replica ? 0 : 1

  identifier           = "${var.name_prefix}-mysql"
  engine               = "mysql"
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  storage_type         = "gp3"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  publicly_accessible  = var.publicly_accessible
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.main.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  enabled_cloudwatch_logs_exports = ["error", "general", "slow_query"]

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-mysql-primary"
    }
  )
}

resource "aws_db_instance" "replica" {
  count = var.is_replica ? 1 : 0

  identifier           = "${var.name_prefix}-mysql-replica"
  replicate_source_db = var.replicate_source_db
  instance_class      = var.instance_class
  publicly_accessible = var.publicly_accessible
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.main.name

  backup_retention_period = 0
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  enabled_cloudwatch_logs_exports = ["error", "general", "slow_query"]

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-mysql-replica"
    }
  )
}

