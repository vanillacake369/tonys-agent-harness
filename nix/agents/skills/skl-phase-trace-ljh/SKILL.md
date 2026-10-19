---
name: skl-phase-trace-ljh
description: Maintain requirement traceability, execution evidence, telemetry, retry state, and Git lifecycle completion.
---

# Phase Traceability Skill

- Keep Markdown PRD as SSoT and TSV as the evidence index.
- Apply state-aware evidence requirements; do not require implementation
  evidence for proposed or deferred requirements.
- Record actual commands, exit codes, duration, changed files, diff summary,
  unresolved errors, and requirement results.
- Enforce the three-attempt retry budget and preserve failure history.
- Do not mark code work DONE with an uncommitted scope or hidden test failure.
