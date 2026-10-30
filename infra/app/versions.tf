terraform {
  required_version = ">= 1.10" # use_lockfile（S3 原生 state lock，不需要 DynamoDB）需要 1.10+
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration：bucket 名稱含帳號 ID，放在本機 backend.hcl（不進 repo）
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Layer     = "app"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ecr_repository" "app" {
  name = var.project # 由 bootstrap layer 建立
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2) # ALB 至少需要 2 個 AZ
}
