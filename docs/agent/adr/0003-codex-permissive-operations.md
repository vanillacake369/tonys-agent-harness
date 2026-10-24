# ADR-0003: Codex Default-Allow Well-Known Mutation Guardrail

## Status

Superseded by [Default-Allow Operations v1](../spec/default-allow-operations-v1.md).
This document is retained as design history and is not an implementation source.

## Context

Native filesystem/network policy controls reachability, not SQL, HTTP, SDK, or
remote-resource semantics. A shell hook cannot prove an arbitrary command is
read-only. The earlier fail-closed design interrupted ordinary work while still
being bypassable through variables, aliases, scripts, drivers, HTTP, MCP,
browser, and computer-use paths.

## Agreement and conflict resolution

- `AGREEMENT`: Codex-only selection; secret/destruction invariants; workspace
  writes; sibling reads; network/infrastructure access; ordinary push.
- `AGREEMENT`: native sandbox and hook classification are separate layers and
  must not overclaim arbitrary external-state protection.
- `AGREEMENT`: versioned well-known signatures are useful accident prevention.
- `CONFLICT RESOLVED`: strong prevention conflicts with unrestricted
  Bash/network/credentials. Convenience wins; unknown forms are allowed and
  the residual risk is explicitly accepted.
- `CONFLICT RESOLVED`: create/start changes state, but recognizable
  create/run/start has standing authorization. Create-or-update forms such as
  `kubectl apply` remain denied.

## Decision

Adopt `codex-permissive-operations-v1` with this order:

1. deny immutable secret-path and catastrophic local-destruction violations;
2. deny an exact recognized rule from the PRD inventory;
3. otherwise allow.

Codex declares workspace write, sibling-project read, secret denies, command
network access/local binding, and `approval_policy = "never"`. Other providers
do not select the profile. Unknown, wrapped, aliased, computed, scripted, SDK,
HTTP, MCP, browser, and computer-use operations are allowed by design.

This is a usability safety rail, not a security boundary. Hard guarantees need
scoped/read-only credentials, server-side controls, admission policy, or typed
brokers unavailable to generic Bash.

## Consequences and maintenance

- Normal work has fewer false-positive interruptions.
- Common accidental mutations receive stable denials.
- False negatives are expected and documented.
- Each new rule needs a concrete fixture, allow counterexample, reason ID, and
  regression test; speculative broad regexes are rejected.

## Validation and rollback

Table-test every supported family, characterize bypasses as accepted gaps,
validate generated config/native smoke probes, prove provider isolation, and
run focused then repository-wide checks. Never perform a real external write.
Rollback disables the Codex profile and restores the former hook/config
projection; future brokers or credentials require a separate ADR.

## Rejected alternatives

- Comprehensive regex enforcement: shell text cannot establish remote meaning.
- Fail closed for unknown commands: disruptive without a true security boundary.
- Global relaxation: violates provider isolation.
- No guard at all: loses cheap protection against common mistakes.
