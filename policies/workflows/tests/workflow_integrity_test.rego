# Fixtures inlined per the note in
# policies/terraform/tests/s3_public_access_test.rego. Mirror
# tests/fixtures/ci_*.yml, expressed in the parsed-YAML shape conftest
# produces (verified live — note the `"true"` key for an unquoted `on:`,
# a YAML 1.1 gotcha).
package workflows.integrity_test

import data.workflows.integrity.deny

good_wf := {
	"name": "plan",
	"true": {"pull_request": null},
	"permissions": {"contents": "read"},
	"jobs": {
		"lint-typecheck-test": {"runs-on": "ubuntu-latest", "steps": [
			{"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"},
			{"run": "bun test"},
		]},
		"policy-gate": {"runs-on": "ubuntu-latest", "steps": [
			{"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"},
			{"run": "conftest test -p policies/terraform --all-namespaces plan.json"},
		]},
	},
}

bad_missing_gate := {
	"name": "plan",
	"true": {"pull_request": null},
	"permissions": {"contents": "read"},
	"jobs": {"lint-typecheck-test": {"runs-on": "ubuntu-latest", "steps": [
		{"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"},
		{"run": "bun test"},
	]}},
}

bad_pull_request_target := {
	"name": "plan",
	"true": {"pull_request_target": null},
	"permissions": {"contents": "read"},
	"jobs": {"lint-typecheck-test": {"runs-on": "ubuntu-latest", "steps": [
		{"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683", "with": {"ref": "${{ github.event.pull_request.head.sha }}"}},
		{"run": "conftest test -p policies/terraform --all-namespaces plan.json"},
	]}},
}

bad_unpinned_action := {
	"name": "plan",
	"true": {"pull_request": null},
	"permissions": {"contents": "read"},
	"jobs": {"lint-typecheck-test": {"runs-on": "ubuntu-latest", "steps": [
		{"uses": "actions/checkout@v4"},
		{"run": "conftest test -p policies/terraform --all-namespaces plan.json"},
	]}},
}

bad_write_all := {
	"name": "plan",
	"true": {"pull_request": null},
	"permissions": "write-all",
	"jobs": {"lint-typecheck-test": {"runs-on": "ubuntu-latest", "steps": [
		{"uses": "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"},
		{"run": "conftest test -p policies/terraform --all-namespaces plan.json"},
	]}},
}

test_workflow_integrity_denies_missing_gate if {
	count(deny) == 1 with input as bad_missing_gate
}

test_workflow_integrity_denies_pull_request_target_with_head_checkout if {
	count(deny) == 1 with input as bad_pull_request_target
}

test_workflow_integrity_denies_unpinned_action if {
	count(deny) == 1 with input as bad_unpinned_action
}

test_workflow_integrity_denies_write_all if {
	count(deny) == 1 with input as bad_write_all
}

test_workflow_integrity_allows_good_workflow if {
	count(deny) == 0 with input as good_wf
}
