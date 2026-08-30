# infra/dev

A thin caller of `paved-road/modules/service` (arm64 container Lambda → `live` alias →
Function URL (AWS_IAM) → CloudFront via OAC → DynamoDB). Thin is the point: the runtime
shape lives in the module, not here.

Add a `main.tf` with the S3 backend at state key `dev/terraform.tfstate` in the shared
bucket (`paved-road/bootstrap/`), and one `module "service"` block. See
`hello-world-svc/infra/dev/main.tf` for the worked example.

`tofu apply` runs from `paved-road`'s `deploy.yml` via OIDC — **never from a local
machine** outside a documented break-glass.
