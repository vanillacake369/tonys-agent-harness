# Default-Allow Operations v2 — Authoritative Implementation Specification

Status: Accepted and authoritative (2026-10-24)

This is the single executable authority for the provider-neutral operation
guardrail. It supersedes
[`default-allow-operations-v1`](default-allow-operations-v1.md) and absorbs the
accepted [v2 PRD](../prd/default-allow-operations-reconcile-v2-2026-10-24.md),
[ADR-0004](../adr/0004-operation-policy-activation-reconcile.md),
[performance contract](../testing/default-allow-operations-reconcile-v2-perf.md),
and [execution plan](../testing/default-allow-operations-reconcile-v2-todo.md).
Those documents provide rationale and workflow; conflicts are resolved here.
`AGENTS.md` remains the behavioral source of truth.

## Objective and boundary

Every activated supported provider selects `default-allow-operations-v1` as
the versioned command-classification profile while using this v2 activation
contract. Ordinary work, role-permitted project reads/writes, networking,
infrastructure access, local commits, ordinary non-force pushes, resource
creation/start, and Nix activation are allowed. Only enumerated well-known
dangerous forms plus secret-path and catastrophic local-destruction invariants
are denied.

This is an accident-prevention rail, not a security boundary. Unknown,
unparseable, wrapped, aliased, computed, scripted, SDK, HTTP, MCP, browser, and
computer-use forms are allowed by design. Strong protection requires scoped
credentials, server authorization/admission policy, or a typed broker.

The standalone `curl | sh`/`curl | bash` rule is removed and characterized as
ALLOW residual risk.

## Provider and state contract

The manifest accepts registered providers only. Unknown names fail with
`UNKNOWN_PROVIDER` before state creation. Codex, Claude, Gemini, and Kiro are
registered for this version; a provider/version/surface is enforced only after
its porter and native blocking semantics are verified.

Exactly one effective state is persisted per provider and profile:

- `PENDING`: current fingerprint has not been proven at a blocking edge;
- `ENFORCED`: blocking PreTool validation succeeded for the fingerprint;
- `FAILED`: a supported installed surface failed local validation;
- `UNAVAILABLE`: provider executable or required runtime is absent;
- `UNSUPPORTED`: version/surface cannot supply the required blocking hook or
  lacks refreshed version evidence.

`DEGRADED` and `PENDING_PREFLIGHT` are not operation-policy states. Static
capability output is descriptive and cannot act as a second status authority.

Activation or doctor writes `UNAVAILABLE`/`UNSUPPORTED`. Activation, startup,
or a live hook may write diagnostic `PENDING`/`FAILED` through the same shared
locked state store. Only successful blocking PreTool validation may write
`ENFORCED`. Startup is advisory and may diagnose and notify, but cannot prove
enforcement or promise to stop the session.

## Activation reconcile and fingerprint

Activation upserts stable-ID managed fragments without replacing whole native
files or hook arrays, preserves unrelated provider settings, repairs managed
entries, migrates known schemas, and retains the newest three mode-0600
backups. PreTool validates; it does not repair provider-owned configuration.

The activation fingerprint is SHA-256 over canonical JSON containing only:

- harness and operation-policy revision;
- provider, profile, verified version, and surface;
- normalized stable-ID managed fragment;
- runtime executable/Nix store identity.

Runtime identity includes resolved path plus stable file identity sufficient to
detect same-path replacement. Activation/doctor refreshes version/surface
evidence when identity changes. PreTool never executes a provider binary; it
fails closed as `UNSUPPORTED` if refreshed evidence is missing. Model, UI,
plugin, project, and unrelated user-hook settings do not affect the fingerprint.

A valid matching `ENFORCED` record uses a lock-free fast path after fingerprint
recomputation. Every transition uses a provider/profile-scoped bounded lock,
rereads state, recomputes fingerprint, and writes through a mode-0700 directory
and mode-0600 same-directory temporary file using flush, fsync, atomic replace,
and parent-directory fsync where supported. Unknown schema, corruption,
symlink substitution, or lock timeout fails closed.

Mutable native config leaves an accepted race between fingerprint observation
and provider execution. Hook removal cannot be self-detected; doctor or the next
activation reports it. No daemon or watcher is required.

## Recovery

Fingerprint change triggers immediate revalidation. An unchanged `FAILED`
record denies until five seconds after failure. The next PreTool invocation
after that boundary receives one validation attempt. There is no internal sleep
until the deadline, recursive agent retry, or unbounded retry. A short bounded
lock-acquisition loop is permitted.

## Decision and feedback order

1. Normalize the provider payload and compute privacy taint.
2. Validate or establish activation state at the blocking PreTool edge.
3. Deny secret/credential paths and catastrophic broad destruction.
4. Deny an exact recognized command rule below.
5. Allow everything else, including parse failures.

Every DENY returns a typed decision with a stable reason and enters one feedback
adapter. Ordinary denial feedback may show the reviewed command. A secret/
credential reason or any privacy-tainted payload is always redacted, including
activation, lock, cooldown, and corrupt-state failures. The user is asked to
review and, if desired, execute the operation directly and report the result.

Telemetry stores timestamp, provider/surface, family, reason, policy revision,
fingerprint where applicable, and SHA-256 input hash only. Raw command, path,
SQL, secret, and credentials are excluded. Notification carries family and
reason only. Telemetry and 60-second session+hash+reason notification dedupe use
bounded concurrency-safe atomic persistence. Corruption is quarantined or
reinitialized without allowing a denied operation. Notification failure is
decision-neutral.

## Versioned command matrix

### Git

Allow local reset/clean and ordinary non-force push, including bare push and
normal upstream/refspec forms. Deny `--force`, `--force-with-lease`, `--mirror`,
deletion refspecs, leading `+` refspecs, and destructive push forms.

### Databases

Recognize PostgreSQL, MySQL/MariaDB, SQLite, SQL Server, MongoDB, and Redis
clients. Deny known DML/DDL/migration, `CALL`/`EXEC`, and file/stdin execution.
Allow transaction control and recognizable reads. Unknown drivers and
application/HTTP paths remain allowed residual risk.

### Docker, Podman, and Compose

Allow inspect/read/build/pull/create/run/start. Deny rm/rmi, stop, kill,
restart, pause/unpause, rename, update, exec, inbound copy, commit, push, prune,
and resource removal. Compose permits plain `up` and `up --build`; it denies
`--force-recreate`, `--scale`, `--remove-orphans`, down, stop, restart, rm,
kill, exec, and push.

### Kubernetes, Kustomize, and kubeadm

Allow reads/diagnostics, create/run, port-forward, proxy, standalone Kustomize
build/inspection/local edit, and kubeadm inspection/upgrade-plan. Deny secret or
token creation; kubectl apply/patch/edit/replace/delete/scale/set/annotate/
label/taint/cordon/uncordon/drain/autoscale/rollout mutation; attach/exec/debug/
copy; `kubectl apply -k` and visible Kustomize-to-apply pipes; kubeadm init/join/
reset/upgrade-apply or node, token create/delete, certificate renew, and
mutating phases.

### Terraform/OpenTofu, Pulumi, Helm, and Nix

Allow plan/show/validate/preview/template/read operations. Explicitly allow
`terraform apply`, `tofu apply`, `pulumi up`, and `helm upgrade --install`,
accepting possible updates. Deny explicit destroy/removal/state mutation such
as destroy, state rm/mv, uninstall, and rollback. Fully allow nixos-rebuild,
darwin-rebuild, and home-manager activation.

## Runtime and language boundary

One Nix-pinned Python policy process owns payload normalization, fingerprint,
activation transition, classification, and feedback. A provider shell adapter
may `exec` it, and a bounded notifier may be a child; neither makes a competing
decision. Retry-budget governance, task lifecycle, exporter, provider rendering,
managed sync, backup, and rollback remain separate responsibilities. Go is not
introduced.

The Python authority must meet p95 <= 100 ms on the current aarch64-darwin Nix
reference host for cached ENFORCED, full preflight, DENY, FAILED-inside-cooldown,
and FAILED-after-cooldown paths. Warm at least 200 production-shaped process
samples per path. Other supported Nix systems report identical fixtures
informationally until CI designates them release-blocking.

If the consolidated Python path misses the budget after scoped optimization,
evaluate the existing Rust workspace. Rust may replace one use case only after
100% frozen-fixture parity, performance evidence, provider smoke, and rollback
verification. Production never runs dual final authorities.

## Acceptance and verification

Acceptance requires:

- stable unknown-provider rejection and the single state vocabulary;
- no startup-established `ENFORCED`;
- blocking first-use latch and scoped fingerprint drift detection;
- atomic concurrent transitions and five-second recovery semantics;
- unified privacy-safe denial feedback and `curl | sh` ALLOW characterization;
- unchanged v1 command-matrix behavior otherwise;
- reference-host performance compliance or conditional Rust gate;
- matching porter semantics, available native smoke, managed-fragment
  regression, and truthful hook-removal reporting;
- traceability rows and recorded Python, Bats, Rust, Nix, repository, benchmark,
  rollback, and independent-review evidence.

No test may perform a real external mutation.

## Rollback

Provider renderers select exactly one authority. Initial cutover records a
fully verified last-known-good v2 Python artifact; without one, activation does
not cut over. Deployment rollback selects that artifact and resets effective
state to `PENDING` while retaining provider-owned settings, backups, unified
feedback, sensitive redaction, command matrix, and state vocabulary. A Rust
rollback returns the complete migrated use case to the same Python artifact.
