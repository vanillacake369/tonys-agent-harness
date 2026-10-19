# PRD: Phase-Complete Agent Harness

## Objective

Build a provider-neutral engineering harness whose user input is one versioned
manifest, whose deterministic core owns policy and evidence, and whose thin
adapters export provider-specific configuration. The design borrows Kubernetes'
`spec → reconcile → status` model without introducing Kubernetes dependencies.

## Status Vocabulary

`proposed | specified | ready | in_progress | implemented | verified | blocked | deferred | rejected`

Provider and operation verification additionally use
`STATICALLY_VERIFIED | NATIVE_VERIFIED | OPERATIONALLY_VERIFIED | UNAVAILABLE |
FAILED | BLOCKED_BY_APPROVAL`.

## Public Surface

Public names follow `${type}-${when}-${what}-${maintainer}`. Internal routers,
policy gates, evidence gates, and traceability gates are core runtime components,
not public skills.

Commands:

- `cmd-mid-work-ljh`
- `cmd-mid-comment-ljh`
- `cmd-post-blog-ljh`
- `cmd-post-handoff-ljh`
- `cmd-post-ship-ljh`
- `cmd-post-commit-ljh`

Skills:

- `skl-pre-prd-ljh`
- `skl-pre-research-ljh`
- `skl-pre-adr-ljh`
- `skl-mid-impl-ljh`
- `skl-mid-review-ljh`
- `skl-mid-perf-ljh`
- `skl-post-blog-ljh`
- `skl-post-docs-ljh`
- `skl-post-ship-ljh`

Legacy public names are removed without aliases. Internal implementation names
are not required to follow this convention.

## Phase 0 — Contract and Evidence Foundation

### PH-0001 — Truthful specification ownership

- Status: in_progress
- Framework PRDs, ADRs, tests, checklist, traceability, and current evidence are
  owned by this repository.
- Historical reports are marked historical and cannot prove current completion.

### PH-0002 — Repository-bound traceability

- Status: in_progress
- Every row identifies repository, revision, phase, requirement, state, design,
  implementation, test, and verification evidence.
- Local references must resolve below the declared repository root.

### PH-0003 — Phase evidence

- Status: in_progress
- Each phase emits revision-bound aggregate evidence with commands, exit codes,
  durations, provider statuses, open items, and a phase decision.
- Relevant later changes make prior evidence stale.

## Phase 1 — Normalized Configuration Core

### PH-0101 — Single normalized configuration

- Status: ready
- `agent-harness.toml` is parsed into one `NormalizedHarnessConfig` consumed by
  CLI, Home Manager, and every provider adapter.
- Mandatory global policy cannot be weakened by project configuration.

### PH-0102 — Reconciliation status

- Status: ready
- Plan/export/activation report desired digest, observed digest, generated
  inventory, warnings, failures, and provider status.

### PH-0103 — External project inputs

- Status: ready
- Project specs default to `.codex/`.
- Team guidelines are referenced through configurable source and link paths and
  are never copied or vendored.
- Approval trust uses an editable external public-key path and optional expected
  fingerprint. Private keys are never persisted.

### PH-0104 — Home Manager parity

- Status: ready
- Home Manager consumes the same normalized manifest and selected providers.
- Disabled mode installs and activates nothing.

## Phase 2 — Provider-Native Enforcement

### PH-0201 — Version-bound conformance

- Status: ready
- Native evidence binds provider version, source digest, generated digest,
  activated path, command result, and observed denial or success.

### PH-0202 — Negative provider tests

- Status: ready
- Codex, Claude, Gemini, and Kiro test instruction loading, sandbox boundaries,
  hook failure semantics, completion hooks, and reviewer write denial where the
  installed provider supports them.
- Missing providers are `UNAVAILABLE`, never passed.

### PH-0203 — MCP authorization evidence

- Status: ready
- MCP calls bind server, method, role, skill, risk, decision, operation,
  fingerprint, outcome, and evidence. Ambiguous outcomes remain `UNKNOWN`.

## Phase 3 — Engineering Execution

### PH-0301 — Deterministic execution DAG

- Status: ready
- A frozen plan produces a deterministic dependency graph with read-only
  research/review roles and exactly one repository writer.

### PH-0302 — TDD and completion integrity

- Status: ready
- Red evidence precedes minimal implementation and Green verification.
- Deleted, disabled, or hidden failing tests require independent review and
  cannot manufacture completion.
- The same root cause is retried at most three times.

### PH-0303 — Git and commit workflow

- Status: ready
- `cmd-post-commit-ljh` analyzes repository history, proposes SRP commits,
  verifies each responsibility, stages only planned files or hunks, commits in
  repository-native convention, and records requirement-to-commit evidence.
- Existing user changes are never reset, stashed, or silently included.

## Phase 4 — Measurement and Improvement

### PH-0401 — Local telemetry lifecycle

- Status: ready
- Versioned JSONL events cover decisions, routes, approvals, tool outcomes,
  retries, reviews, completion, and external operations.
- Local aggregation reports latency, retries, intervention, defects, and
  evidence coverage without storing prompts, chain-of-thought, or secrets.

### PH-0402 — Memory lifecycle

- Status: ready
- Session, daily, and durable memory are project-namespaced, secret-free,
  bounded, conflict-aware, expirable, and deletable.

### PH-0403 — Skill evaluation

- Status: ready
- Skill changes require privacy-safe before/after fixtures and independent
  evaluation. Metrics cannot relax deterministic policy.

## Phase 5 — External Operations

### PH-0501 — External operation state machine

- Status: ready
- Operations transition through `PLANNED → APPROVAL_REQUIRED → APPROVED →
  EXECUTING → SUCCEEDED|FAILED|UNKNOWN → VERIFIED|ROLLED_BACK|BLOCKED`.

### PH-0502 — Scoped execution contract

- Status: ready
- Operation ID, provider, environment, target, request fingerprint, idempotency
  key, approval digest, credential profile, rollback, observation window, and
  verification evidence are mandatory.
- Timeout never triggers an immediate duplicate call; provider state is queried
  first.

### PH-0503 — No implicit external authority

- Status: ready
- `cmd-post-ship-ljh` prepares an operation but grants no execution permission.
- Push, merge, deploy, migration, money movement, and external mutation require
  a valid external approval receipt. Without approval they remain
  `BLOCKED_BY_APPROVAL`.

## Completion Rule

A phase is complete only when every requirement for that phase is implemented,
its local exit matrix passes, conditional checks have explicit non-pass states,
aggregate evidence is bound to the tested revision, and independent review has
no blocking findings. Passing a narrower test never expands the phase scope.
