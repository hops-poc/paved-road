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
**Session 5:** full CI/CD live. Both repos flipped to public (required for rulesets and for the fork-isolation threat model to be real). `plan.yml`/`deploy.yml`/`agents.yml` and `policies/` (9 OPA/Conftest policies, 27 tests) authored and wired; `hello-world-svc` gets required status checks, a repo ruleset, CODEOWNERS, and `dev`/`prod` GitHub Environments (prod requires a human reviewer). The full branch → gates → dev → smoke test → human approval → prod → smoke test flow ran and passed end-to-end on real infrastructure. Along the way, ~10 real bugs surfaced only by a live run and got fixed: GitHub's immutable OIDC subject claims (IAM `sub` format changed for repos created after 2026-07-15), several missing IAM permissions on `deploy-dev`/`deploy-prod` (`ecr:GetAuthorizationToken`, `logs:DescribeLogGroups`, CloudFront OAC actions, IAM role-policy reads), an arm64/amd64 image mismatch, buildx's default provenance attestation breaking Lambda's `UpdateFunctionCode`, ECR tag immutability breaking retries, and Bun's dev-server Host-header check blocking CloudFront. Agent narration checkpoints (`agents-narrate`, `narrate-dev`, `narrate-prod`) are wired into the pipeline at the points a human needs them, but the jobs are still no-op placeholders — real ReviewBot/Triage logic lands session 7 (Release/Incident stay documented design only, PRD §14 Tier 1 scope).
**Session 6:** PR preview environments cut — this AWS account's org-wide Resource Control Policy blocks anonymous Lambda Function URLs, which the original preview design required (raw Function URL, no CloudFront, for speed); a CloudFront-per-preview workaround reintroduces the ~10min provisioning latency previews existed to avoid, and a shared routing distribution breaks the thin-service goal. `deploy-dev`'s IAM trust and permissions narrowed to drop the `pull_request` trust arm and all `pr-*`-named resource grants (break-glass local apply, applied and verified live: 1 added/1 changed/1 destroyed). `cost_allocation_tags.rego`'s dead `tags.pr`/`tags.ttl` branch removed along with its test and fixture (`conftest verify` still 16/16). Full rationale: `hops.ai-demo/docs/DECISIONS.md`.
**Session 7:** `agents.yml`'s `agent-narrate` job now runs real ReviewBot/Triage on Bedrock (PRD §14 Tier 1: "ReviewBot + Triage on Bedrock; agent ledger") instead of the placeholder echo. The agent ledger table (`hello-world-svc-agent-ledger`, DynamoDB on-demand) was created in `bootstrap/` — `agents-inference`'s IAM policy already had `PutItem` scoped to it, waiting. Six real bugs surfaced live and got fixed: the Bedrock model ID needs the `us.*` cross-region inference-profile ARN, not the bare foundation-model ID; Anthropic's one-time account "use case" form (`PutUseCaseForModelAccess`) and a valid AWS Marketplace payment method are both required before any Anthropic model invokes, independent of IAM; a shell-injection hole where LLM-generated/log-derived text spliced via `${{ }}` into a `run:` script could execute as shell (fixed by routing through `env:`, per GitHub's hardening guidance); and three separate log-fetch bugs (`gh run view --log` refuses until the *whole* run completes, fatal since `agent-narrate` is itself part of that run; `gh` needs `--repo` when the job has no checkout to infer one from; `gh api` silently refuses to print any response containing escape sequences without `--allow-escape-sequences`). `cost_usd_est` now uses the verified real per-token rate from `list-foundation-model-agreement-offers` ($1.10/$5.50 per M tokens), not a guess. Confirmed end-to-end on a throwaway test PR: Triage correctly diagnosed a deliberate lint failure, cited the exact ESLint rule and line, and wrote an accurate ledger row. Release and Incident agents stay documented design only in `AI-GOVERNANCE.md` — Tier 1 doesn't require them, Release's job is already satisfied by the human GitHub Environment approval, and Incident would be bolted onto `RUNBOOK.md`'s already-recorded manual alias flip. Narration was then restructured from unstructured prose into scannable sections (**What failed** / **Error** in a fenced code block / **Why** / **Fix** / **Recommendations**, each omitted rather than padded if it has nothing to add) — a real bug surfaced during that pass: the prompt-building `jq` call was missing `-r`, so Bedrock had been receiving a JSON-quoted string (literal `"..."` and `\n` escapes) instead of the actual prompt text since the feature landed.

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
  `workflows/`), 27 tests, run via `conftest verify`/`conftest test`. See `policies/README.md`.

`cli/paved` and `scenarios/` (`demo/*` branches, fork-isolation) land in later sessions — see
the effort plan. Release/Incident agent logic stays documented design only (PRD §14 Tier 1 scope).

## Final bill

TBD — filled in during the polish pass, per the budget guardrail (≤ $25, target ~$10).
