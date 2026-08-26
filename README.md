# paved-road

The platform. Application teams ship through it, not around it: branch → gates →
dev → human-approved prod, without leaving the console. Spec and rationale
live in the planning workspace (`hops.ai-demo`) until they're final — `DECISIONS.md`
and `AI-GOVERNANCE.md` land here at the repo root once they're out of draft.

## What's here

**Session 1:** scaffold and bootstrap authored, verified locally.
**Session 2:** both repos pushed to `github.com/hops-poc`.
**Session 3:** bootstrap applied to AWS — IAM roles and state backend live (account `281832122084`, `us-east-1`).
**Session 4:** runtime live — shared ECR repo added to bootstrap; `modules/service` authored; `hello-world-svc`'s dev + prod stacks applied. Both serve the SPA and `/api/*` through CloudFront.
**Session 5:** full CI/CD live. Both repos flipped to public (required for rulesets and for the fork-isolation threat model to be real). `plan.yml`/`deploy.yml`/`agents.yml` and `policies/` (9 OPA/Conftest policies, 27 tests) authored and wired; `hello-world-svc` gets required status checks, a repo ruleset, CODEOWNERS, and `dev`/`prod` GitHub Environments (prod requires a human reviewer). The full branch → gates → dev → smoke test → human approval → prod → smoke test flow ran and passed end-to-end on real infrastructure. Along the way, ~10 real bugs surfaced only by a live run and got fixed: GitHub's immutable OIDC subject claims (IAM `sub` format changed for repos created after 2026-07-15), several missing IAM permissions on `deploy-dev`/`deploy-prod` (`ecr:GetAuthorizationToken`, `logs:DescribeLogGroups`, CloudFront OAC actions, IAM role-policy reads), an arm64/amd64 image mismatch, buildx's default provenance attestation breaking Lambda's `UpdateFunctionCode`, ECR tag immutability breaking retries, and Bun's dev-server Host-header check blocking CloudFront. Agent narration checkpoints (`agents-narrate`, `narrate-dev`, `narrate-prod`) are wired into the pipeline at the points a human needs them, but the jobs are still no-op placeholders — real ReviewBot/Triage/Release/Incident logic is session 6.

- `bootstrap/` — GitHub OIDC provider, the four per-purpose IAM roles (`plan-readonly`,
  `deploy-dev`, `deploy-prod`, `agents-inference`), the shared Terraform state backend
  (`hops-poc-paved-road-tfstate` S3 bucket + `paved-road-tfstate-lock` DynamoDB table), and
  the shared ECR repo (`hello-world-svc`, one immutable digest promoted dev→prod).
  See `bootstrap/README.md` before touching trust policies.
- `templates/service/` — the cookiecutter scaffold. `hello-world-svc` is its output;
  the generated repo's thinness is the product demo, not a placeholder.
- `modules/service/` — the reusable runtime stack: arm64 container Lambda (Bun + Lambda Web
  Adapter) behind a `live` alias → Function URL (AWS_IAM) → CloudFront via OAC → DynamoDB.
  A service's `infra/{dev,prod}` are thin callers. Function URL grants both
  `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction` (required since Oct 2025).
- `.github/workflows/` — the three reusable workflows: `plan.yml` (blocking + reporting gates,
  fork-isolated), `deploy.yml` (dev deploy → smoke test → narrate-dev, human-approved prod
  deploy → smoke test → narrate-prod), `agents.yml` (the `agents-narrate` checkpoint after
  gates — currently a no-op placeholder, like `narrate-dev`/`narrate-prod`).
- `policies/` — 9 OPA/Conftest policies across three namespaces (`terraform/`, `dockerfile/`,
  `workflows/`), 27 tests, run via `conftest verify`/`conftest test`. See `policies/README.md`.

`cli/paved`, `agents/` (real agent logic), and `scenarios/` land in later sessions — see the effort plan.

## Final bill

TBD — filled in during the polish pass, per the budget guardrail (≤ $25, target ~$10).
