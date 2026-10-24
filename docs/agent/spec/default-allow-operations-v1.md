# Default-Allow Operations v1 — Superseded Implementation Specification

Status: Superseded by [Default-Allow Operations v2](default-allow-operations-v2.md)

This document is retained as implementation history and is not authoritative.

This document merges and supersedes ADR-0003, the 2026-10-21 permissive
operations PRD, and its test/TODO workflow. `AGENTS.md` remains the behavioral
source of truth; this specification defines the executable operation guardrail.

## Objective and non-goals

All activated providers use the provider-neutral profile
`default-allow-operations-v1`. The profile permits ordinary work, project
reads/writes allowed by the active role, networking, infrastructure access,
local commits, ordinary non-force pushes, resource creation/start, and Nix
activation. It blocks only versioned, well-known dangerous forms plus immutable
secret-path and catastrophic local-destruction invariants.

This is an accident-prevention rail, not a security boundary. Unknown,
unparseable, wrapped, aliased, computed, scripted, SDK, HTTP, MCP, browser, and
computer-use forms are allowed by design. Strong protection requires scoped
credentials, server-side authorization/admission policy, or a typed broker.

## Provider-neutral SSOT and porters

- The manifest selects one shared operation policy. Provider adapters translate
  the shared contract into native hook/config shapes and cannot redefine it.
- Codex, Claude, Gemini, and Kiro are supported when their hook porter is active.
- Operation-policy activation has one state machine: `PENDING`, `ENFORCED`,
  `FAILED`, `UNAVAILABLE`, or `UNSUPPORTED`. Unknown manifest providers fail
  before activation with `UNKNOWN_PROVIDER`; `DEGRADED` is not a state.
- Startup performs advisory diagnosis and notification only. `ENFORCED` is
  established solely by a successful blocking PreTool activation latch for the
  current scoped fingerprint.
- Role-specific filesystem/network restrictions remain in force. This profile
  changes operation classification, not agent-role ownership.

## Decision order

1. Deny secret/credential paths (`.env`, `secrets`, credentials, private keys,
   `.ssh`, `.gnupg`) and catastrophic broad filesystem destruction.
2. Deny an exact recognized rule below and emit its stable reason ID.
3. Allow everything else, including parse failures.

Denied commands enter one feedback path and ask the user to review, execute the
operation directly if desired, and report the result. Ordinary feedback may
include the original command. Secret/credential reasons and privacy-tainted
payloads redact it. A best-effort desktop notification contains only command
family and reason. Notification failure never allows the command and never
causes an unbounded wait/retry.

Telemetry stores only timestamp, provider, command family, reason ID, and a
SHA-256 command hash. It never stores raw commands, SQL, secrets, or credentials.
The same session + command hash + reason notification is deduplicated for 60
seconds. Telemetry append and dedupe state are concurrency-safe and fail without
changing the denial decision.

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

Allow plan/show/validate/preview/template/read operations. As an explicit
usability exception, allow `terraform apply`, `tofu apply`, `pulumi up`, and
`helm upgrade --install`, accepting that they may update resources. Deny
explicit destroy/removal/state mutation such as destroy, state rm/mv,
uninstall, and rollback. Fully allow nixos-rebuild, darwin-rebuild, and
home-manager activation.

## Mutable native configuration ownership

Provider-native runtime configuration remains writable and provider-owned:
`~/.codex/config.toml`, `~/.claude/settings.json`,
`~/.gemini/settings.json`, `~/.kiro/settings/**`, and native hook registries.
The harness owns only stable-ID managed fragments plus the shared runtime gate
and SSOT.

Activation upserts the managed fragment without replacing whole files or hook
arrays, preserves provider-added model/UI/project/plugin/hook settings, repairs
deleted/tampered managed entries, migrates known provider schemas, and creates
timestamped mode-0600 backups retaining the newest three. Startup performs
lightweight advisory diagnosis. The blocking PreTool latch validates relevant
managed structure and runtime identity before classification; failure notifies
and blocks the tool. Hook removal remains detectable only by doctor or a later
activation.

## Implementation workflow and acceptance

### Pre

- Consolidate this specification and mark its inputs superseded.
- Freeze reason IDs, porter capabilities, fragment IDs, and fixture matrix.
- Preserve unrelated user worktree changes.

### Mid

- Implement one provider-neutral classifier and decision model.
- Implement privacy-safe notifier/telemetry and 60-second deduplication.
- Implement JSON/TOML managed-fragment upsert, backup rotation, activation, and
  preflight for Codex/Claude/Gemini/Kiro.
- Add paired allow/deny tests for every family and characterization tests for
  accepted bypasses. Tests must perform no real external mutation.
- Validate structured output and provider capability states.

### Post

- Run focused Python/Bats/Nix checks, full repository checks, fixture/native
  smoke tests, and independent review. Repair findings and repeat.
- Commit no more than three responsibilities, then push the harness.
- Update `tonys-nix` to the published harness revision, run its native checks,
  commit, and push.

Acceptance requires provider-neutral selection, matching semantics across all
supported porters, default-ALLOW/parse-failure-ALLOW behavior, stable privacy-
safe denial feedback, managed-fragment preservation/repair/backup behavior,
truthful activation states, green documented verification, and downstream
consumption. Rollback selects the prior policy/removes the stable managed
fragment; provider-owned settings and backups remain recoverable.

The standalone `curl | sh`/`curl | bash` path-guard rule is not part of the
matrix and must be removed; HTTP and downloaded scripts remain accepted
default-allow residual risk.
