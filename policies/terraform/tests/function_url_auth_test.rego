# See s3_public_access_test.rego for why fixtures are inlined rather than
# loaded via --data.
package terraform.function_url_test

import data.terraform.function_url.deny

good_plan := {
	"variables": {"authorizer_exception": {"value": false}},
	"resource_changes": [{
		"address": "aws_lambda_function_url.this",
		"type": "aws_lambda_function_url",
		"name": "this",
		"change": {"actions": ["create"], "after": {"qualifier": "live", "authorization_type": "AWS_IAM"}},
	}],
}

bad_plan := {"resource_changes": [{
	"address": "aws_lambda_function_url.this",
	"type": "aws_lambda_function_url",
	"name": "this",
	"change": {"actions": ["create"], "after": {"qualifier": "live", "authorization_type": "NONE"}},
}]}

exception_plan := {
	"variables": {"authorizer_exception": {"value": true}},
	"resource_changes": [{
		"address": "aws_lambda_function_url.this",
		"type": "aws_lambda_function_url",
		"name": "this",
		"change": {"actions": ["create"], "after": {"qualifier": "live", "authorization_type": "NONE"}},
	}],
}

test_function_url_auth_denies_none_without_exception if {
	count(deny) == 1 with input as bad_plan
}

test_function_url_auth_allows_none_with_annotated_exception if {
	count(deny) == 0 with input as exception_plan
}

test_function_url_auth_allows_good_plan if {
	count(deny) == 0 with input as good_plan
}
