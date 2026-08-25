# Fixtures inlined per the note in policies/terraform/tests/s3_public_access_test.rego
# (OPA's --data loader roots JSON/YAML by directory, not filename). These
# mirror tests/fixtures/Dockerfile.good and Dockerfile.bad_latest, expressed
# in the parsed instruction-array shape `--parser dockerfile` produces.
package dockerfile.base_image_test

import data.dockerfile.base_image.deny

good_instrs := [
	{"Cmd": "from", "Stage": 0, "Value": ["oven/bun:1.2.4-slim@sha256:c377a08d0711e47c23a8ad8cf9a924cf9abeae4c9031dfa56be2f1786e0f8ce7", "AS", "base"]},
	{"Cmd": "user", "Stage": 0, "Value": ["bun"]},
]

bad_instrs := [
	{"Cmd": "from", "Stage": 0, "Value": ["oven/bun:latest", "AS", "base"]},
	{"Cmd": "user", "Stage": 0, "Value": ["bun"]},
]

test_no_unpinned_base_image_denies_latest_tag if {
	count(deny) == 1 with input as bad_instrs
}

test_no_unpinned_base_image_allows_digest_pinned if {
	count(deny) == 0 with input as good_instrs
}
