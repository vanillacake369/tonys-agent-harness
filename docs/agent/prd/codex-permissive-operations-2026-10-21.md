# PRD: Codex Default-Allow Operations Guardrail

> Superseded by [Default-Allow Operations v1](../spec/default-allow-operations-v1.md).
> This document is retained as product-decision history only.

## Objective

Provide a Codex-only, low-friction profile for normal work and study. Commands
are allowed by default; a versioned list of well-known destructive or external
mutation forms is denied. This is a best-effort safety rail, not a security
boundary or a guarantee that all remote writes are stopped.

## Scope and invariants

- Only Codex selects this profile. Other providers keep existing behavior.
- Allow active-workspace writes, configured sibling-project reads, network and
  infrastructure access, local work, commits, ordinary pushes, resource
  creation, and resource start.
- Deny secret/credential paths and catastrophic local destruction first.
- Deny a command only when it matches a versioned well-known mutation rule.
  Allow unknown, wrapped, computed, aliased, scripted, SDK, HTTP, and MCP forms.
- Use `approval_policy = "never"`: denied commands fail; all others proceed.
- Emit stable denial reason IDs without logging secrets or full SQL payloads.

## Well-known denylist v1

### Git

Allow ordinary non-force pushes. Deny force variants, mirror, destructive
prune/all combinations, leading-plus refspecs, and deletion refspecs. Custom
Git aliases and computed subcommands remain outside the enforcement claim.

### DBMS clients

Recognize PostgreSQL (`psql`), MySQL/MariaDB (`mysql`, `mariadb`), SQLite
(`sqlite3`), SQL Server (`sqlcmd`), MongoDB (`mongosh`/`mongo`), and Redis
(`redis-cli`).

- Deny recognizable SQL `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `REPLACE`,
  `UPSERT`, `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `GRANT`, `REVOKE`,
  `COPY ... FROM`, `LOAD DATA`, and migration invocations.
- Deny well-known file/input execution whose contents cannot be classified:
  `-f`/`--file`, `-i`, `.read`, `source`, and input redirection.
- Allow recognizable `SELECT`, `SHOW`, `DESCRIBE`, and `EXPLAIN` forms.
- Deny recognizable MongoDB insert/update/replace/delete/bulk-write/drop/rename,
  index mutation, and shutdown methods.
- Deny recognizable Redis key/data/config mutations, including `SET`, `MSET`,
  `DEL`, `UNLINK`, expiry/rename, collection and stream writes, `FLUSH*`,
  `CONFIG SET`, `ACL SETUSER`, `MIGRATE`, and `RESTORE`.
- Unrecognized clients, procedures, encoded payloads, drivers, application code,
  and generic HTTP requests are allowed.

### Docker and Podman

- Allow inspection/read commands, build, pull, and explicit create/run/start.
- Deny recognizable mutation/removal of existing resources: rm/rmi, stop, kill,
  restart, pause/unpause, rename, update, exec, inbound cp, commit, push, prune,
  and resource-removal commands.
- For Compose, allow config/inspection/build/pull/create/start. Deny `up` because
  it may recreate/update, plus down/stop/restart/rm/kill/exec/push.

### kubectl, Kustomize, and kubeadm

- Allow kubectl get/describe/logs/explain/diff/top/version/cluster-info, API
  discovery, `auth can-i`, config inspection, and explicit create/run.
- Deny apply, patch, edit, replace, delete, scale, set, annotate, label, taint,
  cordon/uncordon/drain, autoscale, exec/cp/attach/debug, and rollout
  restart/undo.
- Allow standalone `kustomize build`, inspection, and local `kustomize edit`.
  Deny cluster mutation at the consumer: `kubectl apply -k` and a visible
  `kustomize build | kubectl apply` pipeline.
- Allow kubeadm version/config display/image listing/certificate inspection and
  upgrade planning. Deny init, join, reset, upgrade apply/node, token
  create/delete, certificate renewal, and their mutating phase commands.

## Decision matrix

| Input class | Decision | Claim |
| --- | --- | --- |
| Secret path or catastrophic local destruction | DENY | Native sandbox/gate |
| Enumerated well-known mutation form | DENY | Best-effort classifier |
| Enumerated read/create/start form | ALLOW | Standing authorization |
| Unknown/wrapped/aliased/scripted/SDK/HTTP/MCP form | ALLOW | Unprotected by design |
| Non-Codex provider | Existing policy | No change |

## Accepted residual risk and non-goals

Examples intentionally outside the guarantee include `g=git; $g push`, custom
aliases, generated SQL, Python SDK writes, and `curl -X DELETE`. Complete
external-mutation prevention requires scoped/read-only credentials, server-side
authorization/admission policy, or a typed broker and is a separate design.
This profile does not parse every shell/client grammar, block local manifest
editing, or protect MCP/browser/computer-use surfaces.

## Acceptance criteria

- An unclassified command defaults to `ALLOW`.
- Each family has positive allow tests and focused deny tests.
- Bypass cases are recorded as accepted false negatives, not protected cases.
- Tests execute no real external mutation.
- Native probes verify workspace write, sibling read, secret denial, and network
  access on the supported Codex version.
- Existing non-Codex tests remain green; rollback disables
  `[codex].permissive_operations` without external-state migration.
