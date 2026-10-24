# ADR-0004: PreTool Activation Reconcile and Single Python Authority

## Status

Accepted (2026-10-24)

## Context

The provider-neutral default-allow policy currently renders native hooks for
Codex, Claude, Gemini, and Kiro. Its startup preflight can validate generated
shape, but provider startup events are not uniformly blocking and cannot prove
that a later tool invocation crossed the policy gate. The current PreTool path
also fans out through Bash, JQ, Python, and a retry script, while early path
denials bypass common feedback.

The accepted requirements are defined in
[`default-allow-operations-reconcile-v2-2026-10-24.md`](../prd/default-allow-operations-reconcile-v2-2026-10-24.md).

Two independent strategies evaluated the PRD and repository. Strategy A
favored the smallest safe Python consolidation around the existing classifier.
Strategy B tested a stronger typed/native boundary and concluded that Python
should remain authoritative for v2, with Rust reserved for measured SLO
failure. Neither found evidence supporting a new Go stack.

## Evidence classification

### AGREEMENT

- A blocking PreTool edge, not startup, is the only portable point that may
  establish `ENFORCED`.
- Activation repairs managed fragments; PreTool validates and classifies but
  does not repair provider-owned config.
- One Nix-pinned Python policy authority is the smallest v2 change.
- Provider adapters normalize native syntax and payloads but do not own policy
  or state semantics.
- All denials need one privacy-safe feedback contract; sensitive input requires
  redaction.
- State transition writes require scoped locking and atomic durable replace.
- Hook removal is not self-detectable and remains a doctor/activation residual
  risk.
- Go adds a third toolchain without using existing Python/Rust/Nix assets.
- Rust is a conditional, parity-gated optimization rather than the v2 starting
  point.

### COMPLEMENTARY

- Strategy A identified retry-budget governance as a separate responsibility
  that must not be absorbed into the operation-policy state machine.
- Strategy B required a separately versioned state schema, canonical semantic
  fingerprints, parent-directory fsync, symlink protections, and an explicit
  mutable-config TOCTOU disclosure.
- Together they define a clean later-native boundary:
  `Payload -> Fingerprint -> ActivationTransition -> OperationDecision -> FeedbackEnvelope`.

### CONFLICT RESOLVED

1. **Literal single OS process versus native adapters and notifier.**
   “Single process” means one authoritative Python policy process. A native
   shell adapter may `exec` it and a bounded notifier may run as a child; no
   other process may produce a competing decision.
2. **Who writes non-live states.** Activation/doctor owns `UNAVAILABLE` and
   `UNSUPPORTED`; the live blocking hook owns `PENDING`, `ENFORCED`, and
   `FAILED`. All writers use the same private state schema, so there is still
   one effective state authority.
3. **Retry hook overlap.** Retry-budget governance remains a separate hook.
   The operation-policy entry point does not invoke it and does not absorb its
   state or retry semantics.
4. **Lock-free fast path versus drift.** A structurally valid matching
   `ENFORCED` record may skip the transition lock only after recomputing the
   scoped fingerprint. Transition paths reread state and fingerprint under the
   lock. A native config change after observation and before provider execution
   remains an accepted TOCTOU risk.
5. **Rollback semantics.** Runtime rollback may change executable authority but
   must retain unified feedback, secret redaction, `curl | sh` ALLOW, and the
   accepted state meanings.
6. **Universal performance claim.** The current aarch64-darwin Nix development
   host is the v2 release-blocking reference. Other systems report comparable
   evidence until CI explicitly promotes them to release-blocking targets.

### UNVERIFIED

- Cheap reliable provider version discovery and native surface identification
  must be proven per adapter. Until a provider/version/surface combination has
  an explicit rule, activation reports `UNSUPPORTED` rather than guessing.
- Native exit-code blocking semantics require generated fixtures and available-
  binary smoke tests for each provider surface.
- The Python implementation must demonstrate the five-path p95 budget; the
  exploratory sequential means are not acceptance evidence.
- Darwin/Linux bounded advisory-lock behavior requires a deterministic
  concurrency fixture.

Agreement is not treated as proof; each unverified claim is an implementation
or activation gate.

## Decision

### Runtime boundary

Create one pinned Python operation-policy entry point. Provider-native hooks
pass provider, profile, and surface identifiers and stream the native payload.
The entry point owns:

1. payload normalization and invariant validation;
2. canonical scoped fingerprint observation;
3. activation-state validation and transition;
4. path and command classification;
5. privacy-safe feedback, telemetry, and bounded notification.

Keep the exporter, provider rendering, managed-config synchronization, backup,
rollback, task lifecycle, and retry-budget governance outside this boundary.
Keep the command classifier pure so unit fixtures and later Rust parity remain
straightforward.

### State model and ownership

The state schema is versioned independently from the policy revision and stores
only:

- schema and policy revision;
- provider, profile, version, and surface;
- runtime identity and canonical fingerprint;
- one of `PENDING`, `ENFORCED`, `FAILED`, `UNAVAILABLE`, `UNSUPPORTED`;
- checked/failed/retry timestamps and a stable reason ID where applicable.

Manifest rejection uses `UNKNOWN_PROVIDER` and creates no state. Startup is
advisory and cannot write `ENFORCED`. Only a successful blocking PreTool
invocation may do so.

Activation/doctor records absence or known incompatibility. A version/surface
that cannot be identified against an explicit porter rule is `UNSUPPORTED`, not
silently assumed compatible.

### Fingerprint and fast path

The fingerprint is SHA-256 over canonical JSON containing only provider,
profile, policy/harness revision, verified version/surface, normalized managed
fragment, and runtime executable/store identity. It excludes unrelated native
settings.

Runtime identity is the resolved executable/store path plus stable file
identity metadata sufficient to detect replacement at the same configured
path. Version discovery is cached only while that identity matches; identity
change refreshes the version before enforcement. If the adapter cannot obtain
a supported version/surface after refresh, the effective state is
`UNSUPPORTED`.

A matching valid `ENFORCED` record proceeds without the transition lock. Every
other state acquires a provider-and-profile lock, rereads state, recomputes the
fingerprint, and then performs full local preflight. Lock acquisition is
bounded; timeout denies through common feedback. The implementation may use a
short bounded lock-acquisition loop, but it may not wait or retry indefinitely.

### Recovery

Changed fingerprint revalidates immediately. Unchanged `FAILED` state denies
until five seconds after failure; the next tool invocation after that boundary
gets one validation attempt. The runtime does not sleep until the deadline and
does not create an agent retry loop.

### Feedback and privacy

Every denial becomes a typed decision and enters one feedback adapter. Ordinary
denials may show the reviewed raw command. Sensitive-path and credential
denials show only family, reason ID, and command hash. Persistent telemetry and
desktop notification never contain raw command, path, SQL, secret, or
credential material.

Telemetry append and notification-dedupe updates use bounded, concurrency-safe
atomic persistence. Corrupt feedback state is reinitialized or quarantined
without allowing a denied operation; notifier failure remains decision-neutral.

The obsolete `curl | sh` special case is removed. It remains an explicitly
accepted default-allow residual risk.

### Performance and conditional native migration

The Python authority must meet p95 <= 100 ms on the reference system for cached
ENFORCED, full preflight, ordinary DENY, and FAILED cooldown fixtures. The
benchmark warms each case, records at least 200 production-shaped process
invocations, and reports reproducible environment and fixture identities.

If any path misses the budget after one-process consolidation and scoped
optimization, evaluate the existing Rust workspace. Rust first runs only in
offline tests/benchmarks as a shadow. It may replace one authoritative use case
only after 100% frozen-fixture parity, provider smoke, performance evidence, and
rollback verification. Production never asks Python and Rust for competing
final decisions.

## Consequences

### Positive

- Activation truth comes from a blocking edge with one state vocabulary.
- Common denial feedback closes the early-exit privacy/notification gap.
- The usual path avoids transition locks and irrelevant config drift.
- The architecture keeps policy readable while preserving a measured native
  optimization path.
- No daemon, Go toolchain, or wholesale config ownership is introduced.

### Negative

- A removed hook cannot report its own removal.
- Mutable native config leaves a narrow fingerprint-to-execution race.
- Unknown provider versions/surfaces fail closed as `UNSUPPORTED` until their
  porter rules and smoke evidence are added.
- Private state and transition locking add concurrency and durability tests.

## Validation

- Frozen v1 matrix plus `curl | sh` ALLOW and secret-redaction fixtures.
- Complete state-transition and fake-clock cooldown table.
- Canonical fingerprint metamorphic tests for relevant and irrelevant changes.
- Concurrent transition, lock-timeout, partial-write, unknown-schema, symlink,
  notifier-timeout, and fsync fault injection.
- Generated porter fixtures for command and file payloads; native smoke for
  installed provider/version/surface combinations.
- Formal five-path performance evidence.
- Full Python, Bats, Rust, Nix, repository, managed-sync, backup, and rollback
  regression checks.
- Independent review of policy scope, privacy, concurrency, performance,
  provider parity, rollback, and traceability.

## Rollback

Provider renderers select exactly one policy authority. Initial cutover occurs
only after a v2 Python artifact passes all gates and is recorded as last-known-
good. Rollback selects that artifact, invalidates activation state to
`PENDING`, and removes only superseded v2 runtime state or fragments. It
preserves provider-owned settings, backups, unified feedback, secret redaction,
`curl | sh` ALLOW, and the single state vocabulary. A later Rust rollback uses
the same selector and returns the whole migrated use case to that Python
artifact.

## Rejected alternatives

- **Immediate Go implementation:** adds a third stack without measured need.
- **Big-bang Rust rewrite:** expands the fail-closed migration beyond the proven
  contract-kernel boundary.
- **Shell-only state machine:** poor fit for structured parsing, atomic state,
  privacy, and locking.
- **Background watcher or daemon:** ownership/race cost is disproportionate and
  still not a complete security boundary.
- **Whole-config hashing:** unrelated settings would cause false invalidation.
- **Startup-established ENFORCED:** lifecycle events are not uniformly blocking.
- **PreTool automatic config repair:** creates writes and provider ownership
  races in the latency-sensitive boundary.
- **Dual production authority:** disagreement would make execution semantics
  ambiguous.
