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
3. `tofu init -migrate-state` — the `backend "s3"` block in `main.tf` is now
   live (key `bootstrap/terraform.tfstate`, deliberately outside the
   `*/dev/*` and `*/prod/*` globs `deploy-dev`/`deploy-prod` are scoped to in
   `iam.tf`, so no CI role can read or write it). This moves bootstrap's own
   state into the bucket it created in step 2. From here on every stack
   (`dev/`, `prod/`, and this one) is S3-backed, per-stack state file
   (PRD §5.4). Until it runs, the only copy of bootstrap's state is the local
   `terraform.tfstate` — losing it means hand-importing ~20 resources to
   recover account control.

DynamoDB lock table, not S3 native locking: OpenTofu 1.8+ supports S3's
native `use_lockfile` locking, but DynamoDB is kept for now to avoid
a state migration mid-bootstrap. Can be dropped later once the bucket exists.

**This local apply is the one structural exception, not a precedent.** Once
`deploy.yml` exists, routine applies go through its OIDC-scoped roles; local
apply with a long-lived admin credential is break-glass only, invoked
explicitly by a human with the reason recorded (hops.ai-demo's
`CLAUDE.md` hard constraints, `DECISIONS.md` §3). `deploy-dev`'s trust and
permissions were narrowed the same way after PR previews were cut (dropped
the `pull_request` trust arm and all `pr-*`-named resource grants).

## Why bootstrap stays on break-glass

Not an unfinished chicken-and-egg leftover — a decision (`DECISIONS.md` §3).
Onboarding a service edits all four roles' trust policies, so any CI apply
role needs `iam:UpdateAssumeRolePolicy` on them, and AWS has no condition key
that constrains a trust policy's *content* (a permissions boundary bounds what
a role can do, not who can assume it). A role able to add a service is
therefore equally able to swap `deploy-prod`'s `environment:prod` subject for
`pull_request` and silently delete the human prod approval gate. Tighten the
boundary enough to stop that and onboarding stops too; there is no setting
in between. Break-glass survives either way — creating the apply role,
recovering a trust policy CI broke, clearing a stuck state lock — so CI apply
adds a second always-on, PR-reachable door rather than closing the first.
`infra/` is CI-applied because it's frequent, multi-author and rebuildable;
this stack has been applied six times ever (the initial apply plus the five
logged below), by one person, and it is the trust anchor for every service.

**Review convention for `bootstrap/**` PRs:** there is no CI plan job for this
stack, so the author runs `tofu plan` locally and pastes the output into the
PR description. That plan is the review artifact — a `bootstrap/` PR without
one can't be reviewed, only trusted.

## Decommissioning a service — do this in order

The first tic-tac-toe-svc decommission (below) only did step 2 — it removed
the service from `variables.tf` and tore down its ECR repo, but never touched
the service's own `infra/` state (Lambda, DynamoDB, CloudFront, exec role, in
both dev and prod). That state lived in the service's own repo, so deleting
the GitHub repo first orphaned it: the resources kept running, live, in AWS,
undetected until the same service was re-onboarded and its first deploy
inherited the leftover state. Correct order, every time:

1. **Destroy the service's own infra first**, both environments, from the
   service repo's `infra/` directory, against the *service's* state (not
   bootstrap's) — this is what was skipped:
   ```
   cd infra
   AWS_PROFILE=poc-user tofu init -backend-config="key=<service>/dev/terraform.tfstate" -reconfigure
   AWS_PROFILE=poc-user tofu destroy -var env=dev -var image_uri=placeholder
   # repeat with prod/terraform.tfstate and -var env=prod
   ```
2. **Remove the service from `variables.tf`'s `services` list and apply** —
   tears down its ECR repo (needs `force_delete = true` on
   `aws_ecr_repository.service`, see `ecr.tf` — an immutable-tag repo that
   ever received a push is never empty otherwise, and `tofu apply` fails
   mid-way with the trust/resource narrowing already done and only the ECR
   destroy left stuck) and narrows the 4 roles' trust/resource ARNs back to
   the remaining services.
3. **Delete the GitHub repo last**, only after 1 and 2 are both clean — it's
   the thing that makes the service's state unreachable, so it must go last,
   not first.

**Break-glass log:**
- Session 5: `aws_dynamodb_table.agent_ledger` (`ledger.tf`) — created the
  `hello-world-svc-agent-ledger` table that `agents_inference`'s
  `WriteLedgerOnly` statement already scoped a `PutItem` grant to, so
  ReviewBot/Triage have somewhere to write ledger rows (PRD §8 Tier 1).
  1 resource added, 0 changed, 0 destroyed.
- Session 5: `agents_inference_perms`'s `InvokeAllowlistedModelOnly`
  statement widened to the cross-region inference-profile ARN plus its
  three underlying regional foundation-model ARNs — found live, a real
  Triage-narration test run failed with `ValidationException: ... with
  on-demand throughput isn't supported`. `bedrock_model_id` also flipped
  from the bare foundation-model ID to the inference-profile ID
  (`us.anthropic.claude-haiku-4-5-20251001-v1:0`). 0 added, 1 changed, 0
  destroyed.
- Session 8: generalized bootstrap from a single hardcoded service
  (`hello-world-svc`) to a `services` list, to onboard a second real app
  (`tic-tac-toe-svc`) onto the platform — reason: demonstrate the paved
  road generalizes beyond the one demo service, not a one-off (paved-road#5).
  `aws_ecr_repository.service`/`aws_ecr_lifecycle_policy.service` moved to
  `for_each` (existing hello-world-svc repo state-moved, not recreated —
  `moved` blocks in `ecr.tf`); the 4 IAM roles' trust `sub` conditions and
  `deploy_dev`/`deploy_prod`'s named-resource ARN lists gained
  tic-tac-toe-svc arms/entries alongside the existing hello-world-svc ones.
  Ledger table deliberately left single/shared, not split per-service. 2
  added, 6 changed, 0 destroyed.
- Session 8: `deploy_dev_perms`/`deploy_prod_perms`'s `PassAndManageLambdaExecRole`
  statement gained `iam:ListInstanceProfilesForRole` — reason: tic-tac-toe-svc's
  first dev deploy shared hello-world-svc's `dev/terraform.tfstate` key
  (a separate bug, fixed in `plan.yml`/`deploy.yml`, paved-road#6) and
  destroyed most of hello-world-svc's live dev resources trying to
  reconcile them into tic-tac-toe-svc's — the destroy aborted partway
  through on this exact missing permission (DeleteRole's own precondition
  check), leaving `hello-world-svc-dev-exec` orphaned instead of cleanly
  replaced. Recovery documented in paved-road#6. 0 added, 2 changed, 0
  destroyed.
- Session 8: tic-tac-toe-svc decommissioned (demo scope decision, not a
  platform problem) — removed from `services` in `variables.tf`, tearing
  down its ECR repo and narrowing the 4 IAM roles' trust/resource ARNs
  back to hello-world-svc only. The `services` list mechanism itself
  stays — more services are coming and this is the intended path to add
  them. hello-world-svc untouched throughout. 0 added, 6 changed, 2
  destroyed.
- Session 8 (re-run): tic-tac-toe-svc re-onboarded to demonstrate the
  platform deploys arbitrary services, not just hello-world-svc — full
  branch→gates→dev→human-approved-prod flow re-verified live, then
  decommissioned again per the same demo-scope decision. This pass also
  applied the state-backend S3 scoping fix (`iam.tf`: `deploy-dev`/
  `deploy-prod`/`plan-readonly`'s bucket-wide grants split to per-env
  `*/dev/terraform.tfstate` and `*/prod/terraform.tfstate`) and migrated
  bootstrap's own state to S3 (`main.tf`) — see `DECISIONS.md` §3. Onboard
  apply: 2 added, 7 changed, 0 destroyed. Found live during re-onboarding:
  the *previous* decommission above never destroyed tic-tac-toe-svc's own
  `infra/` state (dev+prod Lambda/DynamoDB/CloudFront/exec role, 11
  resources each) — orphaned when its repo was deleted, silently still
  running in AWS this whole time, inherited by this pass's first deploy
  instead of being created fresh. This time: destroyed both environments'
  service infra explicitly (22 resources) *before* touching bootstrap —
  see "Decommissioning a service" above, added as a standing checklist so
  this doesn't repeat. Decommission apply: 0 added, 6 changed, 2 destroyed
  (ECR repo required `force_delete = true`, added to `ecr.tf`, plus a
  one-time manual `ecr batch-delete-image` since the flag can't retroactively
  apply to a resource being removed in the same apply). Also found and
  fixed: the cookiecutter template's `server.ts` was missing `development:
  false` on `Bun.serve()` — a fix `hello-world-svc` already carried but
  that never made it back into `templates/service/`, so tic-tac-toe-svc's
  first deploy hit the same "Blocked: Host header does not match the dev
  server" 403 hello-world-svc had already fixed. Backported to the template.
  hello-world-svc untouched throughout.
