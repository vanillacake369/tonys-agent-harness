# Codex Dynamic Permission Capability Research

## Question

Can the Codex provider adapter apply, revoke, and observe task/session-scoped
directory or network grants at runtime through a documented native contract?

## Official Evidence

- OpenAI describes the harness as the control plane for tool routing,
  approvals, tracing, recovery, and run state, while the sandbox is the
  execution plane that owns files, commands, ports, mounts, and
  provider-specific isolation.
  <https://developers.openai.com/api/docs/guides/agents/sandboxes>
- OpenAI states that the host application decides which files or tools are
  accessible, which actions require approval, and how work is observed.
  <https://developers.openai.com/blog/codex-as-a-platform>
- Codex plugin configuration documents static enablement and approval policy
  for bundled MCP tools and trusted lifecycle hooks. It does not establish a
  task-scoped API that mutates filesystem/network sandbox grants and returns
  applied/revoked observed state.
  <https://developers.openai.com/plugins/build/plugins>

Accessed: 2026-10-21.

## Finding

`UNVERIFIED` that Codex CLI exposes runtime grant mutation, revocation, and
observed-state APIs. Absence from the reviewed official documentation is not
proof that an internal mechanism does not exist, but it is insufficient for a
positive enforcement claim.

## Decision

The Codex capability report declares dynamic permissions `unsupported` and
`unenforceable`. Static workspace/network/secret settings remain a separate
supported surface. Hooks may transport canonical decisions but cannot turn an
unobserved grant into `ALLOW`.

A future adapter may change this status only with version-bound native evidence
for apply, deny/out-of-scope behavior, revoke/expiry, and observed effective
state. A brokered executor or sandbox provider is the current viable outbound
enforcement boundary.
