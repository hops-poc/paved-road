# PRD §7 / DECISIONS.md scenario 5: no USER root in the final container
# stage. Same verified input shape as no_unpinned_base_image.rego.
#
# "Final stage" = the highest Stage number present (Stage increments once
# per FROM). Within that stage, the *last* USER instruction wins — a later
# USER overrides an earlier one, matching real Docker semantics. No USER
# instruction at all in the final stage defaults to root (Docker's own
# default), which is also denied.
package dockerfile.root_user

final_stage := max([s | s := input[_].Stage])

final_stage_users := [v |
	some i
	input[i].Stage == final_stage
	input[i].Cmd == "user"
	v := input[i].Value[0]
]

deny contains msg if {
	count(final_stage_users) > 0
	last_user := final_stage_users[count(final_stage_users) - 1]
	is_root(last_user)
	msg := sprintf("final stage runs as USER %q", [last_user])
}

deny contains msg if {
	count(final_stage_users) == 0
	msg := "final stage has no USER instruction — defaults to root"
}

is_root(u) if u == "root"

is_root(u) if u == "0"
