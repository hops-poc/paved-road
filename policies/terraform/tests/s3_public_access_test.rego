# Fixtures below are inlined copies of tests/fixtures/plan_good.json and
# tests/fixtures/plan_bad_public_s3.json. They're inlined rather than loaded
# via `conftest verify --data` because OPA's data loader roots JSON files by
# *directory path only* — the filename is dropped — so multiple flat files
# under tests/fixtures/ collide if loaded that way (verified empirically
# against conftest 0.69.0 / OPA 1.19.0; see policies/README.md). The JSON
# files remain useful on their own via `conftest test`, exercised directly.
package terraform.s3_test

import data.terraform.s3.deny

good_plan := {"resource_changes": [
	{
		"address": "aws_dynamodb_table.this",
		"type": "aws_dynamodb_table",
		"name": "this",
		"change": {"actions": ["create"], "after": {"billing_mode": "PAY_PER_REQUEST", "tags": {"env": "dev"}}},
	},
	{
		"address": "aws_lambda_function.this",
		"type": "aws_lambda_function",
		"name": "this",
		"change": {"actions": ["create"], "after": {"image_uri": "281832122084.dkr.ecr.us-east-1.amazonaws.com/hello-world-svc@sha256:1111111111111111111111111111111111111111111111111111111111111", "tags": {"env": "dev"}}},
	},
]}

bad_plan_false_flag := {"resource_changes": [
	{
		"address": "aws_s3_bucket.artifacts",
		"type": "aws_s3_bucket",
		"name": "artifacts",
		"change": {"actions": ["create"], "after": {"bucket": "hops-artifacts"}},
	},
	{
		"address": "aws_s3_bucket_public_access_block.artifacts",
		"type": "aws_s3_bucket_public_access_block",
		"name": "artifacts",
		"change": {"actions": ["create"], "after": {
			"bucket": "hops-artifacts",
			"block_public_acls": true,
			"block_public_policy": false,
			"ignore_public_acls": true,
			"restrict_public_buckets": true,
		}},
	},
]}

bad_plan_no_pab := {"resource_changes": [{
	"address": "aws_s3_bucket.orphan",
	"type": "aws_s3_bucket",
	"name": "orphan",
	"change": {"actions": ["create"], "after": {"bucket": "hops-orphan"}},
}]}

test_s3_public_access_denies_false_flag if {
	count(deny) == 1 with input as bad_plan_false_flag
}

test_s3_public_access_denies_missing_pab if {
	count(deny) == 1 with input as bad_plan_no_pab
}

test_s3_public_access_allows_good_plan if {
	count(deny) == 0 with input as good_plan
}
