# Handoff: Retry Reliability and Runtime Contract Kernel

## Scope

This handoff covers the Codex PostToolUse retry failure, the first public
consumer-contract slice, and the non-authoritative Rust decision-kernel slice.
The full dynamic permission and provider enforcement objective remains active.

## Decisions

- ADR-0002 selects an incremental contract kernel behind the stable Python CLI.
- Rust output is `mode: shadow` and `authoritative: false`; no hook or executor
  consumes it for authorization.
- Invariant secret and external-mutation denials dominate grants.
- A positive shadow decision requires a matching active grant and a typed,
  provider-bound observed-enforcement record.
- `tonys-nix` consumes only versioned Home Manager/CLI fields and uses a stable
  repository URL; its GitHub lock cannot move until the harness revision is
  published.

## Commits

- `8c8c36a` — normalize provider retry responses without mutating state for an
  unknown valid provider response.
- `9145327` — expose versioned `validate`, `doctor`, `plan`, `export`, and
  `verify` contracts plus a Home Manager consumer contract.
- `a527b2a` — record PRD, ADR, acceptance criteria, validation, and rollback.
- `9ad66f2` — add the Rust shadow decision kernel, JSON CLI, tests, Cargo lock,
  and Nix package/check.

## Verification

- `python3 -m unittest discover -s tests -v`: 31 passed.
- `bats tests/hooks`: 130 passed.
- `shellcheck runtime/governance/retry-hook.sh`: passed.
- `nix flake check`: passed on `aarch64-darwin`.
- `cargo test --workspace --all-targets`: 11 passed.
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`:
  passed.
- `nix build .#checks.aarch64-darwin.contract-kernel --no-link`: passed.
- `tonys-nix` with `--override-input tonys-agent-harness
  path:/Users/vpplab/dev/tonys-agent-harness`: 41 flake checks passed.
- Performance observation, not an optimization claim: 50 `validate` processes
  completed in 1.79 seconds on the local host. No measured bottleneck justified
  a performance mutation.

## Current Consumer State

`/Users/vpplab/dev/tonys-nix` has scoped working-tree changes in `flake.nix` and
`tests/agent-config.check.nix`. Pre-existing user changes in
`modules/language/language.hm.nix`, `modules/shell/fish.hm.nix`, and coupled
Codex alias assertions remain uncommitted and must not be silently included.
The lock still points at `5586f3d`; the local override is the current consumer
evidence.

## Remaining Risks and Work

- Publishing `9ad66f2` (or a later reviewed revision) requires explicit push
  authority before `tonys-nix/flake.lock` can be updated reproducibly.
- Grant scope/end-condition semantics need typed transitions rather than
  nonempty strings.
- Directory enforcement needs at-use canonicalization/handle-based containment
  and symlink-race tests in an egress adapter.
- Network enforcement needs typed DNS resolution and redirect reauthorization.
- Python/Rust differential shadow execution and provider adapter mapping are
  not wired yet.
- Native apply/revoke/observe capability remains version/platform specific and
  must report unsupported rather than claiming active enforcement.
- Linux Nix systems were not built in this macOS session.

## Next Actions

1. Obtain explicit authorization to push the reviewed harness commits.
2. Update `tonys-nix/flake.lock` from the stable repository URL and rerun the
   no-update-lock-file and full consumer checks.
3. Stage only the stable URL and consumer-contract test hunks; exclude the
   pre-existing language/fish changes.
4. Add typed grant scope/operation/end-condition transitions and a read-only
   Python/Rust differential adapter before any authority cutover.
