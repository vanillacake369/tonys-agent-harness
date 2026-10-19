---
name: skl-pre-adr-ljh
description: Compare independent strategies and produce an ADR with explicit agreement, conflict, and validation evidence.
---

# Pre-ADR Decision Skill

Run Strategist A and B independently against the same PRD, repository context,
and research evidence. Normalize claims and classify each as `AGREEMENT`,
`CONFLICT`, `UNVERIFIED`, or `COMPLEMENTARY`.

- Do not treat agreement as proof.
- Do not average unresolved conflicts.
- Record safe defaults, validation plans, rejected alternatives, and rollback.
- Produce ADR evidence without executing implementation or external changes.

The LLM Judge and Review Gate remain advisory; deterministic policy owns
execution authority.
