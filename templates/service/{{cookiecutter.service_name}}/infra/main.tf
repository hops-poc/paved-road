# One stack, both environments. `env` selects which block of config.yaml
# applies; CI passes it via -var and picks the state key via -backend-config
# (paved-road's deploy.yml / plan.yml). Never hand-edit this file per
# environment — that's what config.yaml is for.

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "hops-poc-paved-road-tfstate"
    region         = "us-east-1"
    dynamodb_table = "paved-road-tfstate-lock"
    encrypt        = true
    # key is supplied per environment via -backend-config="key=<env>/terraform.tfstate"
  }
}

provider "aws" {
  region = "us-east-1"

  # `tofu validate` calls the provider's Configure(), which pings STS even
  # for validate — CI's credential-less tofu-validate job needs these to
  # run offline; real deploys authenticate normally via OIDC.
  skip_credentials_validation = true
  skip_requesting_account_id  = true

  default_tags {
    tags = {
      Service     = local.cfg.service
      Environment = title(var.env)
    }
  }
}

variable "env" {
  description = "Environment name — selects a block from config.yaml. Defaults to dev so validate/infracost work standalone; CI always passes this explicitly."
  type        = string
  default     = "dev"
}

variable "image_uri" {
  description = "Digest-pinned ECR image (repo@sha256:...)"
  type        = string
}

locals {
  cfg     = yamldecode(file("${path.module}/config.yaml"))
  env_cfg = merge(local.cfg.defaults, lookup(local.cfg.environments, var.env, {}))
}

module "service" {
  source                 = "git::https://github.com/{{cookiecutter.gh_org}}/paved-road.git//modules/service?ref=${local.cfg.module_ref}"
  env                    = var.env
  name_prefix            = local.cfg.service
  image_uri              = var.image_uri
  memory                 = local.env_cfg.memory
  timeout                = local.env_cfg.timeout
  log_retention_days     = local.env_cfg.log_retention_days
  dynamodb_billing_mode  = local.env_cfg.dynamodb_billing_mode
  enable_cloudfront      = local.env_cfg.enable_cloudfront
  cloudfront_price_class = local.env_cfg.cloudfront_price_class
}

output "url" {
  value = module.service.url
}

output "function_url" {
  value = module.service.function_url
}
