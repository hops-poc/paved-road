variable "env" {
  description = "Environment name — part of every resource name (dev, prod, pr-<n>)"
  type        = string
}

variable "name_prefix" {
  description = "Service name prefix; IAM in bootstrap scopes writes to <prefix>-<env>*"
  type        = string
  default     = "hello-world-svc"
}

variable "image_uri" {
  description = "ECR image reference, digest-pinned (repo@sha256:...) — the artifact that ships (§5.3)"
  type        = string
}

variable "enable_cloudfront" {
  description = "Always true in practice — previews (the only caller that would set false) were cut, see main.tf"
  type        = bool
  default     = true
}
