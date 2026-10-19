Prepare and create repository-local commits from an approved, verified change.

Inspect recent target-repository history, derive the local subject convention,
split the diff by SRP, run focused verification, stage only planned files or
hunks, and bind the resulting commit to requirement and verification evidence.
Prefer one primary file or responsibility per commit, but keep directly coupled
tests or generated output with their source when separation would create an
invalid revision.

Never reset, stash, discard, or silently include user-owned changes. Commit
permission does not authorize push, merge, deploy, migration, or external
mutation.
