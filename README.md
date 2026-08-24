# paved-road

The platform. Application teams ship through it, not around it: branch → gates →
preview → dev → human-approved prod, without leaving the console. Spec and rationale
live in the planning workspace (`hops.ai-demo`) until they're final — `DECISIONS.md`
and `AI-GOVERNANCE.md` land here at the repo root once they're out of draft.

## What's here

**Session 1:** scaffold and bootstrap authored, verified locally.
**Session 2:** both repos pushed to `github.com/hops-poc`.
**Session 3:** bootstrap applied to AWS — IAM roles and state backend live (account `281832122084`, `us-east-1`).

- `bootstrap/` — GitHub OIDC provider, the four per-purpose IAM roles (`plan-readonly`,
  `deploy-dev`, `deploy-prod`, `agents-inference`), and the shared Terraform state backend
  (`hops-poc-paved-road-tfstate` S3 bucket + `paved-road-tfstate-lock` DynamoDB table).
  See `bootstrap/README.md` before touching trust policies.
- `templates/service/` — the cookiecutter scaffold. `hello-world-svc` is its output;
  the generated repo's thinness is the product demo, not a placeholder.

`modules/` (Terraform), `policies/` (OPA/Conftest), `cli/paved`, `agents/`, and
`scenarios/` land in later sessions — see the effort plan.

## Final bill

TBD — filled in during the polish pass, per the budget guardrail (≤ $25, target ~$10).
