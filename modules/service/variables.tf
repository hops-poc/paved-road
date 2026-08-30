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

variable "memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 15
}

variable "log_retention_days" {
  description = "CloudWatch log group retention"
  type        = number
  default     = 14
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode — PROVISIONED flips dynamodb_capacity_report.rego's cost-signal warning"
  type        = string
  default     = "PAY_PER_REQUEST"
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "dynamodb_billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}
