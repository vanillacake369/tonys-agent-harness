# Handoff: Runtime Contract and Consumer Migration

## Outcome

The PostToolUse retry failure is fixed, public CLI/Home Manager contracts are
versioned and producer-tested, and `tonys-nix` consumes those contracts without
inspecting hook filenames or activation script text. Its flake uses a stable
repository URL and keeps the harness revision in `flake.lock` only.

The Rust kernel remains an explicit non-authoritative shadow. It now models
typed directory/network operations, task/session lease scope, expiry/revocation,
`ALLOW|ASK|DENY`, and desired/applied/observed provider reconciliation. It is
not connected to an authorization path. Kernel contract v2 binds revoke,
wall-clock expiry, task-end, and session-end transitions to termination
evidence and rejects v1 wire requests before parsing their obsolete grant
schema.

## Decisions

- Hooks are ingress adapters, not a filesystem or network security boundary.
- Unknown valid tool responses do not mutate retry state.
- Secret access and external mutation denials dominate matching grants.
- Positive shadow decisions require matching active scope and observed
  enforcement evidence.
- Codex runtime grant mutation is `unsupported`/`unenforceable` until a
  version-bound native apply/revoke/observe contract is proven.
- Provider rendering, applied configuration, and observed enforcement are
  distinct states.

## Harness Commits

- `8c8c36a` — normalize provider retry response shapes.
- `9145327` — expose versioned CLI and Home Manager consumer contracts.
- `a527b2a` — record PRD, ADR, validation, and rollback.
- `9ad66f2` — introduce the non-authoritative Rust decision kernel.
- `cbb5698` — type grant scope, operations, lease endings, and targets.
- `30b319a` — model terminal grant revoke/expiry transitions.
- `d06a1d3` — document and report unsupported Codex dynamic grants.
- `6616950` — reconcile desired/applied/observed provider state.
- `ef6f918` — structurally evaluate the producer consumer contract.
- `b9243c3` — bind lease-end events and evidence under kernel contract v2.
- `2620099` — freeze typed Python/Rust decision fixture conformance.

## Consumer Commit

- `tonys-nix` `9beae07` — stable harness URL, lock revision `30b319a`, and
  consumer-only public contract checks.

The consumer intentionally locks the latest published implementation needed by
its public contract. Later harness shadow/capability commits are not required by
that consumer contract.

## Verification

- Harness Python: 32 tests passed.
- Harness Bats: 130 tests passed, including retry shape normalization.
- Rust: 26 tests passed across CLI, decision, lifecycle, fixture conformance,
  and reconciliation.
- Rust formatting and Clippy with warnings denied: passed.
- Harness `nix flake check`: passed on `aarch64-darwin`.
- `tonys-nix nix flake check --no-update-lock-file`: passed, including profile
  checks and Home Manager activation package builds.
- Independent QA, review, and guardrail: no blocker for the committed
  incremental scope.

## Preserved User Work

The following `tonys-nix` changes remain outside commit `9beae07`:

- `modules/language/language.hm.nix`
- `modules/shell/fish.hm.nix`
- three coupled Codex package/alias assertions in
  `tests/agent-config.check.nix`

They must remain grouped if the user later chooses to commit them.

## Remaining Full-Objective Work

- Wire runtime read-only Python/Rust comparison; typed shared-fixture
  conformance is committed, but it does not yet invoke both implementations in
  one observation path.
- Implement an outbound canonical-resource boundary that rechecks filesystem
  paths/symlinks at use time.
- Implement exact network DNS and redirect reauthorization in an enforcement
  adapter or brokered executor.
- Add version-bound apply/revoke/observe probes for each provider.
- Keep unsupported providers `UNENFORCEABLE`; do not cut over authorization
  until native enforcement and rollback are independently verified.
- Run Linux Nix builds in the supported CI environments.

## Rollback

Revert `tonys-nix` lock revision to the previous published harness commit.
Rust is not authoritative, so disabling/removing the shadow package does not
change current authorization behavior. If future enforcement fails, revoke the
affected leases and fall back to least-privilege `ASK|DENY`.
