# Build log

Session-by-session record of how `paved-road` was built, what broke live, and why
each decision went the way it did. Moved here from `README.md`; the text is unchanged.

Full rationale for the platform-level decisions lives in the planning workspace
(`hops.ai-demo/docs/DECISIONS.md`).

---

## Session 1

Scaffold and bootstrap authored, verified locally.

## Session 2

Both repos pushed to `github.com/hops-poc`.

## Session 3

Bootstrap applied to AWS — IAM roles and state backend live (account `281832122084`, `us-east-1`).

## Session 4

Runtime live — shared ECR repo added to bootstrap; `modules/service` authored;
`hello-world-svc`'s dev + prod stacks applied. Both serve the SPA and `/api/*`
through CloudFront.

## Session 5

Full CI/CD live. Both repos flipped to public (required for rulesets and for the
fork-isolation threat model to be real). `plan.yml`/`deploy.yml`/`agents.yml` and
`policies/` (9 OPA/Conftest policies, 27 tests) authored and wired; `hello-world-svc`
gets required status checks, a repo ruleset, CODEOWNERS, and `dev`/`prod` GitHub
Environments (prod requires a human reviewer). The full branch → gates → dev → smoke
test → human approval → prod → smoke test flow ran and passed end-to-end on real
infrastructure. Along the way, ~10 real bugs surfaced only by a live run and got
fixed: GitHub's immutable OIDC subject claims (IAM `sub` format changed for repos
created after 2026-07-15), several missing IAM permissions on `deploy-dev`/`deploy-prod`
(`ecr:GetAuthorizationToken`, `logs:DescribeLogGroups`, CloudFront OAC actions, IAM
role-policy reads), an arm64/amd64 image mismatch, buildx's default provenance
attestation breaking Lambda's `UpdateFunctionCode`, ECR tag immutability breaking
retries, and Bun's dev-server Host-header check blocking CloudFront. Agent narration
checkpoints (`agents-narrate`, `narrate-dev`, `narrate-prod`) were wired into the
pipeline at the points a human needs them, as no-op placeholders at this point (real
ReviewBot/Triage logic landed in session 7, below).

## Session 6

PR preview environments cut — this AWS account's org-wide Resource Control Policy
blocks anonymous Lambda Function URLs, which the original preview design required (raw
Function URL, no CloudFront, for speed); a CloudFront-per-preview workaround
reintroduces the ~10min provisioning latency previews existed to avoid, and a shared
routing distribution breaks the thin-service goal. `deploy-dev`'s IAM trust and
permissions narrowed to drop the `pull_request` trust arm and all `pr-*`-named resource
grants (break-glass local apply, applied and verified live: 1 added/1 changed/1
destroyed). `cost_allocation_tags.rego`'s dead `tags.pr`/`tags.ttl` branch removed along
with its test and fixture (`conftest verify` green). Full rationale:
`hops.ai-demo/docs/DECISIONS.md`.

## Session 7

`agents.yml`'s `agent-narrate` job now runs real ReviewBot/Triage on Bedrock (PRD §14
Tier 1: "ReviewBot + Triage on Bedrock; agent ledger") instead of the placeholder echo.
The agent ledger table (`hello-world-svc-agent-ledger`, DynamoDB on-demand) was created
in `bootstrap/` — `agents-inference`'s IAM policy already had `PutItem` scoped to it,
waiting. Six real bugs surfaced live and got fixed: the Bedrock model ID needs the
`us.*` cross-region inference-profile ARN, not the bare foundation-model ID; Anthropic's
one-time account "use case" form (`PutUseCaseForModelAccess`) and a valid AWS
Marketplace payment method are both required before any Anthropic model invokes,
independent of IAM; a shell-injection hole where LLM-generated/log-derived text spliced
via `${{ }}` into a `run:` script could execute as shell (fixed by routing through
`env:`, per GitHub's hardening guidance); and three separate log-fetch bugs
(`gh run view --log` refuses until the *whole* run completes, fatal since
`agent-narrate` is itself part of that run; `gh` needs `--repo` when the job has no
checkout to infer one from; `gh api` silently refuses to print any response containing
escape sequences without `--allow-escape-sequences`). `cost_usd_est` now uses the
verified real per-token rate from `list-foundation-model-agreement-offers` ($1.10/$5.50
per M tokens), not a guess. Confirmed end-to-end on a throwaway test PR: Triage
correctly diagnosed a deliberate lint failure, cited the exact ESLint rule and line, and
wrote an accurate ledger row. Release and Incident agents stay documented design only in
`AI-GOVERNANCE.md` — Tier 1 doesn't require them, Release's job is already satisfied by
the human GitHub Environment approval, and Incident would be bolted onto `RUNBOOK.md`'s
already-recorded manual alias flip. Narration was then restructured from unstructured
prose into scannable sections (**What failed** / **Error** in a fenced code block /
**Why** / **Fix** / **Recommendations**, each omitted rather than padded if it has
nothing to add) — a real bug surfaced during that pass: the prompt-building `jq` call
was missing `-r`, so Bedrock had been receiving a JSON-quoted string (literal `"..."`
and `\n` escapes) instead of the actual prompt text since the feature landed.

## Session 8

Fork-isolation scenario (PRD §14 Tier 1, never cut) live-verified — the one Tier-1 item
that no unit test can substitute for. Forked `hello-world-svc` to a genuinely separate
GitHub account (`quorumless/hello-world-svc`) and opened `hops-poc/hello-world-svc#16`
from it. Result: `plan.yml`'s `tofu-plan`/`conftest-terraform` and `agents.yml`'s
`agent-narrate` all ran `completed/skipped` — the `head.repo.full_name` fork gate held,
no OIDC token was ever requested, let alone denied. Every non-credentialed gate
(lint/typecheck/test, gitleaks, Trivy, tofu validate, dockerfile/workflow-integrity
policy, SBOM/coverage/infracost reporting) ran and passed normally. PR closed without
merging, test branch and fork both deleted; run `33069405789` is the permanent evidence,
cited in `hops.ai-demo/docs/DECISIONS.md` §5 scenario 11.

## Session 9

`.claude/skills/{ship,watch}` (PRD §11, G1 — console DX, the last Tier 1 gap) built as
prompt-driven `gh` wrappers, not a `cli/paved` binary. Live-tested twice end-to-end on
real PRs (`hello-world-svc#17`, `#19`): branch → gates → dev → smoke test →
human-approved prod → prod → smoke test, a human clicking the actual GitHub Environment
approval each time. Testing surfaced two real, previously-undetected gate bugs via a
live `USER root` scenario (`demo/scenario-5-root-user`, `hello-world-svc#18`, closed
without merge): `conftest-dockerfile` and `workflow-integrity` were both silently
running **zero** policies in CI (`conftest test` defaults to the `main` package only
without `--all-namespaces`; every rule here lives under a named package) — masked
because `conftest verify`'s unit tests don't exercise the same code path as
`conftest test`. Fixed (`3b76cc9`), which then exposed a second latent bug:
`workflow-integrity`'s own "gate not removed" self-check only recognized an inline
`run: conftest ...` step, not this project's actual `uses: .../plan.yml@SHA`
reusable-workflow call — fixed (`33e3b52`, new test, 28/28 green) and re-verified live
(run `33151397406`: `final stage runs as USER "root"`, correctly blocked). Full story in
`hops.ai-demo/docs/DECISIONS.md` §5 scenario 5. Also re-quoted the final bill via a
live, read-only Cost Explorer query, and recorded both the happy path and the corrected
blocked scenario via asciinema (`hops.ai-demo/docs/recordings/`).

## Session 10

Bedrock inference blocked account-wide — `invoke-model` returned `ValidationException`
Error 002 ("Access to Bedrock models is not allowed for this account"), an account-level
block rather than an IAM or model-access-request issue. Swapped ReviewBot/Triage's
inference call to NVIDIA NIM's DeepSeek endpoint (`build.nvidia.com`, OpenAI-compatible,
free preview tier, model `deepseek-ai/deepseek-v4-pro-0813`, `paved-road@2c60b35`).
Ledger schema unchanged; `cost_usd_est` now `0` since this tier isn't metered.

## Session 11

Service infra made config-driven for the developer-facing "write yaml, not Terraform"
goal. `modules/service` gained
`memory`/`timeout`/`log_retention_days`/`dynamodb_billing_mode`/`cloudfront_price_class`
inputs (defaults match the prior hardcoded values) and its `Project` tag now uses
`name_prefix` instead of a hardcoded literal, so the module is actually reusable across
services (`paved-road#1`). The cookiecutter scaffold now generates one `infra/main.tf`
(never hand-edited) and `infra/config.yaml` (the only file a developer touches) per
service, replacing the old `infra/dev`/`infra/prod` pattern of two hand-copied ~58-line
files with the module ref pinned separately in each. `plan.yml`/`deploy.yml` moved from
`infra/dev`/`infra/prod` working directories to a single `infra/`, selecting environment
via `-var env=...` + `-backend-config="key=<env>/terraform.tfstate"`.
`hello-world-svc` migrated live (`hello-world-svc#22`): verified zero resource drift
before merging (PR-time plan showed only the expected placeholder-image-digest diff),
then a real `deploy-dev` → smoke test → human-approved `deploy-prod` → smoke test ran
clean end-to-end on the new pattern. Follow-up (`paved-road#2`) pointed the scaffold's
default `paved_road_ref` at the proven commit instead of a placeholder.

## Session 12

`modules/service`'s Lambda now exposes `APP_ENV`/`APP_BUILD` (`paved-road#4`) — reuses
the module's existing `env`/`image_uri` inputs, no new Terraform variables or
`deploy.yml` changes needed. `hello-world-svc` added a `/api/version` endpoint and
renders `env: <env> · build: <short digest>` on the homepage (`hello-world-svc#24`,
falls back to `local`/`dev` when the vars are unset), then bumped its `module_ref` pin to
`076cb75` (`hello-world-svc#25`) and deployed through the real pipeline to both dev and
prod. Confirmed live: dev returns `env: dev`, prod returns `env: prod`, both
`build: 3bb08e77cba4`.

## Session 13

Infracost's `plan.yml` job (live since session 3) turned out to be silently broken — its
cost breakdown only ever reached raw CI logs, never a PR comment or job summary.
Investigating further found the product had moved on entirely: the classic
static-API-key + `breakdown` CLI is deprecated, dashboard-issued static keys are gone
(now via `infracost ci setup`/CLI OAuth login), and the v2 CLI doesn't auto-discover
`infracost-usage.yml` without an explicit `infracost.yml` project config pointing at it.
Removed the dead `infracost-report` job from `plan.yml` (`paved-road@6417385`) and
replaced it with `infracost/actions/diff` — real PR cost-diff comments — scaffolded into
both `hello-world-svc` and the cookiecutter template (`paved-road@44643b2`, `@662129f`)
so future services get it by default. Filled `infracost-usage.yml` with real
very-low-traffic assumptions and added the missing `infracost.yml`; verified live, the
PR comment now shows real FinOps/tagging policy findings and a real cost delta
(`hello-world-svc#26`–`#28`).

## Session 14

Two small fixes, both in `infra/main.tf` for `hello-world-svc` and the cookiecutter
template. `default_tags` (`Service`/`Environment`) added to the AWS provider so
Infracost Cloud's FinOps tagging policy passes without per-resource tags in
`modules/service` (`paved-road@a6cdbce`, `hello-world-svc@9b35963`) — verified live via
`hello-world-svc#30`, which bumped Lambda memory to 1024MB to force a real plan diff and
confirm the tag fix and cost-diff reporting together. Separately, `hello-world-svc` and
the template each got a minimal `devbox.json` (`bun`, `gh`) + `.envrc` so a service
developer gets a `direnv allow`-activated dev shell without depending on the platform
workspace's devbox — `hello-world-svc#31`, merged.

## Session 15

Onboarded a second service (`tic-tac-toe-svc`) to prove the platform generalizes, not a
one-off. `bootstrap/` generalized from one hardcoded service to a `services` list
(`paved-road#5`) — per-service ECR repos via `for_each`, IAM trust/resource ARNs looped
across the list, ledger table deliberately kept single/shared. That onboarding surfaced
two real bugs: the cookiecutter template's `ci.yml` was stale (missing `agents-narrate`'s
required `gates_result` input/secrets) and had no `.trivyignore` at all (Trivy FATALs
without one) — both fixed in the template.

Bigger find: the deploy backend's Terraform state key was `<env>/terraform.tfstate`,
shared bucket-wide instead of per-service — `tic-tac-toe-svc`'s first dev deploy read
`hello-world-svc`'s live dev state as drift and destroyed most of it (Lambda, DynamoDB
table, log group, function URL, permissions) before an unrelated missing
`iam:ListInstanceProfilesForRole` permission stopped the destroy partway through. Prod
was never touched (separate key, verified healthy throughout). Fixed the key scheme to
`${{ github.event.repository.name }}/<env>/terraform.tfstate` and the missing IAM
permission (`paved-road#6`); recovered `hello-world-svc`'s dev environment by migrating
its surviving resources (CloudFront distribution, OAC, exec role) onto the new key via
`tofu state mv`/`push`, then a real `deploy-dev` → human-approved `deploy-prod` run
through `hello-world-svc#33` recreated what was destroyed — verified live, same
CloudFront domain, zero further drift.

`tic-tac-toe-svc` was then decommissioned as a demo-scope decision (not a platform
problem): AWS resources destroyed, removed from bootstrap's `services` list
(`paved-road#7`), GitHub repo deleted. The `services` list mechanism stays for the next
real service.
