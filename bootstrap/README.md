# bootstrap

Creates the things nothing else can depend on: the GitHub OIDC trust, the S3
bucket every other stack's state lives in, and the four IAM roles GitHub
Actions assumes. Chicken-and-egg by nature, so it's the one stack that starts
on local state.

## Why these four roles, not one

One agent/job class → one role → one blast radius (PRD §8, §12). Nobody gets
"deploy" in general; each role can only do the one thing its job needs.

`sub` alone can't tell `plan-readonly` and `deploy-dev` apart either — both
would otherwise trust the same `repo:<org>/<repo>:pull_request` subject,
which would let a plan-only job assume the write-capable role. Every role
also requires a `job_workflow_ref` match, naming which reusable workflow
*file* in `paved-road` the calling job actually runs — that's the real
separator between "can plan" and "can write." See `iam.tf`'s trust-policy
comments for the file-path convention this commits session 3 to.

| Role | Assumed by | Trust condition (`sub` **and** `job_workflow_ref`) | Can |
|---|---|---|---|
| `plan-readonly` | any same-repo PR job (`tofu plan`) | `pull_request` + `plan.yml` | Read/describe the services in §12 of the PRD. Nothing that mutates state. |
| `deploy-dev` | dev deploy job | `ref:refs/heads/main` + `deploy.yml` | Write Lambda/DynamoDB/ECR/logs/CloudWatch-alarm resources named `hello-world-svc-dev-*`, plus CloudFront distribution management (unscopable by ARN pre-create — action list is the actual boundary there). |
| `deploy-prod` | prod deploy job, post-approval | `environment:prod` + `deploy.yml` | Same shape, `hello-world-svc-prod-*` only. **Unassumable until the GitHub Environment reviewer approves** — the environment-scoped `sub` composes the approval gate with IAM instead of leaving it purely in Actions config. |
| `agents-inference` | ReviewBot/Triage/Release/Incident | `pull_request`/`ref:refs/heads/main`/`environment:{dev,prod}` + `agents.yml` | `bedrock:InvokeModel` on one allow-listed model + write to the ledger table. Nothing else — an agent identity is a credential like any other (DECISIONS.md §1). |

**Blast-radius note, fixed after review:** `deploy-dev`/`deploy-prod`'s
scopable actions (`lambda:*`, `dynamodb:*`, `ecr:*`, `logs:*`,
`cloudwatch:<alarm-actions>`) sit in statements with only named-resource
ARNs — never in the same action list as a `"*"` resource. CloudFront is the
one service genuinely unscopable pre-create (`CreateDistribution` requires
`Resource: "*"` — an AWS API constraint), so its statement narrows the
*action list* instead: only distribution-lifecycle calls, resource `"*"`.
An earlier draft combined `lambda:*`/`dynamodb:*`/`ecr:*` with a blanket
`"*"` resource in one statement, which — because IAM resource lists union,
not intersect — silently granted account-wide write on those services
regardless of the named ARNs listed alongside it (dev could delete prod).
Don't recombine them for convenience later.

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

1. `tofu init` (local backend, this stack only)
2. `tofu apply` — creates the OIDC provider, the `<org>-paved-road-tfstate`
   S3 bucket (versioned), the `paved-road-tfstate-lock` DynamoDB table, and
   the four roles
3. Uncomment the `backend "s3"` block in `main.tf`, then
   `tofu init -migrate-state` — moves bootstrap's own state into the
   bucket it just created. From here on every stack (`dev/`, `prod/`,
   and this one) is S3-backed, per-stack state file (PRD §5.4).

DynamoDB lock table, not S3 native locking: OpenTofu 1.8+ supports S3's
native `use_lockfile` locking, but DynamoDB is kept for now to avoid
a state migration mid-bootstrap. Can be dropped later once the bucket exists.

**This local apply is the one structural exception, not a precedent.** Once
`deploy.yml` exists, routine applies go through its OIDC-scoped roles; local
apply with a long-lived admin credential is break-glass only, invoked
explicitly by a human with the reason recorded (hops.ai-demo's
`CLAUDE.md` hard constraints, `DECISIONS.md` §3). `deploy-dev`'s trust and
permissions were narrowed the same way after PR previews were cut (dropped
the `pull_request` trust arm and all `pr-*`-named resource grants) — `bootstrap/`
still has no CI apply route of its own.

**Break-glass log:**
- Session 5: `aws_dynamodb_table.agent_ledger` (`ledger.tf`) — created the
  `hello-world-svc-agent-ledger` table that `agents_inference`'s
  `WriteLedgerOnly` statement already scoped a `PutItem` grant to, so
  ReviewBot/Triage have somewhere to write ledger rows (PRD §8 Tier 1).
  1 resource added, 0 changed, 0 destroyed.
