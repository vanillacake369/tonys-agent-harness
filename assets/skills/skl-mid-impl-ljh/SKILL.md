---
name: skl-mid-impl-ljh
description: Implement approved code or infrastructure changes with TDD, focused scope, and verification evidence.
---

# Mid-Implementation Engineering Skill

Use only after an approved PRD, design, test specification, and execution
plan exist.

- One writer owns repository mutations.
- Write the failing test first unless an explicit exemption is recorded.
- Apply the smallest coherent change using local patterns.
- Refactor only after green verification.
- Record commands, exit codes, changed files, diff summary, and residual risk.
- Never infer deployment or external mutation permission from implementation
  approval.

The VPP code-safety guardrail is mandatory for multi-file, business-logic,
database, or infrastructure changes.
