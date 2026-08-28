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
**Session 5:** full CI/CD live. Both repos flipped to public (required for rulesets and for the fork-isolation threat model to be real). `plan.yml`/`deploy.yml`/`agents.yml` and `policies/` (9 OPA/Conftest policies, 27 tests) authored and wired; `hello-world-svc` gets required status checks, a repo ruleset, CODEOWNERS, and `dev`/`prod` GitHub Environments (prod requires a human reviewer). The full branch → gates → dev → smoke test → human approval → prod → smoke test flow ran and passed end-to-end on real infrastructure. Along the way, ~10 real bugs surfaced only by a live run and got fixed: GitHub's immutable OIDC subject claims (IAM `sub` format changed for repos created after 2026-07-15), several missing IAM permissions on `deploy-dev`/`deploy-prod` (`ecr:GetAuthorizationToken`, `logs:DescribeLogGroups`, CloudFront OAC actions, IAM role-policy reads), an arm64/amd64 image mismatch, buildx's default provenance attestation breaking Lambda's `UpdateFunctionCode`, ECR tag immutability breaking retries, and Bun's dev-server Host-header check blocking CloudFront. Agent narration checkpoints (`agents-narrate`, `narrate-dev`, `narrate-prod`) were wired into the pipeline at the points a human needs them, as no-op placeholders at this point (real ReviewBot/Triage logic landed in session 7, below).
**Session 6:** PR preview environments cut — this AWS account's org-wide Resource Control Policy blocks anonymous Lambda Function URLs, which the original preview design required (raw Function URL, no CloudFront, for speed); a CloudFront-per-preview workaround reintroduces the ~10min provisioning latency previews existed to avoid, and a shared routing distribution breaks the thin-service goal. `deploy-dev`'s IAM trust and permissions narrowed to drop the `pull_request` trust arm and all `pr-*`-named resource grants (break-glass local apply, applied and verified live: 1 added/1 changed/1 destroyed). `cost_allocation_tags.rego`'s dead `tags.pr`/`tags.ttl` branch removed along with its test and fixture (`conftest verify` green). Full rationale: `hops.ai-demo/docs/DECISIONS.md`.
**Session 7:** `agents.yml`'s `agent-narrate` job now runs real ReviewBot/Triage on Bedrock (PRD §14 Tier 1: "ReviewBot + Triage on Bedrock; agent ledger") instead of the placeholder echo. The agent ledger table (`hello-world-svc-agent-ledger`, DynamoDB on-demand) was created in `bootstrap/` — `agents-inference`'s IAM policy already had `PutItem` scoped to it, waiting. Six real bugs surfaced live and got fixed: the Bedrock model ID needs the `us.*` cross-region inference-profile ARN, not the bare foundation-model ID; Anthropic's one-time account "use case" form (`PutUseCaseForModelAccess`) and a valid AWS Marketplace payment method are both required before any Anthropic model invokes, independent of IAM; a shell-injection hole where LLM-generated/log-derived text spliced via `${{ }}` into a `run:` script could execute as shell (fixed by routing through `env:`, per GitHub's hardening guidance); and three separate log-fetch bugs (`gh run view --log` refuses until the *whole* run completes, fatal since `agent-narrate` is itself part of that run; `gh` needs `--repo` when the job has no checkout to infer one from; `gh api` silently refuses to print any response containing escape sequences without `--allow-escape-sequences`). `cost_usd_est` now uses the verified real per-token rate from `list-foundation-model-agreement-offers` ($1.10/$5.50 per M tokens), not a guess. Confirmed end-to-end on a throwaway test PR: Triage correctly diagnosed a deliberate lint failure, cited the exact ESLint rule and line, and wrote an accurate ledger row. Release and Incident agents stay documented design only in `AI-GOVERNANCE.md` — Tier 1 doesn't require them, Release's job is already satisfied by the human GitHub Environment approval, and Incident would be bolted onto `RUNBOOK.md`'s already-recorded manual alias flip. Narration was then restructured from unstructured prose into scannable sections (**What failed** / **Error** in a fenced code block / **Why** / **Fix** / **Recommendations**, each omitted rather than padded if it has nothing to add) — a real bug surfaced during that pass: the prompt-building `jq` call was missing `-r`, so Bedrock had been receiving a JSON-quoted string (literal `"..."` and `\n` escapes) instead of the actual prompt text since the feature landed.
**Session 8:** Fork-isolation scenario (PRD §14 Tier 1, never cut) live-verified — the one Tier-1 item that no unit test can substitute for. Forked `hello-world-svc` to a genuinely separate GitHub account (`quorumless/hello-world-svc`) and opened `hops-poc/hello-world-svc#16` from it. Result: `plan.yml`'s `tofu-plan`/`conftest-terraform` and `agents.yml`'s `agent-narrate` all ran `completed/skipped` — the `head.repo.full_name` fork gate held, no OIDC token was ever requested, let alone denied. Every non-credentialed gate (lint/typecheck/test, gitleaks, Trivy, tofu validate, dockerfile/workflow-integrity policy, SBOM/coverage/infracost reporting) ran and passed normally. PR closed without merging, test branch and fork both deleted; run `33069405789` is the permanent evidence, cited in `hops.ai-demo/docs/DECISIONS.md` §5 scenario 11.
**Session 9:** `.claude/skills/{ship,watch}` (PRD §11, G1 — console DX, the last Tier 1 gap) built as prompt-driven `gh` wrappers, not a `cli/paved` binary. Live-tested twice end-to-end on real PRs (`hello-world-svc#17`, `#19`): branch → gates → dev → smoke test → human-approved prod → prod → smoke test, a human clicking the actual GitHub Environment approval each time. Testing surfaced two real, previously-undetected gate bugs via a live `USER root` scenario (`demo/scenario-5-root-user`, `hello-world-svc#18`, closed without merge): `conftest-dockerfile` and `workflow-integrity` were both silently running **zero** policies in CI (`conftest test` defaults to the `main` package only without `--all-namespaces`; every rule here lives under a named package) — masked because `conftest verify`'s unit tests don't exercise the same code path as `conftest test`. Fixed (`3b76cc9`), which then exposed a second latent bug: `workflow-integrity`'s own "gate not removed" self-check only recognized an inline `run: conftest ...` step, not this project's actual `uses: .../plan.yml@SHA` reusable-workflow call — fixed (`33e3b52`, new test, 28/28 green) and re-verified live (run `33151397406`: `final stage runs as USER "root"`, correctly blocked). Full story in `hops.ai-demo/docs/DECISIONS.md` §5 scenario 5. Also re-quoted the final bill via a live, read-only Cost Explorer query (below), and recorded both the happy path and the corrected blocked scenario via asciinema (`hops.ai-demo/docs/recordings/`).

- `bootstrap/` — GitHub OIDC provider, the four per-purpose IAM roles (`plan-readonly`,
  `deploy-dev`, `deploy-prod`, `agents-inference`), the shared Terraform state backend
  (`hops-poc-paved-road-tfstate` S3 bucket + `paved-road-tfstate-lock` DynamoDB table), the
  shared ECR repo (`hello-world-svc`, one immutable digest promoted dev→prod), and the agent
  ledger table (`hello-world-svc-agent-ledger`, DynamoDB on-demand).
  See `bootstrap/README.md` before touching trust policies.
- `templates/service/` — the cookiecutter scaffold. `hello-world-svc` is its output;
  the generated repo's thinness is the product demo, not a placeholder.
- `modules/service/` — the reusable runtime stack: arm64 container Lambda (Bun + Lambda Web
  Adapter) behind a `live` alias → Function URL (AWS_IAM) → CloudFront via OAC → DynamoDB.
  A service's `infra/{dev,prod}` are thin callers. Function URL grants both
  `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction` (required since Oct 2025).
- `.github/workflows/` — the three reusable workflows: `plan.yml` (blocking + reporting gates,
  fork-isolated), `deploy.yml` (dev deploy → smoke test → narrate-dev, human-approved prod
  deploy → smoke test → narrate-prod), `agents.yml` (the `agent-narrate` checkpoint after
  gates — real ReviewBot/Triage on Bedrock, posting AI-generated PR comments and writing to
  the ledger table on gate failures; `narrate-dev`/`narrate-prod` stay no-op placeholders —
  Release/Incident are documented design only, PRD §14 Tier 1 scope).
- `policies/` — 9 OPA/Conftest policies across three namespaces (`terraform/`, `dockerfile/`,
  `workflows/`), 28 tests, `conftest verify -p policies` → 28/28. See `policies/README.md`.

## Not built

- `cli/paved` — not started; `ship`/`watch` are prompt-driven `gh` wrappers instead (Session 9).
  Fork isolation and scenario 5 are live-verified via real PRs (Sessions 8–9), each closed and
  deleted after — no `demo/*` branch is left standing in either repo.
- The incident/canary stack (scheduled-Lambda monitor + CloudWatch alarm) behind
  `hops.ai-demo/docs/RUNBOOK.md` — design only, not built.
- Release and Incident agent logic — documented design only, by decision (PRD §14 Tier 1
  scope). Release's job is already covered by the human GitHub Environment approval.

## Final bill

$0.0023 through 2026-08-28, live Cost Explorer month-to-date (ECR $0.0011, S3 $0.0011,
DynamoDB $0.0001; everything else inside free tier). Guardrail: ≤ $25, target ~$10.
