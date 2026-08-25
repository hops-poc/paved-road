# PRD §7 / DECISIONS.md scenario 8: DynamoDB capacity-mode changes are a
# cost signal, not a violation — report only. `warn` (not `deny`) so
# `conftest test`'s exit code stays 0 on this alone; verified against
# conftest 0.69.0 / OPA 1.19.0 that a warn-only result exits 0 while any
# deny exits 1.
package terraform.dynamodb_capacity

# This project's convention is on-demand (PAY_PER_REQUEST) billing —
# modules/service/main.tf's aws_dynamodb_table.this. A flip to PROVISIONED
# is a cost delta worth a human "intentional?" per DECISIONS.md §4.
warn contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_dynamodb_table"
	rc.change.after != null
	rc.change.after.billing_mode == "PROVISIONED"
	msg := sprintf("%s: billing_mode switched to PROVISIONED", [rc.address])
}

# Provisioned concurrency is an always-on cost adder; flag it appearing at
# all (a new aws_lambda_provisioned_concurrency_config being created).
warn contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_lambda_provisioned_concurrency_config"
	rc.change.actions[_] == "create"
	msg := sprintf("%s: adds provisioned concurrency", [rc.address])
}
