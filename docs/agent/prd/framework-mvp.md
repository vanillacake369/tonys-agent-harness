# PRD: Agent Harness Framework MVP

## Problem

The reusable agent contract currently lives inside `tonys-nix`, mixing shared
policy with one user's Home Manager integration. Projects need one simple,
versioned manifest that can be validated and exported to provider-native files
without allowing project configuration to weaken mandatory policy.

## Scope

Build an independent `tonys-agent-harness` repository with a dependency-light
CLI and reusable assets. The MVP supports `init`, `doctor`, `plan`, `export`,
and `verify`; Codex, Claude, Gemini, and Kiro are explicit exporter targets.

## Requirements

### FR-001 — Versioned project manifest

- Status: implemented
- `docs/agent/harness.toml` is the editable project input.
- Unknown schema versions and malformed values fail closed.

### FR-002 — Immutable core policy

- Status: implemented
- Secret access denial, approval for destructive/production/migration/external
  mutation, read-only review/research, and single-writer mutation are mandatory.
- Project settings may strengthen but never weaken these rules.

### FR-003 — Presets

- Status: implemented
- Provide `minimal`, `application`, `infra-devops`, and `regulated` presets.
- A preset supplies defaults; explicit project settings may narrow them.

### FR-004 — Provider capability model

- Status: implemented
- Codex, Claude, Gemini, and Kiro expose explicit supported, adapted, or
  unsupported capabilities.
- Unsupported mandatory enforcement fails verification instead of disappearing.

### FR-005 — Deterministic plan and export

- Status: implemented
- `plan` reports normalized settings, generated targets, warnings, and errors
  without mutation.
- `export` writes only below a caller-selected output directory using atomic
  replacement and includes source metadata.

### FR-006 — Provider-neutral assets

- Status: implemented
- Ship the 12 lifecycle/content `skl-*` assets, five public `cmd-vpp-*` workflows, A2A
  workflow, deterministic governance scripts, and orchestrator scripts.

### FR-007 — Verification

- Status: implemented
- `verify` validates manifest policy, asset inventory, generated files, and
  provider capability claims.
- Verification returns nonzero on missing, stale, or policy-weakening output.

### FR-008 — Nix consumption

- Status: implemented
- Expose a flake package/app, library metadata, and Home Manager module entry
  without embedding a machine username or home path.

### FR-009 — Safe extraction

- Status: implemented
- Do not remove the source implementation from `tonys-nix` until parity tests
  prove the standalone framework and a versioned consumer reference exists.

### FR-010 — Cross-provider instruction SSoT

- Status: implemented
- Resolve the project-relative instruction file without allowing path traversal.
- Export the same instruction bytes to every selected provider and include the
  instruction digest in stale-output detection.
- Verify Claude and Gemini native references and reject provider instruction
  drift before activation.

## Acceptance Criteria

- [x] Tests fail before the CLI implementation exists.
- [x] `harness init --preset infra-devops` creates a valid manifest without
      overwriting an existing file.
- [x] A project attempt to allow secret access or disable mandatory production
      approval fails validation.
- [x] `plan` does not create provider output.
- [x] `export` deterministically creates selected provider output in a staging
      directory.
- [x] `verify` detects tampered generated output.
- [x] All 11 lifecycle skills and four public commands are discoverable.
- [x] Every selected provider receives the same project `AGENTS.md`, and the
      provider instruction gate detects drift.
- [x] `nix flake check` and the repository test command pass.

## Non-goals

- Publishing a remote Git repository or package registry release.
- Activating user home configuration.
- Executing deployments, migrations, commits, pushes, or external mutations.
- Removing `tonys-nix/modules/agents` during the first extraction wave.
