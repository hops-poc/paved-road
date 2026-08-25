# PRD §7: Function URL auth type must be explicit — NONE only via an
# annotated exception. modules/service/main.tf uses AWS_IAM (see its own
# comment: this AWS Organization's Resource Control Policy blocks anonymous
# Function URLs account-wide), so a plan showing NONE is the bad case.
#
# Exception convention: a Terraform variable named `authorizer_exception`,
# set true via `-var`/tfvars. `tofu show -json` always reflects `-var`/
# tfvars input in the plan's top-level `variables` block regardless of
# whether any resource references it, so this is visible to the policy
# without needing a resource-level tag hack. Documented in
# policies/README.md alongside the matching `destroy_ack` convention.
package terraform.function_url

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_lambda_function_url"
	rc.change.after.authorization_type == "NONE"
	not authorizer_exception
	msg := sprintf("%s: authorization_type = NONE without an authorizer_exception variable", [rc.address])
}

authorizer_exception if {
	input.variables.authorizer_exception.value == true
}
