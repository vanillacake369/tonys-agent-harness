# ADR-0002: Incremental Rust Contract Kernel for Scoped Permissions

## Status

Accepted for phased implementation.

## Context

The current Python CLI already separates ingress, domain, control-plane, and
provider rendering, and it reconciles generated desired/observed digests.
Runtime policy remains split across Python and shell, provider-native observed
state is not part of reconciliation, and scoped directory/network grants do not
exist. Consumer tests also inspect Home Manager activation implementation.

## Independent Strategies

- Strategy A proposed a strangler migration to a Rust core with explicit ports,
  grant leases, provider probes, and phased native enforcement.
- Strategy B proposed a smaller subprocess contract kernel behind the existing
  Python CLI, explicit rather than resident reconciliation, and physical ports
  only at nondeterministic boundaries.

## Claim Classification

- `AGREEMENT`: preserve CLI and Phase 0–5 contracts; use one policy authority;
  keep adapters thin; bind grants to task/session/role; separate network access
  from external mutation; require observed enforcement for positive status.
- `COMPLEMENTARY`: native sandbox adapters and scoped executors may coexist
  behind one outbound enforcement contract.
- `CONFLICT`: none material. The possible breadth of the Rust migration is
  resolved by starting with the smaller contract kernel.
- `UNVERIFIED`: provider runtime permission mutation/reload APIs, reliable
  network redirect enforcement per provider, and their platform-specific
  observed-state probes.

## Decision

Adopt a versioned, pure Rust contract kernel incrementally behind the stable
Python CLI. Its first responsibilities are decision and grant validation/state
transitions using canonical JSON. Python remains authoritative during a
read-only shadow comparison; authority moves one use case at a time and the
replaced legacy rule is then removed.

Use explicit reconciliation commands rather than a daemon. Model desired,
applied, and observed state separately. An adapter can translate and apply a
decision but cannot redefine it. When enforcement cannot be applied or observed,
the safe result is `ASK`/`DENY` and `UNENFORCEABLE`, never inferred `ALLOW`.

Directory and network grants are bounded leases. Secret access, destructive
operations, and external mutations remain orthogonal gates. Start network
scope with exact protocol/host/port; do not introduce wildcards or CIDR until
the exact model is proven.

Harness producer tests own internal behavior and public contracts. `tonys-nix`
uses only the public Home Manager/flake/CLI contract and a stable repository
URL whose revision is managed by `flake.lock`.

## Validation

1. Golden CLI, JSON, generated inventory/mode, and Phase 0–5 fixtures.
2. Rust unit/property tests and Python/Rust differential fixtures.
3. Grant expiry, revoke, identity isolation, canonical path/symlink escape,
   exact host/port, DNS, redirect, and external-mutation separation tests.
4. Provider adapter contract tests and version-bound native probes.
5. Full harness checks and `tonys-nix` evaluation/activation consumer checks.

## Rollback

Keep the prior authority selectable until the next cutover gate is independently
verified. Never dual-write. On a kernel regression, restore the prior authority;
on an enforcement regression, revoke affected leases and fall back to
least-privilege `ASK`/`DENY`. Consumers roll back the harness lock revision while
the stable repository URL remains unchanged.

## Rejected Alternatives

- Big-bang Rust rewrite: excessive compatibility and rollback risk.
- Resident Kubernetes-style controller: unjustified lifecycle and packaging
  cost for activation/CLI-driven state.
- Provider-specific policy or grant-in-config policy: creates multiple sources
  of truth.
- Hook-only enforcement: cannot enforce filesystem or network access safely.
- Universal privileged proxy as the first step: creates a larger security
  boundary before native capabilities are measured.
