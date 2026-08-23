# bootstrap

Creates the things nothing else can depend on: the GitHub OIDC trust, the S3
bucket every other stack's state lives in, and the four IAM roles GitHub
Actions assumes. Chicken-and-egg by nature, so it's the one stack that starts
on local state.

## Why these four roles, not one

One agent/job class → one role → one blast radius (PRD §8, §12). Nobody gets
"deploy" in general; each role can only do the one thing its job needs.

| Role | Assumed by | Trust condition (`sub`) | Can |
|---|---|---|---|
| `plan-readonly` | any same-repo PR job (`terraform plan`) | `repo:<org>/<repo>:pull_request` | Read/describe the services in §12 of the PRD. Nothing that mutates state. |
| `deploy-dev` | preview + dev deploy jobs | `repo:<org>/<repo>:pull_request` **and** `repo:<org>/<repo>:ref:refs/heads/main` | Write Lambda/DynamoDB/CloudFront/ECR resources named `hello-world-svc-{dev,pr-*}-*` |
| `deploy-prod` | prod deploy job, post-approval | `repo:<org>/<repo>:environment:prod` | Write resources named `hello-world-svc-prod-*`. **Unassumable until the GitHub Environment reviewer approves** — the environment-scoped `sub` composes the approval gate with IAM instead of leaving it purely in Actions config. |
| `agents-inference` | ReviewBot/Triage/Release/Incident | `pull_request`, `ref:refs/heads/main`, `environment:dev`, `environment:prod` | `bedrock:InvokeModel` on one allow-listed model + write to the ledger table. Nothing else — an agent identity is a credential like any other (DECISIONS.md §1). |

## The fork-isolation gap this doesn't close by itself — read before touching trust policies

GitHub's OIDC `sub` claim for a `pull_request`-triggered run is
`repo:<org>/<repo>:pull_request` **whether or not the PR is from a fork.**
There is no claim that distinguishes them (verified against GitHub's OIDC docs
— `ref`/`job_workflow_ref` carry the PR number, `sub` does not). So
`plan-readonly` and `deploy-dev`'s `pull_request` trust arm cannot be the
control that keeps a fork PR from assuming them — a fork PR presenting that
exact `sub` is indistinguishable, at the IAM layer, from a same-repo PR.

**The actual control is at the workflow layer, not this trust policy:** the
reusable workflow (`service.yml`, built in session 3) must never grant
`permissions: id-token: write` to a job that can run from a fork — gated on
`github.event.pull_request.head.repo.full_name == github.repository`, never
on `pull_request_target` with untrusted checkout (CLAUDE.md hard constraint).
This trust policy is layer two, not layer one. Scenario 11 (DECISIONS.md §5)
has to demonstrate *that* gate, not just quote this table. Session 3: wire it
and don't get this backwards.

## Bootstrapping the state backend from local state

1. `terraform init` (local backend, this stack only)
2. `terraform apply` — creates the OIDC provider, the `<org>-paved-road-tfstate`
   S3 bucket (versioned), the `paved-road-tfstate-lock` DynamoDB table, and
   the four roles
3. Uncomment the `backend "s3"` block in `main.tf`, then
   `terraform init -migrate-state` — moves bootstrap's own state into the
   bucket it just created. From here on every stack (`dev/`, `prod/`,
   `previews/pr-<n>/`, and this one) is S3-backed, per-stack state file
   (PRD §5.4).

DynamoDB lock table, not S3 native locking: pinned to Terraform 1.5.7 (last
MPL-licensed release, DECISIONS.md notes the BSL cut) which predates S3's
native `use_lockfile` locking (1.10+). PRD §5.4's "DynamoDB as fallback" is
what this actually is, not a fallback held in reserve.
