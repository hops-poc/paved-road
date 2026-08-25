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
  # Used only in job_workflow_ref conditions — that claim is unaffected by
  # immutable subject claims, stays name-based regardless.
  gh_owner_paved_road = "${var.gh_org}/${var.gh_paved_road_repo}"

  # Used in sub conditions — hello-world-svc was created after GitHub's
  # 2026-07-15 immutable-subject-claims cutover, so sub is
  # repo:org@org_id/repo@repo_id, not repo:org/repo (see variables.tf).
  gh_owner_repo = "${var.gh_org}@${var.gh_org_id}/${var.gh_service_repo}@${var.gh_service_repo_id}"
}
