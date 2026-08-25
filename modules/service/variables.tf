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
  description = "Persistent envs (dev/prod) front Lambda with CloudFront; previews skip it (§5.2)"
  type        = bool
  default     = true
}
