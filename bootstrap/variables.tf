variable "gh_org" {
  description = "GitHub org/owner that owns both repos (must match exactly — embedded in every OIDC trust condition)"
  type        = string
}

variable "gh_paved_road_repo" {
  description = "Name of the platform repo"
  type        = string
  default     = "paved-road"
}

variable "gh_service_repo" {
  description = "Name of the service repo whose pipeline assumes these roles"
  type        = string
  default     = "hello-world-svc"
}

# Repos created after 2026-07-15 default to GitHub's "immutable subject
# claims" — the OIDC `sub` claim becomes repo:org@org_id/repo@repo_id
# instead of repo:org/repo (job_workflow_ref is unaffected, stays name-only
# — verified against GitHub's OIDC reference docs). hops-poc/hello-world-svc
# was created 2026-08-24, after the cutover, so trust conditions must match
# the immutable format or every AssumeRoleWithWebIdentity call is denied
# (found live: CloudTrail showed the real sub as
# repo:hops-poc@320600525/hello-world-svc@1345034033:pull_request against a
# trust policy still written for the legacy plain-name format). IDs are
# stable identifiers GitHub assigns at creation — safe to hardcode, and more
# robust than name-matching against a future org/repo rename.
variable "gh_org_id" {
  description = "Numeric GitHub org ID (immutable subject claims) — gh api orgs/<org> --jq .id"
  type        = string
  default     = "320600525"
}

variable "gh_service_repo_id" {
  description = "Numeric GitHub repo ID for gh_service_repo (immutable subject claims) — gh api repos/<org>/<repo> --jq .id"
  type        = string
  default     = "1345034033"
}

variable "aws_region" {
  description = "Single region for everything (PRD: multi-region cut, DECISIONS.md §2)"
  type        = string
  default     = "us-east-1"
}

variable "bedrock_model_id" {
  description = "Allow-listed small Claude model for agents-inference (PRD §8.1 — small model, ~$2-4 total)"
  type        = string
  default     = "anthropic.claude-haiku-4-5-20251001-v1:0"
}
