# See s3_public_access_test.rego for why fixtures are inlined rather than
# loaded via --data. This policy is `warn`, not `deny` — tests check `warn`.
package terraform.dynamodb_capacity_test

import data.terraform.dynamodb_capacity.warn

good_plan := {"resource_changes": [{
	"address": "aws_dynamodb_table.this",
	"type": "aws_dynamodb_table",
	"name": "this",
	"change": {"actions": ["create"], "before": null, "after": {"billing_mode": "PAY_PER_REQUEST"}},
}]}

bad_plan := {"resource_changes": [
	{
		"address": "aws_dynamodb_table.this",
		"type": "aws_dynamodb_table",
		"name": "this",
		"change": {"actions": ["update"], "before": {"billing_mode": "PAY_PER_REQUEST"}, "after": {"billing_mode": "PROVISIONED", "read_capacity": 5, "write_capacity": 5}},
	},
	{
		"address": "aws_lambda_provisioned_concurrency_config.this",
		"type": "aws_lambda_provisioned_concurrency_config",
		"name": "this",
		"change": {"actions": ["create"], "before": null, "after": {"qualifier": "live", "provisioned_concurrent_executions": 1}},
	},
]}

test_dynamodb_capacity_report_warns_on_provisioned_and_concurrency if {
	count(warn) == 2 with input as bad_plan
}

test_dynamodb_capacity_report_allows_good_plan if {
	count(warn) == 0 with input as good_plan
}
