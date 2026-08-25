# See s3_public_access_test.rego for why fixtures are inlined rather than
# loaded via --data.
package terraform.destroy_ack_test

import data.terraform.destroy_ack.deny

good_plan := {"resource_changes": [{
	"address": "aws_dynamodb_table.this",
	"type": "aws_dynamodb_table",
	"name": "this",
	"change": {"actions": ["create"], "before": null, "after": {"billing_mode": "PAY_PER_REQUEST"}},
}]}

bad_plan := {
	"variables": {"destroy_ack": {"value": false}},
	"resource_changes": [{
		"address": "aws_dynamodb_table.this",
		"type": "aws_dynamodb_table",
		"name": "this",
		"change": {"actions": ["delete"], "before": {"billing_mode": "PAY_PER_REQUEST"}, "after": null},
	}],
}

acked_plan := {
	"variables": {"destroy_ack": {"value": true}},
	"resource_changes": [{
		"address": "aws_dynamodb_table.this",
		"type": "aws_dynamodb_table",
		"name": "this",
		"change": {"actions": ["delete"], "before": {"billing_mode": "PAY_PER_REQUEST"}, "after": null},
	}],
}

replace_plan := {"resource_changes": [{
	"address": "aws_dynamodb_table.this",
	"type": "aws_dynamodb_table",
	"name": "this",
	"change": {"actions": ["delete", "create"], "before": {"billing_mode": "PAY_PER_REQUEST"}, "after": {"billing_mode": "PAY_PER_REQUEST", "hash_key": "pk2"}},
}]}

test_stateful_destroy_ack_denies_delete_without_ack if {
	count(deny) == 1 with input as bad_plan
}

test_stateful_destroy_ack_denies_replace_without_ack if {
	count(deny) == 1 with input as replace_plan
}

test_stateful_destroy_ack_allows_delete_with_ack if {
	count(deny) == 0 with input as acked_plan
}

test_stateful_destroy_ack_allows_good_plan if {
	count(deny) == 0 with input as good_plan
}
