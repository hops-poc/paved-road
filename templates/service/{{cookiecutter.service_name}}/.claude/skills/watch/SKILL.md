---
name: watch
description: Tail a running pipeline and surface agent narration in the console. NOT BUILT — the narration it would surface is live and posted to the PR today.
---

# watch — not built

ReviewBot and Triage are live: `paved-road`'s `agents.yml` runs them on Bedrock and posts
AI-generated comments to the PR on gate failure, writing each action to the agent ledger
table. This skill would pull that into the console rather than the browser. Until it exists:

```bash
gh run watch                             # live job status
gh pr view --comments                    # ReviewBot / Triage narration
```

## What it needs to do when built

1. Tail the active run, one line per job, not a raw log dump.
2. Surface ReviewBot/Triage comments as they post, labelled as AI-generated (PRD §8.2).
3. Show the prod approval when the run parks on the `prod` Environment gate.

Not available to surface, because they are documented design only and not built: Release
and Incident agent narration, and preview URLs (previews are cut — DECISIONS.md §2).

Spec: PRD §11 (console DX).
