# Agent Contracts

Use these contracts as phase I/O. Each phase consumes the previous compact artifact plus relevant repository evidence. Implementation files are modified only by the Executor.

## Research Agent

Purpose: investigate requirements, relevant code, docs, dependencies, and prior implementation. No writes.

Output:

- `Findings`: facts separated from assumptions.
- `Evidence`: file paths, commands, official sources, dates for external sources.
- `Constraints`: repository, policy, dependency, compatibility, or user constraints.
- `Unknowns`: unresolved questions and why they matter.
- `Recommended direction`: implementation-neutral next direction.

## Architecture Agent

Purpose: analyze current structure, impact boundaries, and viable designs. No writes.

Output:

- `Current architecture`
- `Proposed architecture`
- `Alternatives and trade-offs`
- `Affected boundaries`
- `Risks`
- `Decision`

Research and Architecture may run in parallel only when independent. Planner waits for both outputs.

## Planner

Purpose: convert research and architecture into small executable tasks.

Output:

- `Scope`
- `Non-goals`
- `Ordered tasks`
- `Files likely to change`
- `Verification per task`
- `Definition of done`

Freeze the plan before writes. If new evidence changes the plan, record the deviation and update only the affected tasks.

## Guardrail Precheck

Purpose: decide whether implementation may start.

Output:

- `Status`: pass | mitigated | blocked
- `Risks`
- `Mitigations`
- `Blockers`
- `Plan updates`

Stop on unmitigated high risk.

## Executor

Purpose: implement the approved plan as the single repository writer.

Rules:

- Follow existing conventions and local abstractions.
- Keep changes inside the approved scope.
- Add or update tests when behavior changes.
- Run the narrowest useful verification after each task.
- Record deviations and reasons.
- Do not hide failing checks.

## QA Agent

Purpose: verify behavior against requirements and acceptance criteria. No writes.

Output:

- `Commands run`
- `Passed checks`
- `Failed checks`
- `Untested areas`
- `Reproduction steps`

Prefer existing repository commands and CI-equivalent commands.

## Reviewer

Purpose: review the diff for correctness, maintainability, concurrency, performance, and error handling. No writes.

Output findings in this order:

- `Blocking`
- `Important`
- `Minor`

Each finding includes:

- `file` or `component`
- `problem`
- `impact`
- `evidence`
- `recommended fix`

If there are no material issues, write `No material findings`.

## Guardrail Verification

Purpose: recheck completed changes against policy and scope. No writes.

Output:

- `Requirements compliance`
- `Scope creep`
- `Security`
- `Destructive behavior`
- `Secret exposure`
- `Compatibility`
- `Migration and rollback`
- `Test evidence`
- `Documentation consistency`
- `Status`: pass | failed | blocked
