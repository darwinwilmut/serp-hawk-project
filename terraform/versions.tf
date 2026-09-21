terraform {
  required_version = ">= 1.6"

  backend "s3" {
    bucket  = "terraform-state-management-0112"
    key     = "serphawk-crm/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
    profile = "aws-darwin-personal"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "aws-darwin-personal"
}
