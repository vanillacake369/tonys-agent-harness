---
name: a2a-workflow
description: Orchestrate complex repository work through scoped research, architecture, planning, single-writer implementation, independent verification, targeted repair, and compact handoff. Use for multi-file, risky, ambiguous, architectural, migration, security-sensitive, or explicitly requested A2A tasks. Do not use the full workflow for trivial edits.
---

# A2A Workflow

## Trigger

Use this skill when the user requests `A2A Workflow`, `$a2a-workflow`, or work is multi-file, risky, ambiguous, architectural, migration-related, security-sensitive, destructive, or research-dependent. Do not run the full workflow for trivial edits.

## Complexity Routing

Classify first:

- `Trivial`: Executor -> Targeted Verification -> Compact
- `Standard`: Research-lite -> Plan -> Guardrail Precheck -> Executor -> QA -> Review-lite -> Compact
- `Complex`: Research + Architecture -> Planner -> Guardrail Precheck -> Executor -> QA + Reviewer + Guardrail Verification -> Fix Loop -> Compact

Read `references/routing.md` before classifying non-trivial work.

## Orchestration Order

1. Gather only the context needed for the selected route.
2. Pass compact structured artifacts between phases, not raw logs.
3. Freeze the plan before writes; update it only when new evidence requires a scoped deviation.
4. Reuse existing repository commands, tests, linters, formatters, and CI-equivalent checks where available.

## Delegation Policy

Delegate only independent read-only research, architecture, QA, review, or guardrail verification. Repository writes have one owner: the Executor. Do not run concurrent writers or let subagents edit implementation files.

Read `references/agent-contracts.md` when assigning roles or validating role outputs.

## Mandatory Gates

Run Guardrail Precheck before implementation for Standard and Complex routes. Run Guardrail Verification before completion for Complex routes or any task with security, migration, destructive, compatibility, dependency, or secret exposure risk.

Read `references/guardrails.md` for checklists and blocker handling.

## Fix Loop Policy

When QA, review, or guardrail verification fails, deduplicate findings, classify blocking status, have the Executor make the smallest related fix, and rerun targeted verification first. Default maximum is 3 iterations unless repository rules set a stricter limit. Do not weaken tests or bypass guardrails to declare completion.

## Final Handoff

Finish with the Compact Handoff schema only. Preserve decisions, changes, verification, remaining risks, and the next smallest actionable task; omit raw logs and discarded hypotheses.

Read `references/artifact-schemas.md` before producing phase artifacts or the final handoff.
