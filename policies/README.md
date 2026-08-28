# Policy-as-Code (PRD §7)

OPA/Conftest policies that gate `plan.yml`. Three namespaces, one parser each:

| Namespace | Input | Parser | Invocation |
|---|---|---|---|
| `terraform/` | `tofu show -json` plan JSON | default (`json`, by extension) | `conftest test -p policies/terraform --all-namespaces <plan.json>` |
| `dockerfile/` | a raw `Dockerfile` | `--parser dockerfile` | `conftest test --parser dockerfile -p policies/dockerfile --all-namespaces <Dockerfile>` |
| `workflows/` | workflow YAML | default (`yaml`, by extension) | `conftest test -p policies/workflows --all-namespaces <workflow.yml>` |

**`--all-namespaces` is required.** `conftest test` only evaluates package
`main` by default; every policy here is namespaced (`terraform.s3`,
`dockerfile.root_user`, `workflows.integrity`, etc.) so it can carry a
package-scoped test suite. Without the flag `conftest test` reports "0
tests" and passes trivially — verified against conftest 0.69.0 / OPA 1.19.0.

Unit tests (`conftest verify`) don't need the flag — it only affects `test`:

```
conftest verify -p policies/terraform
conftest verify -p policies/dockerfile
conftest verify -p policies/workflows
```

## Why fixtures are inlined in the `_test.rego` files, not loaded via `--data`

Each `tests/fixtures/*.json` / `*.yml` / `Dockerfile.*` is a real, standalone
fixture — useful on its own via `conftest test` (see the tables of
invocations below) and readable as "what does a good/bad plan actually look
like." The natural instinct is to also load them into the Rego unit tests
via `conftest verify --data tests/fixtures` and reference
`data.fixtures.plan_good` etc. **This doesn't work with a flat fixtures
directory**, verified empirically:

OPA's data loader roots JSON/YAML data files by **directory path only — the
filename is dropped**. `tests/fixtures/plan_good.json` and
`tests/fixtures/plan_bad_public_s3.json` both load to the *same* path
(`data.fixtures`, using the parent directory name), so two files there
collide with a merge error the moment there's more than one. (Splitting each
fixture into its own uniquely-named subdirectory would work, but that's not
the flat layout this suite uses, and adding N one-file directories per
policy is worse than the alternative below.)

So `conftest verify`'s `_test.rego` files inline a Rego copy of each
relevant fixture directly (valid JSON is valid Rego object/array syntax, so
the inline literal and the `.json`/parsed-YAML fixture are the same shape by
construction) and use `with input as <literal>`. The standalone fixture
files remain the integration-level check: `conftest test` against them
directly exercises the exact same documents through the real CLI path a CI
job would use. Both layers are run in CI; neither is redundant with the
other.

## Conventions this project defines

Two policies need a way to say "this violation is expected, let it through."
Both use the same mechanism: **a Terraform variable whose value is reflected
in the plan JSON's top-level `variables` block.** `tofu show -json` always
includes `-var`/tfvars input there regardless of whether any resource
actually references the variable, so it's visible to a plan-JSON policy
without inventing a resource-level tagging hack.

- **`function_url_auth.rego`** — `authorization_type = "NONE"` is denied
  unless `-var authorizer_exception=true` is set for that plan (i.e.
  `input.variables.authorizer_exception.value == true`). Doesn't apply to
  this project's actual `modules/service/main.tf`, which uses `AWS_IAM` —
  the exception exists for a future consumer of the module that has a
  legitimate reason to go public.
- **`stateful_destroy_ack.rego`** — a `delete` or `delete`+`create` (replace)
  action on `aws_dynamodb_table` is denied unless `-var destroy_ack=true` is
  set (`input.variables.destroy_ack.value == true`). Forces the destroy to
  be a visible, deliberate choice at plan time rather than something a
  gate silently allows or silently blocks forever.

## Policies

### `terraform/` (all `deny` except the last, which is `warn`)

| File | Denies when | Scenario |
|---|---|---|
| `s3_public_access.rego` | An `aws_s3_bucket_public_access_block` has any of its 4 booleans `false`, or an `aws_s3_bucket` has no matching block (matched by resource name — see file header) | 6 |
| `cost_allocation_tags.rego` | A taggable resource is missing `tags.env` | 7 |
| `ecr_image_pinning.rego` | An `aws_ecr_repository` isn't `image_tag_mutability = IMMUTABLE`, or a Lambda `image_uri` lacks `@sha256:` | 2 |
| `function_url_auth.rego` | `aws_lambda_function_url.authorization_type == "NONE"` without the `authorizer_exception` variable | — |
| `stateful_destroy_ack.rego` | An `aws_dynamodb_table` is deleted/replaced without the `destroy_ack` variable | 9 |
| `dynamodb_capacity_report.rego` (`warn`) | `billing_mode == "PROVISIONED"`, or a new `aws_lambda_provisioned_concurrency_config` is created | 8 |

### `dockerfile/` (all `deny`)

Input shape verified live via `conftest parse --parser dockerfile <file>`:
a flat array of `{"Cmd": "<lowercase instruction>", "Value": [...], "Stage":
<int>, ...}`. `Stage` increments once per `FROM` (0-indexed).

| File | Denies when | Scenario |
|---|---|---|
| `no_unpinned_base_image.rego` | Any `FROM` reference lacks `@sha256:` | 2 |
| `no_root_user.rego` | The final stage's last `USER` is `root`/`0`, or has no `USER` instruction at all (Docker's own default is root) | 5 |

### `workflows/` (all `deny`)

`workflow_integrity.rego` is fast feedback only — **not** the enforcement
anchor. Per `docs/DECISIONS.md` §6 ("guarding the guards"), a PR can edit or
delete this file in the same diff it's meant to block; the real anchor is a
GitHub required-status-check ruleset configured outside this repo's diff,
plus CODEOWNERS on `policies/`.

Denies when:
1. `pull_request_target` trigger + a `checkout` step referencing
   `github.event.pull_request.head` (untrusted fork checkout).
2. Any `uses:` (step-level or reusable-workflow job-level) isn't pinned to a
   full 40-hex-char commit SHA. Local composite actions (`uses: ./...`) are
   exempt — there's no ref to pin.
3. `permissions: write-all` appears at the workflow or job level.
4. No step anywhere in the file runs `conftest` at all — this project's own
   convention for catching "the security stage was deleted" (scenario 10) as
   fast feedback, on top of the three checks above that mirror
   `.claude/skills/supply-chain-guard/scripts/scan-ci.sh`.

**YAML gotcha, verified live:** an unquoted `on:` key parses under YAML 1.1
as the boolean `true`, so the trigger block appears in parsed JSON as
`input["true"]`, not `input.on`. The policy reads both.

## Verification

Run from `paved-road/`:

```
conftest verify -p policies/terraform   # 16 tests
conftest verify -p policies/dockerfile  # 6 tests
conftest verify -p policies/workflows   # 6 tests
```

All 28 pass as of this writing (conftest 0.69.0, OPA 1.19.0, installed via
`brew install conftest` — not in `devbox.json`; add it there before wiring
this into CI).
