# infra/prod

Wired in session 2: a thin Terragrunt-style config pointing at
`paved-road/modules/service` (Lambda container + DynamoDB + CloudFront),
state key `prod/terraform.tfstate` in the shared bucket (`bootstrap/`).
Empty on purpose until then.
