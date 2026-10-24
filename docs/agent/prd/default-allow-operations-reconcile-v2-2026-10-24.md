# PRD: Default-Allow Operation Activation Reconcile v2

Status: Accepted requirements (2026-10-24)

This PRD refines the activation, feedback, and runtime-performance portions of
the prior v1 specification. Its accepted requirements are absorbed by
[`default-allow-operations-v2`](../spec/default-allow-operations-v2.md), the
single executable implementation authority.

## Problem

The shared default-allow policy is rendered for Codex, Claude, Gemini, and
Kiro, but a correctly rendered file does not prove that a provider invoked its
blocking hook. Session-start events are advisory or surface-dependent for some
providers, and the current Bash/JQ/Python hook chain adds process startup cost.
Denials can also bypass the common feedback path when an earlier path guard
exits first.

The harness needs a provider-neutral activation latch that proves enforcement
at a blocking `PreToolUse` boundary, detects relevant drift cheaply, recovers
from transient failures without retry loops, and preserves low-friction daily
use.

## Goals

- Give every known provider the same operation-policy state semantics.
- Route every denial through one privacy-safe feedback path.
- Reconcile activation at provider activation and at blocking tool-use edges.
- Keep the unchanged fast path below an explicit latency budget.
- Preserve mutable provider-owned configuration and unrelated user settings.
- Retain the v1 default-allow command matrix except for the explicit removal of
  the `curl | sh` special case.

## Non-goals

- Continuous daemon or filesystem-watcher reconciliation.
- Detecting a native hook after that hook and its startup check have both been
  removed or disabled.
- Comprehensive detection of wrapped, aliased, SDK, HTTP, MCP, browser, or
  computer-use mutations.
- Introducing Go or rewriting the exporter, provider renderer, managed-config
  synchronizer, backup, or rollback paths in v2.
- Making this accident-prevention rail a security boundary.

## Functional requirements

### DAOR2-001 — Known-provider ingress

The manifest accepts only registered providers. An unregistered provider fails
validation with the stable error code `UNKNOWN_PROVIDER` before activation
state is created. The prior `DEGRADED` state is removed.

### DAOR2-002 — Single activation state machine

Each selected provider has exactly one effective operation-policy state:

- `PENDING`: enforcement has not yet been proven for the current fingerprint;
- `ENFORCED`: a blocking PreTool check succeeded for the current fingerprint;
- `FAILED`: a supported installed surface failed validation;
- `UNAVAILABLE`: its executable or required execution environment is absent;
- `UNSUPPORTED`: the installed provider version or surface cannot supply the
  required blocking hook.

Static capability metadata is not a second operation-policy status authority.
Activation or doctor records `UNAVAILABLE` and `UNSUPPORTED`. Activation,
startup, or a live hook may persist `PENDING`/`FAILED` diagnostic state through
the shared locked state store, but only a successful blocking PreTool edge may
persist `ENFORCED`.

### DAOR2-003 — Advisory startup and authoritative PreTool latch

SessionStart or the closest provider-native startup event performs early
diagnosis and best-effort notification, but it does not establish `ENFORCED`.
Before a covered tool executes, a blocking PreTool hook validates or reuses the
current activation fingerprint. Only a successful blocking invocation changes
the state to `ENFORCED` and proceeds to operation classification.

### DAOR2-004 — Activation and edge reconciliation

Home Manager/provider activation upserts and repairs stable-ID managed
fragments. Each PreTool invocation compares a narrowly scoped fingerprint. A
changed or absent fingerprint moves the effective state to `PENDING` and runs
full local preflight before classification.

The fingerprint contains only:

- harness and operation-policy revision;
- provider identity, version, and active surface;
- the relevant managed native-config fragment;
- runtime executable or Nix store-path identity.

Unrelated model, UI, plugin, project, or user hook settings do not invalidate
the operation-policy fingerprint.

### DAOR2-005 — Cached fast path and concurrency

An `ENFORCED` record with a matching fingerprint uses a lock-free validation
fast path. State transitions use a provider-and-profile-scoped bounded lock and
atomic replacement. Lock timeout fails closed and uses the common feedback
path.

Because provider configuration is mutable, a change after fingerprint
observation but before native tool execution remains a narrow accepted TOCTOU
risk. The hook re-observes state under transition locks but cannot make the
provider's later execution transactional.

### DAOR2-006 — Failure recovery

Fingerprint changes trigger immediate revalidation. With an unchanged
fingerprint, a `FAILED` state may retry once on the next PreTool invocation
after a five-second cooldown. No internal sleep, busy loop, recursive agent
retry, or unbounded retry is allowed. Failed notifications remain deduplicated
for 60 seconds.

### DAOR2-007 — Unified denial feedback

Every policy denial, including sensitive-path, catastrophic-destruction,
activation, and lock failures, produces one stable reason ID and flows through
the shared telemetry/notifier adapter. Notification failure never changes the
decision.

Ordinary denial feedback may show the original command. Payload normalization
computes a privacy taint before activation checks; a sensitive-path or
credential reason, or any privacy-tainted payload denied for another reason,
redacts the original input and exposes only family, reason ID, and command
hash. Telemetry and desktop notifications never contain raw commands, SQL,
paths, secrets, or credentials.

### DAOR2-008 — Command-matrix correction

Remove the standalone `curl | sh`/`curl | bash` denial. HTTP, downloaded
scripts, and other unclassified forms remain allowed residual risk under the
v1 default-allow contract. The existing secret-path, catastrophic-destruction,
and versioned command-family denials remain in force.

### DAOR2-009 — Runtime boundary

The v2 hot path is implemented first as one authoritative Nix-pinned Python
policy process rather than a Bash/JQ/Python decision pipeline. A provider shell
adapter may `exec` that authority, and the notifier may be a bounded child
process; neither may make a competing policy decision. Python continues to own CLI/export,
provider rendering, managed-fragment synchronization, schema migration,
backup, and rollback. Go is not introduced.

### DAOR2-010 — Conditional native cutover

If the Python hot path misses the accepted performance budget, native migration
prefers the existing Rust workspace. A Rust use case becomes authoritative only
after frozen-fixture semantic parity, provider-native smoke tests, and rollback
validation pass. Python and Rust must never make the final decision
simultaneously; cutover proceeds one use case at a time.

### DAOR2-011 — Explicit residual risk

If a user or provider removes or disables the blocking hook, code invoked by
that hook cannot detect its own absence. Doctor/native conformance and the next
activation must report or repair the condition. No background watcher is
required for v2.

## Non-functional requirements

### DAOR2-NFR-001 — Latency

On the current aarch64-darwin Nix development host, policy overhead must meet
p95 <= 100 ms for each measured path: cached `ENFORCED`, full preflight,
ordinary DENY, and `FAILED` cooldown. Other supported Nix systems report the
same fixtures informationally until CI designates them release-blocking.
Provider command execution time is excluded. Baselines and measurement inputs
must be reproducible.

### DAOR2-NFR-002 — Reliability

State writes use a mode-0700 private parent directory, mode-0600 files,
temporary-file write, flush, fsync, atomic replace, and parent-directory fsync
where supported. Symlink substitution is rejected using no-follow or equivalent
lstat validation where supported. Corrupt, partial, or unknown-schema state
never allows a tool invocation.

### DAOR2-NFR-003 — Portability

Provider adapters may translate event names, matchers, timeouts, and payload
shapes, but cannot redefine the shared state machine, fingerprint, classifier,
feedback, or retry semantics.

### DAOR2-NFR-004 — Observability and privacy

State and telemetry record stable codes, timestamps, provider/surface, policy
revision, fingerprint, and command hash only. Sensitive raw input is excluded.

## Dependencies and constraints

- Provider-native blocking PreTool hooks remain the enforcement edge.
- Session-start behavior differs across provider versions and surfaces.
- Nix supplies the pinned Python executable and any later Rust binary.
- Existing user-owned worktree changes and mutable native settings must be
  preserved.
- Native tests must not execute real external mutations.

## Acceptance criteria

1. Unknown provider input fails with `UNKNOWN_PROVIDER`; `DEGRADED` disappears
   from the operation-policy model.
2. No startup-only result can produce `ENFORCED`.
3. The first covered PreTool call validates the current fingerprint before the
   requested tool can run.
4. Matching `ENFORCED` state uses the fast path; relevant drift forces
   revalidation; unrelated native settings do not.
5. Concurrent transitions are atomic and lock timeout fails closed.
6. `FAILED` recovery follows the five-second cooldown without a retry loop.
7. Every denial uses the shared feedback path; sensitive denial output is
   redacted.
8. `curl | sh` is characterized as allowed, while all retained v1 matrix tests
   remain green.
9. The five latency paths meet p95 <= 100 ms or implementation stops before
   cutover and follows the Rust migration gate.
10. Provider fixtures and available native smoke tests prove equivalent state
    and decision semantics.
11. Managed-fragment preservation, repair, backup, and rollback tests remain
    green.
12. Doctor/conformance reports hook removal as residual drift without claiming
    continuous enforcement.

## Rollback

Cutover records the last-known-good v2 Python artifact before changing provider
selectors. Deployment rollback selects that artifact while retaining unified
feedback, sensitive redaction, `curl | sh` ALLOW, and the state semantics. If no
verified v2 artifact exists, activation does not cut over. Rollback removes only
superseded v2 state/fragment IDs and retains provider-owned settings and
existing backups. A conditional Rust cutover uses the same selector to return
authority to the verified Python artifact.
