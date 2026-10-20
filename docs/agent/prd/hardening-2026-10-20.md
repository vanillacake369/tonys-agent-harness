# PRD: 2026-10-20 Harness Usability Hardening

## Objective

Remove false-positive policy blocks and complete provider activation without
weakening secret, destructive-operation, or external-mutation boundaries.
This is a focused hardening slice of the Phase 0–5 plan; it is not the Rust
migration itself.

## Requirements

### AH-261020-001 — Local engineering operations

- Status: ready
- Repository-local commits created through the verified commit workflow do not
  require an external-operation approval receipt.
- Push, merge, release, deployment, migration, destructive commands, and
  external mutation remain approval-scoped.
- Declared Nix builds and ordinary rootless container-backed tests are treated
  as local tests/builds. Native sandbox escalation may still be required for a
  host socket or network, but the shared hook must not reject them by name.

### AH-261020-002 — Path-guard precision

- Status: ready
- Sensitive path checks evaluate path-bearing command tokens and provider file
  fields, not arbitrary search text.
- Searching documentation for words such as `secrets` or `credentials` is
  allowed when no sensitive path is addressed.
- Actual `.env`, secret, credential, SSH, GnuPG, private-key, and key-file paths
  remain blocked.

### AH-261020-003 — Shell compatibility

- Status: ready
- Benign command substitution and backticks are not rejected solely because
  they are difficult to parse.
- Known destructive or external operations nested in a shell command remain
  approval-scoped or blocked.

### AH-261020-004 — Lifecycle lock recovery

- Status: ready
- Concurrent lifecycle state transitions remain serialized.
- Lock ownership records process and creation metadata.
- A dead owner cannot permanently block future sessions; a live owner is never
  silently displaced.

### AH-261020-005 — SRP commit contract

- Status: ready
- Commit planning runs before staging from an explicit responsibility plan.
- Every responsibility has its own requirement IDs, files, verification
  command, and result commit.
- Planning rejects overlapping files, unassigned scope, duplicate
  responsibilities, and plans that differ from the committed patch.

### AH-261020-006 — Provider-native activation

- Status: ready
- Codex command facades and reusable procedures are Agent Skills under
  `~/.codex/skills/<name>/SKILL.md`.
- Claude command facades and reusable procedures are Agent Skills under
  `~/.claude/skills/<name>/SKILL.md`; the legacy `commands/*.md` surface is not
  required for newly generated artifacts.
- Kiro command facades and reusable procedures are Agent Skills under
  `~/.kiro/skills/<name>/SKILL.md`. Markdown files must not be presented as
  workflows: reusable Kiro workflows require a `.workflow.json`,
  `.workflow.yaml`, or `.workflow.yml` recipe.
- Gemini command facades and adapted skill entry points are TOML custom
  commands under `~/.gemini/commands/*.toml`; Markdown command files are not a
  valid Gemini command surface.
- Activation tracks only harness-owned links, preserves unmanaged files, and
  removes only stale links that still point into the generated bundle.
- Codex uses the same shared activation mechanism; consumer repositories do not
  duplicate provider installation policy.

### Provider research baseline (2026-10-20)

| Provider | Official native contract | Local verification status |
| --- | --- | --- |
| Codex | User skills live below `~/.codex/skills`; repository instructions use `AGENTS.md`. | CLI 0.162.1 installed; target discovery is locally verifiable. |
| Claude Code | Personal skills live below `~/.claude/skills`; custom commands are now skills, while legacy command Markdown remains compatible. | `UNAVAILABLE`: CLI not installed. Static format and activation checks only. |
| Kiro CLI | Global skills live below `~/.kiro/skills`; workflows are JSON/YAML recipes with a `.workflow.*` suffix. | CLI 2.31.1 installed; target discovery is locally verifiable. |
| Gemini CLI | Global custom commands live below `~/.gemini/commands` and must be TOML; global context uses `~/.gemini/GEMINI.md`. | `UNAVAILABLE`: CLI not installed. Static TOML and activation checks only. |

Sources: OpenAI Build skills and AGENTS guidance, Anthropic Claude Code Skills,
Kiro configuration and workflow authoring, and Gemini CLI custom-command and
context documentation. Provider docs are temporal dependencies and must be
rechecked when adapter formats change.

## Non-goals

- Completing the Rust migration.
- Replacing provider-owned mutable settings files.
- Bypassing a provider-native sandbox for container sockets or network access.
- Push, merge, release, or deployment without explicit user authorization.

## Acceptance Criteria

- Focused Python, Bats, and Nix contract tests cover every requirement above.
- The full harness test suite and `nix flake check` pass.
- Native provider target paths contain the generated skills/commands after Home
  Manager activation, or are reported as unavailable with evidence.
- `tonys-nix` consumes the pushed harness revision and has no duplicate Codex
  activation implementation.
