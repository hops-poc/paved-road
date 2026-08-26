# PRD §7 / DECISIONS.md scenario 7: mandatory cost-allocation tags. The `env`
# tag is how per-environment cost is attributed in Cost Explorer.
package terraform.tags

# Resource types this project tags for cost allocation. Kept to what
# modules/service/main.tf actually creates (or will, once tagging lands) —
# aws_s3_bucket is deliberately excluded here since the service module
# doesn't provision one.
taggable_types := {
	"aws_lambda_function",
	"aws_dynamodb_table",
	"aws_cloudfront_distribution",
}

deny contains msg if {
	some rc in input.resource_changes
	taggable_types[rc.type]
	rc.change.after != null
	not rc.change.after.tags.env
	msg := sprintf("%s: missing required tag 'env'", [rc.address])
}
