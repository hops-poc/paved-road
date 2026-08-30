# infra/prod

A thin caller of `paved-road/modules/service`, identical in shape to `infra/dev` — same
module, different state key and variables. Thin is the point: the runtime shape lives in
the module, not here.

Add a `main.tf` with the S3 backend at state key `prod/terraform.tfstate` in the shared
bucket (`paved-road/bootstrap/`), and one `module "service"` block. See
`hello-world-svc/infra/prod/main.tf` for the worked example.

`tofu apply` runs from `paved-road`'s `deploy.yml` via OIDC, and only after the `prod`
GitHub Environment's human reviewer approves — **never from a local machine** outside a
documented break-glass.
