# PRD §7 / DECISIONS.md scenario 10: in-repo fast-feedback echo of the
# checks in .claude/skills/supply-chain-guard/scripts/scan-ci.sh, reimplemented
# as tested Rego against parsed workflow YAML. NOT the enforcement anchor —
# per DECISIONS.md §6 ("guarding the guards"), the anchor is a GitHub
# required-status-check ruleset outside this repo's diff, because a PR can
# edit or delete this policy in the same diff it's supposed to block.
#
# YAML gotcha verified live (conftest 0.69.0, `conftest parse`): an
# unquoted `on:` key is parsed as the YAML 1.1 boolean `true`, so the
# trigger block shows up in JSON as `input["true"]`, not `input.on`. Both
# are read below for robustness across YAML-lib versions.
package workflows.integrity

trigger_block := object.union(object.get(input, "on", {}), object.get(input, "true", {}))

all_steps contains step if {
	some job
	some step in input.jobs[job].steps
}

# --- Check 1: pull_request_target + checkout of untrusted PR head ---
deny contains msg if {
	object.get(trigger_block, "pull_request_target", "__absent__") != "__absent__"
	some step in all_steps
	startswith(step.uses, "actions/checkout")
	with_block := object.get(step, "with", {})
	contains(sprintf("%v", [with_block]), "github.event.pull_request.head")
	msg := "pull_request_target trigger combined with checkout of github.event.pull_request.head (untrusted fork checkout pattern)"
}

# --- Check 2: every `uses:` pinned to a full 40-char commit SHA ---
all_uses contains u if {
	some step in all_steps
	u := step.uses
}

all_uses contains u if {
	some job
	u := input.jobs[job].uses
}

deny contains msg if {
	some u in all_uses
	not startswith(u, "./") # local composite actions aren't versioned by ref
	not sha_pinned(u)
	msg := sprintf("action %q is not pinned to a full commit SHA", [u])
}

sha_pinned(u) if {
	parts := split(u, "@")
	count(parts) == 2
	regex.match("^[a-f0-9]{40}$", parts[1])
}

# --- Check 3: no write-all permissions, top-level or per-job ---
deny contains msg if {
	input.permissions == "write-all"
	msg := "workflow sets permissions: write-all"
}

deny contains msg if {
	some job
	input.jobs[job].permissions == "write-all"
	msg := sprintf("job %q sets permissions: write-all", [job])
}

# --- Check 4: the policy gate itself hasn't been deleted from the file ---
# Fast-feedback echo of scenario 10 ("CI file edited to remove the security
# stage"): at least one step must actually invoke conftest. This is a
# convention this project defines (not in a public conftest doc) precisely
# because the real anchor is the required-status-check ruleset, not this
# file — see the package comment above.
deny contains msg if {
	not any_step_runs_conftest
	msg := "workflow has no step that runs `conftest test`/`conftest verify` — the policy gate appears to have been removed"
}

any_step_runs_conftest if {
	some step in all_steps
	run := object.get(step, "run", "")
	contains(run, "conftest ")
}
