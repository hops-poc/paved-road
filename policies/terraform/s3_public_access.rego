# PRD §7 / DECISIONS.md scenario 6: no public S3 buckets.
#
# Two independent failure modes:
#   1. A public_access_block resource exists but has one of its four booleans
#      set to false.
#   2. An aws_s3_bucket exists with no corresponding public_access_block at
#      all (so the account/bucket defaults apply instead of an explicit
#      block).
#
# Matching a bucket to "its" public_access_block: real plans resolve
# `aws_s3_bucket_public_access_block.bucket` to the bucket's computed id,
# which plan-JSON may not show pre-apply. We match by Terraform resource
# name (the label after the type) instead — i.e. `aws_s3_bucket.artifacts`
# pairs with `aws_s3_bucket_public_access_block.artifacts`. This is a
# convention this policy relies on, documented in policies/README.md.
package terraform.s3

pab_flags := {
	"block_public_acls",
	"block_public_policy",
	"ignore_public_acls",
	"restrict_public_buckets",
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	some flag in pab_flags
	rc.change.after[flag] == false
	msg := sprintf("%s: public_access_block has %s = false", [rc.address, flag])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket"
	not has_public_access_block(rc.name)
	msg := sprintf("%s: no aws_s3_bucket_public_access_block for this bucket", [rc.address])
}

has_public_access_block(bucket_name) if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	rc.name == bucket_name
}
