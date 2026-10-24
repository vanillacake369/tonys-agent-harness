# Default-Allow Operations v1 Execution Log

Date: 2026-10-24

Authoritative specification:
[`docs/agent/spec/default-allow-operations-v1.md`](../spec/default-allow-operations-v1.md)

## Changes made

- Replaced the Codex-only selector with provider-neutral
  `default-allow-operations-v1` normalization and provider porters.
- Added the common classifier, denial feedback/telemetry, structural preflight,
  and stable managed-fragment synchronizer.
- Added stable fragment IDs, mutable JSON/TOML upsert, timestamped mode-0600
  backups (newest three), atomic replacement, schema migration, and rollback.
- Wired Codex, Claude, Gemini, and Kiro hooks; retained file-path invariants;
  installed all runtime dependencies through Home Manager.
- Added command-family, porter parity, privacy, preflight, preservation, repair,
  malformed-input, backup, and rollback tests.
- Marked the prior Codex PRD/ADR/testing workflow superseded.

## Verification commands and results

- `PATH=/Users/vpplab/.nix-profile/bin:$PATH python3 -m unittest discover -s tests -v`:
  PASS (53 tests).
- `PATH=/Users/vpplab/.nix-profile/bin:$PATH bats tests/hooks`: PASS (131 tests).
- `PATH=/Users/vpplab/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH just check`:
  PASS.
- `/nix/var/nix/profiles/default/bin/nix flake check`: PASS on aarch64-darwin;
  Linux checks were reported incompatible and omitted by Nix.
- `cargo test --manifest-path rust/contract-kernel/Cargo.toml`: PASS (26 tests).
- Nix parser check for every changed Nix module: PASS.
- Export/verify fixture smoke: PASS.
- Managed TOML preservation, mode, backup, and rollback smoke: PASS.
- Codex 0.162.1 native sandbox profile: workspace write, sibling `~/dev` read,
  secret-path denial, and network smoke PASS.
- Kiro 2.31.1 generated agent validation: PASS. Claude and Gemini binaries were
  unavailable locally; their generated native JSON shapes passed structural
  preflight fixtures.

## Independent review and repair

Read-only QA, reviewer, and guardrail agents found premature `ENFORCED` status,
substring-only preflight, incomplete managed ownership/rollback, Kiro hook
replacement and path-invariant gaps, missing runtime installation, and common
CLI option bypasses. Final review also found an ambient Python 3.9 activation
failure, incomplete exact matcher checks, and stale rollback snapshots. Targeted
repair loops replaced static enforcement with
`PENDING_PREFLIGHT`, added provider-native structural validation and exact
fragment ownership, completed rollback, preserved Kiro lists, restored path
invariants, pinned hook startup to the Nix-managed Python, refreshed snapshots
on user-owned field edits, installed dependencies, and expanded the fixtures.

## Residual risk and blockers

- This remains a documented default-allow accident-prevention rail. Computed,
  aliased, SDK, HTTP, MCP, browser, and otherwise unrecognized operations remain
  allowed by design.
- Native Claude/Gemini process smoke could not run because their binaries were
  not installed; activation remains `PENDING_PREFLIGHT` until their own
  SessionStart succeeds.
- Linux Nix checks were not runnable on this Darwin host.
- No unresolved implementation blocker is known. Downstream `tonys-nix`
  validation and publication are recorded after the harness commit is pushed.
