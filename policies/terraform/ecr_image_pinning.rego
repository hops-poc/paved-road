# PRD §7 / DECISIONS.md scenario 2: no unpinned image references. Two
# independent checks:
#   1. Any aws_ecr_repository must set image_tag_mutability = IMMUTABLE, so a
#      tag can't be silently repointed after CI scanned it.
#   2. Any Lambda image_uri must be digest-pinned (@sha256:...), not a bare
#      tag like `:latest` — mirrors the Dockerfile-level check in
#      policies/dockerfile/no_unpinned_base_image.rego, but this is the
#      terraform-plan-visible surface (what actually gets deployed).
package terraform.image_pinning

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	rc.change.after.image_tag_mutability != "IMMUTABLE"
	msg := sprintf("%s: image_tag_mutability must be IMMUTABLE, got %q", [rc.address, rc.change.after.image_tag_mutability])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_lambda_function"
	image_uri := rc.change.after.image_uri
	not contains(image_uri, "@sha256:")
	msg := sprintf("%s: image_uri %q is not digest-pinned (missing @sha256:)", [rc.address, image_uri])
}
