Start the project engineering workflow through the deterministic router.

1. Load the configured project policy, PRD, traceability, and existing evidence.
2. Let the internal deterministic router classify risk, uncertainty, blast
   radius, and reversibility.
3. Select only the lifecycle skills required by the route:
   `skl-pre-*`, `skl-mid-*`, and `skl-post-*`.
4. Pass the internal policy gate before any mutation.
5. Finish through the internal evidence/completion gate or return a structured
   blocked result.

For code verification, run `python3 modules/agents/governance/record-verification.py
--repo <repo> --output <new-evidence-path-outside-repo> --baseline <task-start-commit> --requirement <FR-ID>
-- <verification-command>`. The installed equivalent is under
`~/.config/agents/governance/`. Do not edit the recorded output to claim success.
Then call `completion-gate.sh --repo <repo> --mode code --scope <scope-file>
--evidence <evidence-file>`. A passing test with uncommitted changes is verified
work-in-progress, not DONE. Test changes requiring independent review remain
blocked. Research/design uses `--mode design` and explicit artifact evidence.

This command is a facade. Specialist skills are not independent mutation
entrypoints.
