# Test Specification: Phase-Complete Agent Harness

## Phase 0

- reject duplicate, unknown, stale, cross-repository, and escaping traceability
  references;
- require revision-bound phase evidence;
- reject legacy public names and public internal gates;
- distinguish historical reports from current evidence.

## Phase 1

- normalize every preset and explicit provider selection;
- reject malformed values and mandatory-policy weakening;
- prove CLI/Nix normalized digest parity;
- prove disabled Home Manager has no provider or activation output;
- create only the configured team-guidelines symlink and preserve its source;
- reject missing, repository-contained, malformed, or fingerprint-mismatched
  approval trust inputs for approval-required work.

## Phase 2

- bind conformance evidence to source and generated digests;
- Codex harmless/read/write denial probes distinguish startup failure;
- Claude/Gemini instruction, hook, sandbox, and reviewer negative probes;
- Kiro reviewer and Stop behavior;
- unavailable provider is never PASS;
- MCP read allowlist, mutation denial, timeout UNKNOWN, and evidence binding.

## Phase 3

- deterministic role DAG and dependency validation;
- exactly one writer and read-only reviewers;
- scope drift triggers reapproval;
- Red/Green evidence and failing-test deletion detection;
- persistent three-attempt retry budget;
- incomplete evidence or dirty uncommitted code cannot become DONE;
- commit plan follows target repository history and planned file scope.

## Phase 4

- validate every telemetry event version and redact prohibited content;
- aggregate route, latency, retry, intervention, review, and completion metrics;
- telemetry failure cannot weaken policy;
- enforce memory namespace, bounds, promotion, conflict, expiry, and deletion;
- require before/after skill evaluation evidence.

## Phase 5

- reject unapproved and scope-mismatched external operations;
- validate state transitions and terminal closure;
- prevent duplicate execution after timeout;
- reconcile `UNKNOWN` through provider lookup;
- require dry-run, rollback, observation, and verification evidence;
- represent unavailable environment or missing approval without claiming PASS.

## Repository Gates

Focused checks run first. Phase candidates run Python tests, Bats hooks, Nix
contract checks, `nix flake check`, native conformance for installed providers,
traceability validation, secret scanning, and Git lifecycle validation.
