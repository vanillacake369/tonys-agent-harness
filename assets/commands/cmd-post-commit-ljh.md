Prepare and create repository-local commits from an approved, verified change.

1. Inspect the target repository's recent history and derive its subject style,
   scope vocabulary, and responsibility boundaries.
2. Compare the task scope, changed files, tests, and current Git baseline.
3. Propose SRP commits before staging. Prefer one primary file or responsibility;
   include directly coupled tests or generated output only when separating them
   would leave an invalid revision.
4. Run the focused verification for each proposed commit.
5. Stage only the planned files or hunks and create the commit using the target
   repository's established convention.
6. Record requirement IDs, verification evidence, resulting commit, and
   remaining uncommitted files.

Never reset, stash, discard, or silently include user-owned changes. A commit
does not authorize push, merge, release, deployment, migration, or any external
mutation.
