# PRD §7 / DECISIONS.md scenario 9: destroying a stateful resource requires
# an explicit ack. Data loss shouldn't be silently allowed or silently
# blocked forever — an override makes intent visible in the plan.
#
# Ack convention: a Terraform variable named `destroy_ack`, set true via
# `-var`/tfvars — same mechanism as `authorizer_exception` in
# function_url_auth.rego. See policies/README.md.
package terraform.destroy_ack

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_dynamodb_table"
	is_destructive(rc.change.actions)
	not destroy_ack
	msg := sprintf("%s: plan destroys a stateful resource without destroy_ack", [rc.address])
}

is_destructive(actions) if actions == ["delete"]

is_destructive(actions) if actions == ["delete", "create"]

is_destructive(actions) if actions == ["create", "delete"]

destroy_ack if {
	input.variables.destroy_ack.value == true
}
