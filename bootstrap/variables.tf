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
