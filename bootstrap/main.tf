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

  # The bucket and lock table this points at are created by this stack's own
  # state.tf, so a first-ever apply runs on local state with this block
  # commented out, then migrates (step 3 of bootstrap/README.md). Both exist,
  # so it is live: bootstrap's state belongs in the versioned bucket, not only
  # in a laptop-local file whose loss means hand-importing ~20 resources.
  # The key can't collide with a service's "<service>/<env>/terraform.tfstate"
  # and sits deliberately outside the "*/dev/*" and "*/prod/*" globs
  # deploy-dev/deploy-prod are scoped to in iam.tf — no CI role can read or
  # write it, which is the point (DECISIONS.md §3).
  backend "s3" {
    bucket         = "hops-poc-paved-road-tfstate"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "paved-road-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  # Used only in job_workflow_ref conditions — that claim is unaffected by
  # immutable subject claims, stays name-based regardless.
  gh_owner_paved_road = "${var.gh_org}/${var.gh_paved_road_repo}"

  # Used in sub conditions — hello-world-svc and later service repos were
  # created after GitHub's 2026-07-15 immutable-subject-claims cutover, so
  # sub is repo:org@org_id/repo@repo_id, not repo:org/repo (see
  # variables.tf). One entry per trusted service repo.
  services = {
    for s in var.services : s.name => merge(s, {
      gh_owner_repo = "${var.gh_org}@${var.gh_org_id}/${s.repo}@${s.repo_id}"
    })
  }
}
