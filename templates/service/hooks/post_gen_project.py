"""Point the generated ci.yml's `uses:` pins at the requested paved-road ref.

ci.yml has to sit in cookiecutter.json's `_copy_without_render` — its GitHub
Actions expression syntax collides with Jinja's — so its three
`uses: .../workflows/*.yml@<sha>` pins could not reference
`paved_road_ref` and drifted independently of it. Found live: a freshly
generated service pinned its reusable workflows to a SHA *older* than the
fix that scoped Terraform state per service, silently reintroducing the
shared-state-key collision that had already destroyed one environment.

One ref, one place. Rewritten here after copy instead of during render.
"""

import pathlib
import re
import sys

REF = "{{ cookiecutter.paved_road_ref }}"

# policies/workflows/workflow_integrity.rego rejects any `uses:` that is not a
# full 40-char SHA, so a branch name or short SHA here produces a service that
# cannot pass its own first gate. Fail at generation instead.
if not re.fullmatch(r"[a-f0-9]{40}", REF):
    sys.exit(
        f"paved_road_ref must be a full 40-char commit SHA, got: {REF!r}\n"
        "  cookiecutter templates/service paved_road_ref=$(git -C <paved-road> rev-parse HEAD)"
    )

ci = pathlib.Path(".github/workflows/ci.yml")
pinned, n = re.subn(
    r"(paved-road/\.github/workflows/[\w.-]+\.yml@)[a-f0-9]{40}",
    rf"\g<1>{REF}",
    ci.read_text(),
)
if n == 0:
    sys.exit(f"no paved-road workflow pins found in {ci} — template drift, refusing to generate")

ci.write_text(pinned)
print(f"pinned {n} paved-road workflow reference(s) in {ci} to {REF}")
