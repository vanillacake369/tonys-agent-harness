# Historical Framework MVP implementation report

This report captures the 2026-10-19 extraction baseline. Its command counts and
repository state are historical evidence and do not establish current completion.

## Result

The provider-neutral harness now lives in its own repository. It accepts a
project-owned `docs/agent/harness.toml`, validates mandatory policy, and exports
deterministic Codex, Claude, Gemini, and Kiro adapter bundles. Export does not
activate provider configuration or mutate external systems.

## Safety boundary

- Core policy cannot be weakened by project configuration.
- Existing output is replaced only when its manifest carries the harness
  ownership marker and valid inventory structure.
- Reviewer and researcher write permissions remain disabled.
- Production, destructive, migration, and external mutations require approval.
- Claude MCP calls pass through the MCP authorization gate.
- Gemini and Kiro tool results feed the persistent retry budget.
- Runtime scripts preserve executable modes and verification checks those modes.
- Every selected provider receives the same project instruction bytes; the
  instruction digest participates in stale-output detection and a standalone
  provider gate rejects drift.

## Extraction state

`tonys-nix/modules/agents` remains intact as a compatibility source. Removing it
is deliberately deferred until this repository has a versioned remote reference
and `tonys-nix` consumes that version. Machine-specific MCP credentials and Home
Manager activation remain consumer responsibilities.

## Verification

See `docs/agent/traceability.tsv` for requirement-level links. The final command
results were:

- `python3 -m unittest discover -s tests -v` -> 21 tests passed.
- `python3 -m compileall -q harness.py runtime/governance tests` -> exit 0.
- `nix flake check` -> all checks passed on `aarch64-darwin`; Linux systems were
  omitted by the local-system check.
- `git diff --check` -> exit 0.

The framework was initially left uncommitted because commit and publication
were outside the extraction scope. A later, explicit release operation must
rerun the full verification suite, audit the publication inventory, and record
the resulting commit and remote URL before treating the standalone repository
as a versioned consumer source.
