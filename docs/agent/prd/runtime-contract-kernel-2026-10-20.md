# PRD: Runtime Contract Kernel and Scoped Permissions

## Objective

Preserve the Phase 0–5 public behavior while moving policy decisions and state
transitions toward one Rust authority. Provider hooks remain transport adapters;
native sandboxes or scoped executors remain enforcement boundaries.

## Requirements

### RCK-001 — Stable public contracts

- Version the CLI, normalized configuration, export manifest, decision, grant,
  reconciliation status, and evidence envelopes.
- Keep existing command names, exit codes, generated ownership, and Nix module
  options compatible during migration.
- The harness owns producer contract tests for `validate`, `doctor`, `plan`,
  `export`, and `verify`; consumer repositories test only public behavior.

### RCK-002 — Architectural boundaries

- Ingress translates manifests, CLI requests, provider events, and approvals.
- Inbound use cases invoke normalize, decide, grant lifecycle, reconcile, and
  verify operations.
- Core policy and state transitions do not depend on provider syntax or I/O.
- Outbound ports describe state, clock, canonical resource, enforcement probe,
  and evidence behavior; egress adapters perform actual I/O.
- Logical boundaries do not require a daemon, CRDs, or one module per port.

### RCK-003 — Desired, applied, and observed state

- Reconciliation distinguishes declared intent, adapter-applied state, and
  provider-observed enforcement.
- Rendering success alone cannot report native enforcement as active.
- Status is one of `IN_SYNC`, `DRIFTED`, `PARTIALLY_ENFORCED`,
  `UNENFORCEABLE`, or `ERROR`, with reasons and evidence references.

### RCK-004 — Risk decision contract

- The core returns `ALLOW`, `ASK`, or `DENY` with a stable reason code and
  policy revision.
- Invariant prohibitions dominate grants. Unknown or unobservable enforcement
  never becomes `ALLOW`.
- Command text may contribute risk evidence but is not the security boundary.

### RCK-005 — Scoped grant lifecycle

- Grants include ID, task/session identity, role/agent, resource type,
  canonical target, operations, scope, expiry/end condition, approval identity,
  revocation state, policy revision, and evidence reference.
- Directory grants distinguish read/write/execute/delete and re-check canonical
  containment at use time. Secret access and destructive operations remain
  separate prohibitions.
- Network grants initially use exact protocol/host/port. DNS resolution and
  redirects are re-authorized; reachability never grants remote mutation.
- Missing, expired, revoked, or identity-mismatched grants yield `ASK` where a
  provider can pause safely and `DENY` otherwise.

### RCK-006 — Phased Rust authority

- Freeze golden contracts before Rust changes.
- Introduce a small pure Rust kernel in shadow mode with differential fixtures.
- Cut over one use case at a time and remove the corresponding legacy decision
  only after parity evidence. Never dual-write authoritative state.
- Support a lockfile/package rollback to the previous authority.

### RCK-007 — Provider capability truthfulness

- Each adapter reports whether it can apply, revoke, and observe a requested
  grant for its version and platform.
- Unsupported providers report `UNENFORCEABLE`/`UNAVAILABLE`; they do not claim
  a safe active grant.
- External mutations continue to require operation-specific approval.

### RCK-008 — Consumer dependency contract

- `tonys-nix` uses the stable repository URL and keeps ordinary revisions only
  in `flake.lock`.
- Its tests assert module evaluation, CLI installation, selected providers, and
  activation build behavior through versioned public fields, not hook filenames
  or activation script strings.

## Non-goals

- A Kubernetes dependency, resident controller, or generic plugin framework.
- A big-bang rewrite of provider renderers and shell adapters.
- Treating Rust, hooks, or preflight canonicalization as an OS sandbox.
- Implicit push, publish, deploy, migration, or other external authority.

## Acceptance Criteria

- Existing Phase 0–5, Python, Bats, and Nix checks remain green.
- Public consumer contract tests are owned by this repository, and
  `tonys-nix` contains no activation-script or hook-path assertions.
- Rust differential tests cover decision dominance, grant isolation,
  expiry/revocation, path escape, and exact network targets before cutover.
- Native probes record repository revision, task/role, grant, provider/sandbox,
  command/result, reason, and unverified items.
- Supported Nix systems build the selected authority, with a documented
  rollback to the prior locked revision.
