# paved-road

The platform application teams ship **through**, not around. A service repo contains its
own code and a ~30-line `ci.yml`; every gate, deploy step, and IAM boundary lives here
and is consumed at a pinned SHA.

```
branch → gates → merge → dev → smoke test → human approval → prod → smoke test
```

No step leaves the console. Runtime is an arm64 container Lambda behind CloudFront —
one immutable image digest built once and promoted dev → prod.

| | |
|---|---|
| **Account / region** | `281832122084` / `us-east-1` |
| **Onboarded services** | `hello-world-svc` |
| **Cost to date** | $0.0023 (guardrail ≤ $25) |

---

## Contents

- [For service developers](#for-service-developers) — ship a change, create a service, configure infra
- [For platform maintainers](#for-platform-maintainers) — onboard a repo, change a gate, decommission
- [How it works](#how-it-works) — the pipeline, the four IAM roles, the agents
- [Repo layout](#repo-layout)
- [Status](#status)

---

## For service developers

### Ship a change

Everything happens through a normal PR. There is no separate deploy command.

```bash
git switch -c my-change
# ...edit...
git push -u origin HEAD
gh pr create --fill      # → gates run; ReviewBot/Triage comment on failure
gh pr checks --watch
gh pr merge --squash     # → deploy to dev → smoke test
gh run watch             # → parks on the prod Environment approval
```

Prod deploys only after a human clicks approve on the `prod` GitHub Environment. The
pipeline presents that approval; nothing approves it automatically.

The scaffold also ships `.claude/skills/{ship,watch}` — prompt-driven `gh` wrappers for
the same flow. There is no `paved` binary.

### Create a new service

```bash
cookiecutter templates/service      # from a clone of this repo
gh repo create <org>/<service> --public --source <service> --push
```

The generated repo is deliberately thin — its thinness is the point, not a TODO:

| File | You edit it? | What it is |
|---|---|---|
| `src/` | **yes** | Bun server: SPA + `/api/*` |
| `infra/config.yaml` | **yes** | The only infra file you touch — service name, `module_ref` pin, per-env sizing |
| `infra/main.tf` | no | Reads `config.yaml`, calls `modules/service`. Never hand-edit per environment |
| `.github/workflows/ci.yml` | no | ~30 lines calling this repo's `plan.yml` / `agents.yml` / `deploy.yml` at a pinned SHA |
| `infracost.yml` + `infracost-usage.yml` | usage only | Cost-diff PR comments. Without `infracost.yml` the usage file is silently ignored and cost always reports $0 |
| `.trivyignore` | rarely | Required — Trivy FATALs without one |

Then hand the repo to a platform maintainer for [onboarding](#onboard-a-service)
(IAM trust, ECR repo, branch protection). Until that lands, credentialed jobs will fail.

### Configure infra

`infra/config.yaml` is the whole interface. Write YAML, not Terraform:

```yaml
service: my-svc
module_ref: <paved-road commit SHA>   # bump via PR to upgrade the platform

defaults:                             # applied to every environment
  memory: 512
  timeout: 15
  log_retention_days: 14
  dynamodb_billing_mode: PAY_PER_REQUEST
  enable_cloudfront: true
  cloudfront_price_class: PriceClass_100

environments:
  dev: {}                             # override any default key per environment
  prod:
    memory: 1024
```

One stack serves both environments; CI selects which with `-var env=<env>` and a
per-service, per-environment state key
(`<repo>/<env>/terraform.tfstate`). Upgrading the platform means bumping `module_ref` in
a PR, like any other change.

Your Lambda gets `APP_ENV` and `APP_BUILD` (image digest) in its environment, so a
running service can report its own identity.

---

## For platform maintainers

### Onboard a service

`bootstrap/` is applied **locally by a human**, on purpose — a CI role able to onboard a
service is equally able to rewrite `deploy-prod`'s trust policy and delete the prod
approval gate. There is no setting in between. See
[`bootstrap/README.md`](bootstrap/README.md#why-bootstrap-stays-on-break-glass).

1. Add the service to `services` in `bootstrap/variables.tf`:

   ```hcl
   { name = "my-svc", repo = "my-svc", repo_id = "..." }   # gh api repos/<org>/<repo> --jq .id
   ```

   `repo_id` is required: GitHub's immutable subject claims put the numeric ID in the
   OIDC `sub`, and a trust policy written for the legacy name-only format denies every
   assume-role call.

2. Apply it, and paste the plan into the PR — there is no CI plan job for this stack, so
   that plan output *is* the review artifact:

   ```bash
   cd bootstrap && tofu plan && tofu apply
   ```

   This creates the service's ECR repo and extends all four IAM roles' trust conditions
   and resource ARNs. Log the apply in `bootstrap/README.md`'s break-glass log.

3. In the service repo's GitHub settings (enforcement has to live outside the diff a PR
   can edit):
   - required status checks on `main` for the gate jobs, plus a repo ruleset
   - CODEOWNERS review on `.github/`, `infra/`, `policies/`
   - `dev` and `prod` Environments, `prod` requiring a human reviewer
   - secrets: `NVIDIA_API_KEY` (agent inference), `INFRACOST_API_KEY`
     (`infracost ci setup --ci-pipeline`)

### Change a gate

Policies live in `policies/` as OPA/Rego across three namespaces. Run the unit suite
from the repo root:

```bash
conftest verify -p policies    # 28/28
```

**`conftest test` requires `--all-namespaces`.** Without it, it evaluates package `main`
only, every policy here is namespaced, and the gate reports "0 tests" and passes
trivially. This silently disabled two gates in CI once. Details and the full policy table:
[`policies/README.md`](policies/README.md).

Renaming `plan.yml`, `deploy.yml`, `agents.yml`, or the `tofu-plan` job **breaks IAM** —
each role's trust policy matches on `job_workflow_ref`, i.e. the workflow file's path.

### Decommission a service

Order matters, and getting it wrong orphans live AWS resources with unreachable state.
The checklist is in
[`bootstrap/README.md`](bootstrap/README.md#decommissioning-a-service--do-this-in-order):
destroy the service's own `infra/` (both envs) → remove it from `services` and apply →
delete the GitHub repo **last**.

---

## How it works

### The pipeline

**`plan.yml`** — runs on every PR, fork-isolated. Eight blocking gates:

| Gate | Checks |
|---|---|
| `lint-typecheck-test` | ESLint, `tsc`, `bun test` |
| `gitleaks` | committed secrets |
| `container-build-scan` | builds the image, Trivy CRITICAL |
| `tofu-validate` | runs credential-free |
| `tofu-plan` | assumes `plan-readonly`; uploads plan JSON |
| `conftest-terraform` | 6 policies against that plan JSON |
| `conftest-dockerfile` | no root user, digest-pinned `FROM` |
| `workflow-integrity` | no `pull_request_target` + untrusted checkout, all `uses:` SHA-pinned, no `write-all`, gates not deleted |

Plus two reporting-only jobs (`continue-on-error`): `sbom-license-scan` (Syft
CycloneDX), `coverage-bundle-report`. Cost diffs come from the service repo's own
`infracost-diff.yml`.

**`deploy.yml`** — on push to `main`: `deploy-dev` → `smoke-test-dev` → `narrate-dev` →
**`deploy-prod`** (blocks on the `prod` Environment reviewer) → `smoke-test-prod` →
`narrate-prod`. The image is built once in dev and promoted to prod by digest.

**`agents.yml`** — `agent-narrate` fires after gates, only on failure. ReviewBot/Triage
run on NVIDIA NIM's DeepSeek endpoint (Bedrock is blocked account-wide), post a
structured PR comment (**What failed** / **Error** / **Why** / **Fix** /
**Recommendations**), and write a row to the agent ledger table. `narrate-dev` /
`narrate-prod` remain no-op placeholders.

### Fork isolation

The OIDC `sub` claim is identical for a fork PR and a same-repo PR — IAM **cannot** tell
them apart. The real control is at the workflow layer: any job with
`id-token: write` is gated on
`github.event.pull_request.head.repo.full_name == github.repository`, and nothing uses
`pull_request_target` with an untrusted checkout. Verified live against a real fork PR
from a separate GitHub account (run `33069405789`): credentialed jobs skipped, no token
ever requested; every non-credentialed gate ran normally.

### Four IAM roles, four blast radii

One job class → one role → one boundary. Every trust policy matches **both** the OIDC
`sub` and `job_workflow_ref` — `sub` alone can't tell "can plan" from "can write".

| Role | Assumed by | Can |
|---|---|---|
| `plan-readonly` | same-repo PR, `plan.yml` | read/describe only |
| `deploy-dev` | push to `main`, `deploy.yml` | write `<svc>-dev-*` resources |
| `deploy-prod` | `environment:prod`, `deploy.yml` | write `<svc>-prod-*`; **unassumable until a human approves** |
| `agents-inference` | `agents.yml` | one allow-listed model + ledger `PutItem` |

Full table, blast-radius notes, and the trust-policy gotchas that cost real debugging
time: [`bootstrap/README.md`](bootstrap/README.md).

---

## Repo layout

| Path | What it is |
|---|---|
| `bootstrap/` | OIDC provider, the four IAM roles, S3+DynamoDB state backend, per-service ECR repos, agent ledger table. Break-glass, human-applied. **Read its README before touching trust policies.** |
| `modules/service/` | The runtime stack: arm64 container Lambda (Bun + Lambda Web Adapter) → `live` alias → Function URL (AWS_IAM) → CloudFront via OAC → DynamoDB. Config-driven inputs |
| `.github/workflows/` | The three reusable workflows service repos call: `plan.yml`, `deploy.yml`, `agents.yml` |
| `policies/` | 9 OPA/Conftest policies in three namespaces, 28 tests |
| `templates/service/` | The cookiecutter scaffold. `hello-world-svc` is its output |
| `docs/HISTORY.md` | Session-by-session build log — what broke live and why decisions went the way they did |

---

## Status

**Live and verified end-to-end on real infrastructure:** the full branch → gates → dev →
human-approved prod flow, fork isolation, policy gates blocking a real bad PR,
ReviewBot/Triage narration, per-service state isolation, cost-diff PR comments.

**Not built, by decision:**

- `cli/paved` — `ship`/`watch` are prompt-driven `gh` wrappers instead
- PR preview environments — cut; the org's Resource Control Policy blocks anonymous
  Lambda Function URLs, and the CloudFront workaround reintroduces the latency previews
  existed to avoid
- Release and Incident agents — documented design only; Release's job is already covered
  by the human Environment approval
- The incident/canary stack (scheduled-Lambda monitor + CloudWatch alarm) — design only

**Cost:** $0.0023 through 2026-08-28, live Cost Explorer month-to-date (ECR $0.0011, S3
$0.0011, DynamoDB $0.0001; everything else inside free tier). Guardrail ≤ $25, target
~$10.

Spec and rationale live in the planning workspace (`hops.ai-demo`) until final —
`DECISIONS.md` and `AI-GOVERNANCE.md` land here at the repo root once they're out of
draft.
