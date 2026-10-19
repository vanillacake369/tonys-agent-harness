# Artifact Schemas

Use concise Markdown artifacts. Preserve evidence and decisions, not raw transcripts.

## Classification

```markdown
## Classification
- complexity: trivial | standard | complex
- reason:
- selected_route:
- omitted_phases:
- escalation_conditions:
```

## Research

```markdown
## Findings
- ...

## Evidence
- `path` or command/source/date: finding

## Constraints
- ...

## Unknowns
- ...

## Recommended Direction
- ...
```

## Architecture

```markdown
## Current Architecture
- ...

## Proposed Architecture
- ...

## Alternatives And Trade-offs
- ...

## Affected Boundaries
- ...

## Risks
- ...

## Decision
- ...
```

## Plan

```markdown
## Scope
- ...

## Non-goals
- ...

## Ordered Tasks
1. task:
   files:
   verification:
   done_when:

## Files Likely To Change
- `path`

## Definition Of Done
- ...
```

## Guardrail Gate

```markdown
## Guardrail Gate
- status: pass | mitigated | blocked
- gate: precheck | verification

## Checks
- requirement alignment:
- security/privacy:
- destructive behavior:
- compatibility:
- dependency/license:
- migration/rollback:
- testability:
- user changes:
- secrets:
- documentation:

## Mitigations
- ...

## Blockers
- ...
```

## QA

```markdown
## Commands Run
- command: result

## Passed Checks
- ...

## Failed Checks
- ...

## Untested Areas
- ...

## Reproduction Steps
- ...
```

## Review

```markdown
## Blocking
- file/component:
  problem:
  impact:
  evidence:
  recommended fix:

## Important
- ...

## Minor
- ...
```

Use `No material findings` under a severity when applicable.

## Fix Loop

```markdown
## Fix Loop
- iteration: 1 | 2 | 3
- failed_gate:
- deduplicated_findings:
- blocking:
- root_cause:
- executor_fix:
- targeted_verification:
- remaining_failures:
- escalation_needed:
```

## Compact Handoff

```markdown
## Outcome
- status: completed | partial | blocked
- objective:
- result:

## Decisions
- ...

## Changes
- `path`: summary

## Verification
- command: result

## Remaining Risks
- ...

## Next Task
- smallest actionable next step
```
