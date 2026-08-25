# PRD §7 / DECISIONS.md scenario 2: no unpinned image references in the
# shipped artifact's Dockerfile.
#
# Input shape verified live against conftest 0.69.0's `--parser dockerfile`
# (`conftest parse --parser dockerfile <file>`): a flat array of instruction
# objects, each `{"Cmd": "<lowercase instruction>", "Value": [...], "Stage":
# <int>, ...}`. `Stage` increments once per FROM (0-indexed).
#
# Known limitation (not hit by this project's Dockerfiles): a FROM that
# references a previous build stage by alias (`FROM builder AS final`)
# would false-positive here, since Value[0] is the alias, not an image ref.
# Not handled — YAGNI for a single-stage image.
package dockerfile.base_image

deny contains msg if {
	some i
	input[i].Cmd == "from"
	ref := input[i].Value[0]
	not contains(ref, "@sha256:")
	msg := sprintf("FROM %q is not pinned to a digest (missing @sha256:)", [ref])
}
