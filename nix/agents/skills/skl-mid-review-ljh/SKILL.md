---
name: skl-mid-review-ljh
description: Independently review implementation scope, security, tests, and completion evidence.
---

# Mid-Review Engineering Skill

Review PRD, design, diff, tests, policy, and evidence independently from the
implementation assumptions.

- Default to read-only permissions.
- Report findings with severity, evidence, impact, and recommended correction.
- Check security, scope drift, hidden contracts, regression risk, and missing
  traceability.
- Never delete or disable a failing test to obtain a pass.
- Return changes to the implementation owner; do not mutate the repository.
