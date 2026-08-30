---
name: ship
description: Push a change through the paved road (branch → gates → dev → human-approved prod) without leaving the console. NOT BUILT — the pipeline it would wrap is live; only this console wrapper is missing.
---

# ship — not built

The pipeline this skill would drive is live via `.github/workflows/ci.yml`. What is
missing is only the console wrapper. Until it exists, drive the road with `gh`:

```bash
git switch -c <branch> && git commit && git push -u origin HEAD
gh pr create --fill                      # triggers the gates + agent narration
gh pr checks --watch                     # lint/test/gitleaks/trivy/conftest/tofu plan
gh pr merge --squash                     # merge to main → deploy → dev → smoke test
gh run watch                             # prod waits on the `prod` Environment reviewer
```

## What it needs to do when built

1. Branch, commit, push, open the PR.
2. Surface gate results as they land — pass/fail per gate, not raw log tails.
3. On failure, show the ReviewBot/Triage PR comment inline instead of making the
   developer open GitHub.
4. Merge on the human's explicit yes; never merge on its own (PRD §8.2).
5. Hand off to the `prod` GitHub Environment approval — **present** it, never approve
   it. Approval is recorded under the human's identity, not the agent's.

Preview environments are **cut** (`paved-road`'s DECISIONS.md §2) — the flow is
branch → gates → dev → human approval → prod, with no preview step.

Spec: PRD §11 (console DX), G1 (ship without leaving the console).
