# Agent Harness Verification Checklist

Statuses are `SATISFIED`, `PARTIAL`, `NOT_SATISFIED`, `UNAVAILABLE`, and
`BLOCKED_BY_APPROVAL`. Only current revision-bound evidence can produce
`SATISFIED`.

| Area | Required evidence | Current status |
|---|---|---|
| Sandbox/approval separation | normalized fields plus native boundary probes | PARTIAL |
| Hook coverage | pre, post, failure, completion, and bypass-negative tests | PARTIAL |
| MCP | allowlist, evidence binding, UNKNOWN reconciliation | PARTIAL |
| Instruction SSoT | byte equality plus native loading per provider | PARTIAL |
| Public commands/skills | canonical inventory and legacy rejection | NOT_SATISFIED |
| Project-specific harness | manifest-driven provider/HM output | NOT_SATISFIED |
| Evidence completion | command, exit, duration, result, diff, requirement, commit | PARTIAL |
| Retry budget | persistent same-root-cause block after three attempts | SATISFIED |
| Reviewer isolation | static permissions plus native write denial | PARTIAL |
| Memory lifecycle | namespace, secrecy, bounds, conflict, expiry, deletion | PARTIAL |
| External idempotency | operation state, UNKNOWN lookup, duplicate prevention | PARTIAL |
| Git lifecycle | baseline, scope, clean completion, commit evidence | PARTIAL |
| Team guidelines | configured runtime symlink without copied policy | NOT_SATISFIED |
| Approval trust | external editable public-key path and fingerprint | PARTIAL |
| Phase evidence | revision-bound aggregate evidence for Phase 0–5 | NOT_SATISFIED |

## Mandatory Failure Scenarios

- unapproved production, destructive, migration, money, or external mutation;
- hook bypass or malformed native payload;
- completion with unrun tests or hidden failure;
- failing test deletion or disabling without independent review;
- retry budget exceeded;
- dirty or uncommitted code completion;
- duplicate external call after timeout;
- reviewer write attempt;
- provider instruction drift;
- project policy weakening global policy;
- ambiguous approval or changed approval scope;
- missing provider or operational environment reported as passed.
