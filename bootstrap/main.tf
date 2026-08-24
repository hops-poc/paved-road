terraform {
  required_version = ">= 1.8.0" # OpenTofu (MPL fork); replaces Terraform 1.5.7 — DECISIONS.md notes the BSL cut

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Local state until step 3 of bootstrap/README.md. Then:
  # backend "s3" {
  #   bucket         = "<gh_org>-paved-road-tfstate"
  #   key            = "bootstrap/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "paved-road-tfstate-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

locals {
  gh_owner_repo       = "${var.gh_org}/${var.gh_service_repo}"
  gh_owner_paved_road = "${var.gh_org}/${var.gh_paved_road_repo}"
}
