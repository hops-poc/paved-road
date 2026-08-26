# See s3_public_access_test.rego for why fixtures are inlined rather than
# loaded via --data.
package terraform.tags_test

import data.terraform.tags.deny

good_plan := {"resource_changes": [
	{
		"address": "aws_lambda_function.this",
		"type": "aws_lambda_function",
		"name": "this",
		"change": {"actions": ["create"], "after": {"tags": {"env": "dev"}}},
	},
	{
		"address": "aws_dynamodb_table.this",
		"type": "aws_dynamodb_table",
		"name": "this",
		"change": {"actions": ["create"], "after": {"tags": {"env": "dev"}}},
	},
]}

bad_plan := {"resource_changes": [
	{
		"address": "aws_lambda_function.this",
		"type": "aws_lambda_function",
		"name": "this",
		"change": {"actions": ["create"], "after": {"tags": {}}},
	},
	{
		"address": "aws_dynamodb_table.this",
		"type": "aws_dynamodb_table",
		"name": "this",
		"change": {"actions": ["create"], "after": {"tags": {}}},
	},
]}

test_cost_allocation_tags_denies_missing_env if {
	count(deny) == 2 with input as bad_plan
}

test_cost_allocation_tags_allows_good_plan if {
	count(deny) == 0 with input as good_plan
}
