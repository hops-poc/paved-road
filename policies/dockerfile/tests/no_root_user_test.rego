# See no_unpinned_base_image_test.rego for why fixtures are inlined.
package dockerfile.root_user_test

import data.dockerfile.root_user.deny

good_instrs := [
	{"Cmd": "from", "Stage": 0, "Value": ["oven/bun:1.2.4-slim@sha256:c377a08d0711e47c23a8ad8cf9a924cf9abeae4c9031dfa56be2f1786e0f8ce7", "AS", "base"]},
	{"Cmd": "user", "Stage": 0, "Value": ["bun"]},
]

bad_instrs_explicit_root := [
	{"Cmd": "from", "Stage": 0, "Value": ["oven/bun:1.2.4-slim@sha256:c377a08d0711e47c23a8ad8cf9a924cf9abeae4c9031dfa56be2f1786e0f8ce7", "AS", "base"]},
	{"Cmd": "user", "Stage": 0, "Value": ["root"]},
]

bad_instrs_no_user := [{"Cmd": "from", "Stage": 0, "Value": ["oven/bun:1.2.4-slim@sha256:c377a08d0711e47c23a8ad8cf9a924cf9abeae4c9031dfa56be2f1786e0f8ce7", "AS", "base"]}]

multistage_instrs := [
	{"Cmd": "from", "Stage": 0, "Value": ["golang:1.22@sha256:1111111111111111111111111111111111111111111111111111111111111", "AS", "builder"]},
	{"Cmd": "user", "Stage": 0, "Value": ["root"]}, # root in the builder stage is fine — not final
	{"Cmd": "from", "Stage": 1, "Value": ["oven/bun:1.2.4-slim@sha256:c377a08d0711e47c23a8ad8cf9a924cf9abeae4c9031dfa56be2f1786e0f8ce7"]},
	{"Cmd": "user", "Stage": 1, "Value": ["bun"]},
]

test_no_root_user_denies_explicit_root if {
	count(deny) == 1 with input as bad_instrs_explicit_root
}

test_no_root_user_denies_missing_user_instruction if {
	count(deny) == 1 with input as bad_instrs_no_user
}

test_no_root_user_allows_nonroot if {
	count(deny) == 0 with input as good_instrs
}

test_no_root_user_allows_root_in_non_final_stage if {
	count(deny) == 0 with input as multistage_instrs
}
