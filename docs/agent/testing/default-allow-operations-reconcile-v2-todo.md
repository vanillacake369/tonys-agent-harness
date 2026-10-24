# TODO and Pseudocode: Operation Activation Reconcile v2

Status: Phases 0-5 implemented and repository-wide verification passed
(2026-10-24). Phase 6 was skipped because the Python SLO passed. Phase 7
publication and downstream consumption remain pending. See the [execution
report](default-allow-operations-reconcile-v2-execution.md).

Inputs:

- [PRD](../prd/default-allow-operations-reconcile-v2-2026-10-24.md)
- [ADR-0004](../adr/0004-operation-policy-activation-reconcile.md)
- [authoritative v2 implementation specification](../spec/default-allow-operations-v2.md)
- [performance plan](default-allow-operations-reconcile-v2-perf.md)

Independent pseudocode review passed after correction of authority precedence,
privacy taint propagation, state-writer ownership, runtime identity refresh,
rollback, concurrency persistence, and five-path performance traceability.

## Acceptance traceability

The planned evidence paths below were exercised and are recorded in the linked
execution report and benchmark artifact.

| PRD acceptance | Requirements | Planned verification | Planned evidence |
| --- | --- | --- | --- |
| AC1 unknown provider and no `DEGRADED` | DAOR2-001, DAOR2-002 | manifest/state unit tests | v2 execution report |
| AC2 startup cannot establish `ENFORCED` | DAOR2-002, DAOR2-003 | transition table and provider fixture tests | v2 execution report |
| AC3 first PreTool validates fingerprint | DAOR2-003, DAOR2-004 | latch integration and native smoke | v2 execution report |
| AC4 scoped drift and fast path | DAOR2-004, DAOR2-005 | fingerprint metamorphic tests | benchmark JSON and v2 execution report |
| AC5 atomic concurrent transition | DAOR2-005, DAOR2-NFR-002 | multi-process lock/write tests | v2 execution report |
| AC6 five-second failure recovery | DAOR2-006 | fake-clock transition tests | v2 execution report |
| AC7 unified privacy-safe feedback | DAOR2-007, DAOR2-NFR-004 | reason/redaction/concurrency tests | v2 execution report |
| AC8 `curl \| sh` ALLOW and v1 matrix | DAOR2-008 | classifier regression fixtures | v2 execution report |
| AC9 p95 budget or Rust gate | DAOR2-009, DAOR2-010, DAOR2-NFR-001 | five-path benchmark and conditional parity suite | benchmark JSON; optional Rust parity report |
| AC10 porter semantics | DAOR2-NFR-003 | generated fixtures and available native smoke | native conformance report |
| AC11 managed-fragment regression | DAOR2-004 | preservation/repair/backup/rollback tests | v2 execution report |
| AC12 truthful hook-removal gap | DAOR2-011 | doctor/conformance missing-hook fixture | native conformance report |

## Phase 0 — Freeze contracts and fixtures

- [x] Add DAOR2 requirement rows to `docs/agent/traceability.tsv`.
- [x] Replace v1 activation wording in the authoritative specification with the
      accepted single state machine and PreTool latch.
- [x] Freeze stable state, error, reason, fragment, and telemetry identifiers.
- [x] Map every PRD acceptance criterion to its planned test and evidence row;
      implementation cannot begin while any mapping is absent.
- [x] Freeze provider/version/surface fixtures without contacting providers.
- [x] Add characterization fixtures for `curl | sh` ALLOW and hook-removal
      residual-risk reporting.
- [x] Record unrelated worktree changes and keep them outside task commits.

Exit: documents and fixtures agree; no unresolved decision is hidden in code.

## Phase 1 — Unified decision and feedback contract

- [x] Express sensitive-path and catastrophic-destruction results as the same
      typed decision returned by the command classifier.
- [x] Remove the standalone `curl | sh` guard.
- [x] Route every DENY through one feedback adapter.
- [x] Redact raw input for secret/credential reason families and whenever early
      payload normalization marks the request privacy-tainted.
- [x] Preserve 60-second notification deduplication and privacy-safe telemetry.
- [x] Make telemetry append and dedupe updates concurrency-safe and define
      corrupt-state recovery without changing a DENY decision.
- [x] Add paired allow/deny/redaction tests before implementation changes.

Pseudocode:

```text
normalized = normalize(payload)
privacy_tainted = detect_sensitive_input(normalized)
decision = classify(normalized)
if decision == ALLOW:
    return allow

feedback = {
    provider, surface, family, reason_id,
    command_hash, redact_raw = decision.sensitive || privacy_tainted
}
persist_private_telemetry(feedback without raw input)
notify_bounded_and_deduplicated(feedback without raw input)
deny(message = redacted(feedback) if feedback.redact_raw else reviewed_command(feedback))
```

Payload normalization computes `privacy_tainted` before the activation latch.
Every later denial redacts when `decision.sensitive || privacy_tainted`, even
when the denial reason is activation, lock, cooldown, or corrupt state.

Exit: all denial families share stable feedback semantics and secret cases never
echo raw input.

## Phase 2 — State machine and fingerprint

- [x] Implement `PENDING`, `ENFORCED`, `FAILED`, `UNAVAILABLE`, and
      `UNSUPPORTED` as the only persisted states.
- [x] Return `UNKNOWN_PROVIDER` during manifest validation and remove operation-
      policy `DEGRADED` metadata/tests.
- [x] Define canonical serialization for the scoped activation fingerprint.
- [x] Ignore unrelated provider-native settings in the fingerprint.
- [x] Bind state to provider, surface, version, policy revision, runtime
      identity, and managed fragment digest.
- [x] Define runtime identity so replacement at the same executable path
      invalidates cached version and enforcement state.
- [x] Version the activation-state schema independently from policy revision;
      reject unknown schemas.
- [x] Write corrupt-state and stale-fingerprint fail-closed tests.

Pseudocode:

```text
fingerprint = sha256(canonical_json({
    harness_revision,
    policy_revision,
    provider,
    provider_version,
    provider_surface,
    managed_fragment,
    runtime_identity
}))

state = read_private_state_or(PENDING)
if state.fingerprint != fingerprint:
    effective_state = PENDING
else:
    effective_state = state.status
```

Exit: the same fixture produces the same fingerprint and effective state across
all porter paths.

State/event ownership is frozen as follows. Every writer uses the same scoped
transition lock and atomic state schema except the validated lock-free read of a
matching `ENFORCED` record.

| Event | Prior effective state | Result |
| --- | --- | --- |
| Unknown manifest provider | none | reject `UNKNOWN_PROVIDER`; no record |
| Activation/doctor cannot find executable/runtime | any | `UNAVAILABLE` |
| Activation/doctor finds unrecognized version/surface | any | `UNSUPPORTED` |
| Activation/startup validates managed structure | non-ENFORCED | `PENDING` |
| Activation/startup finds invalid structure | any | `FAILED` |
| Live hook finds valid identity and current cached version evidence after absence | `UNAVAILABLE` | `PENDING`, then locked preflight |
| Live hook sees unchanged unsupported identity | `UNSUPPORTED` | deny until activation/doctor records support |
| Live hook sees new runtime identity without refreshed version evidence | any | `UNSUPPORTED`; deny until activation/doctor refreshes evidence |
| Blocking PreTool preflight succeeds | `PENDING` or retryable `FAILED` | `ENFORCED` |
| Blocking PreTool preflight fails | `PENDING` or retryable `FAILED` | `FAILED` with retry time |
| Matching blocking PreTool | `ENFORCED` | remain `ENFORCED`, then classify |
| Relevant fingerprint drift | any | effective `PENDING`, then locked preflight |

## Phase 3 — Activation latch, locking, and recovery

- [x] Make startup preflight advisory: diagnose, persist non-ENFORCED evidence,
      and notify, but never establish `ENFORCED`.
- [x] Add a blocking latch before classification for every covered PreTool
      surface.
- [x] Use a lock-free cached `ENFORCED` path when the fingerprint matches.
- [x] Acquire a bounded provider+profile lock only for transitions.
- [x] Persist transitions with private temp file, flush/fsync, atomic replace,
      and parent-directory durability where supported.
- [x] Use a mode-0700 state directory, mode-0600 records, and no-follow/lstat
      protections where supported.
- [x] Apply the scoped lock and atomic schema to activation, doctor, startup,
      and live-hook writers, not only PreTool transitions.
- [x] Fail closed on lock timeout or malformed state.
- [x] Revalidate immediately after fingerprint change.
- [x] Revalidate unchanged `FAILED` state only on the next PreTool call after
      the five-second cooldown.
- [x] Add parallel-process transition tests and deterministic fake-clock tests.
- [x] Freeze full local preflight as: state/schema/mode validation, runtime
      identity and cached-version validation, native managed-fragment structural
      validation, required runtime readability/executability, and canonical
      fingerprint recomputation. It must not invoke a provider tool or network.
- [x] Require activation/doctor to refresh provider version/surface evidence
      when runtime identity changes. PreTool fails closed as `UNSUPPORTED` when
      that refreshed evidence is absent; it never executes the provider binary.
- [x] Assign bounded deadlines to lock acquisition, notifier dispatch, and any
      subprocess adapter; record them in fixtures before performance testing.

Pseudocode:

```text
function latch(provider, profile, payload, now):
    normalized = normalize(payload)
    privacy_tainted = detect_sensitive_input(normalized)
    fingerprint = observe_scoped_fingerprint(provider, profile)
    state = read_state()

    if state == ENFORCED and state.fingerprint == fingerprint:
        return classify_and_feedback(normalized, privacy_tainted)

    if state == FAILED and state.fingerprint == fingerprint:
        if now < state.retry_after:
            return deny(ACTIVATION_COOLDOWN, redact = privacy_tainted)

    lock = acquire_transition_lock(deadline = bounded)
    if lock.failed:
        return deny(ACTIVATION_LOCK_TIMEOUT, redact = privacy_tainted)

    state = reread_state_under_lock()
    fingerprint = observe_scoped_fingerprint(provider, profile)
    if state == ENFORCED and state.fingerprint == fingerprint:
        return classify_and_feedback(normalized, privacy_tainted)

    result = full_local_preflight(provider, profile, fingerprint)
    if result.ok:
        atomic_write(ENFORCED, fingerprint, verified_at = now)
        return classify_and_feedback(normalized, privacy_tainted)

    failure_state = result.target_state  # FAILED, UNAVAILABLE, or UNSUPPORTED
    if failure_state == FAILED:
        atomic_write(FAILED, fingerprint,
                     failed_at = now, retry_after = now + 5s,
                     reason_id = result.reason_id)
    else:
        atomic_write(failure_state, fingerprint,
                     checked_at = now, reason_id = result.reason_id)
    return deny(result.reason_id, redact = privacy_tainted)
```

Exit: the provider cannot execute a covered tool before successful latch
validation, and concurrent callers cannot publish contradictory state.

## Phase 4 — Single-process Python hot path

- [x] Replace the Bash/JQ/Python fan-out with one Nix-pinned Python entry point.
- [x] Keep provider hook commands as thin transport adapters only where native
      payload normalization requires them.
- [x] Keep exporter, rendering, managed sync, backup, and rollback outside the
      hot-path module.
- [x] Ensure every provider invokes the same authority with provider/surface
      parameters.
- [x] Preserve provider-specific timeout units and blocking response shapes.

Exit: one Python process owns latch, classification, state, and feedback for a
tool event; no alternate script can make a competing final decision.

## Phase 5 — Performance and provider verification

- [x] Record the formal current-path benchmark.
- [x] Measure cached ENFORCED, full preflight, DENY, FAILED inside cooldown, and
      FAILED after cooldown p95 as five separate distributions.
- [x] Require p95 <= 100 ms on the current aarch64-darwin Nix reference host;
      report identical fixtures informationally on other supported systems.
- [x] Run focused unit tests, all Python tests, Bats hooks, Rust tests, Nix
      parser/checks, `just check`, and full `nix flake check` where compatible.
- [x] Run structural fixtures for all providers and native smoke for installed
      provider surfaces without real external mutation.
- [x] Run doctor/conformance with a deliberately missing managed hook and prove
      truthful residual-risk reporting.
- [x] Replace a provider executable fixture at the same path and prove runtime
      identity invalidates the cached version/fingerprint.

Exit: correctness and performance acceptance pass with recorded evidence.

## Phase 6 — Conditional Rust path

This phase is skipped when the Python implementation meets the SLO.

- [ ] Add a Rust shadow implementation for one hot-path use case.
- [ ] Require frozen-fixture 100% semantic parity.
- [ ] Compare the same performance cases.
- [ ] Validate provider smoke and rollback selector.
- [ ] Cut over exactly one use case and remove Python authority for that case.
- [ ] Never accept dual final decisions.

Exit: either Python remains authoritative within budget, or a verified single
Rust authority owns the migrated use case.

## Phase 7 — Review, rollout, and downstream consumption

- [x] Independent review checks privacy, state transitions, concurrency,
      performance evidence, provider parity, rollback, and traceability.
- [x] Repair findings and repeat targeted then full verification.
- [x] Update the execution log with commands, results, and residual risks.
- [ ] Run the repository post-commit workflow.
- [ ] Commit responsibilities in coherent groups, publish the harness, update
      `tonys-nix` to the published revision, validate, commit, and publish it.

Exit: all PRD acceptance criteria pass and downstream consumption is verified.

## Pseudocode review checklist

- [ ] Does every failure return a typed DENY rather than exit before feedback?
- [ ] Can corrupt state, lock failure, or fingerprint observation ever default
      to ALLOW?
- [ ] Does startup avoid claiming `ENFORCED`?
- [ ] Is the fast path safe without a lock because its fingerprint binds every
      enforcement-relevant input?
- [ ] Is state reread after lock acquisition to avoid TOCTOU transitions?
- [ ] Can cooldown retry occur only because a new tool event arrived?
- [ ] Are notifier and telemetry failures bounded and decision-neutral?
- [ ] Are secret-bearing messages redacted before all output adapters?
- [ ] Are provider-specific payloads normalized before entering shared policy?
- [ ] Is hook removal described as residual risk rather than silently passed?
- [ ] Is a Rust cutover gated and single-authority?
- [ ] Do activation/doctor/startup writers use the same lock and atomic schema?
- [ ] Is a privacy-tainted payload redacted even when activation fails before
      command classification?
