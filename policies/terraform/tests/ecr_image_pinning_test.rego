# See s3_public_access_test.rego for why fixtures are inlined rather than
# loaded via --data.
package terraform.image_pinning_test

import data.terraform.image_pinning.deny

good_plan := {"resource_changes": [{
	"address": "aws_lambda_function.this",
	"type": "aws_lambda_function",
	"name": "this",
	"change": {"actions": ["create"], "after": {"image_uri": "281832122084.dkr.ecr.us-east-1.amazonaws.com/hello-world-svc@sha256:1111111111111111111111111111111111111111111111111111111111111"}},
}]}

bad_plan := {"resource_changes": [
	{
		"address": "aws_ecr_repository.hello_world_svc",
		"type": "aws_ecr_repository",
		"name": "hello_world_svc",
		"change": {"actions": ["create"], "after": {"name": "hello-world-svc", "image_tag_mutability": "MUTABLE"}},
	},
	{
		"address": "aws_lambda_function.this",
		"type": "aws_lambda_function",
		"name": "this",
		"change": {"actions": ["create"], "after": {"image_uri": "281832122084.dkr.ecr.us-east-1.amazonaws.com/hello-world-svc:latest"}},
	},
]}

test_ecr_image_pinning_denies_mutable_repo_and_untagged_image if {
	count(deny) == 2 with input as bad_plan
}

test_ecr_image_pinning_allows_good_plan if {
	count(deny) == 0 with input as good_plan
}
