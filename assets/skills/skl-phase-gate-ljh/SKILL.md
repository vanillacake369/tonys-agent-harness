---
name: skl-phase-gate-ljh
description: Enforce deterministic policy, scoped Human Gate approval, sandbox, and single-writer execution boundaries.
---

# Phase Gate Skill

- Separate sandbox permissions from approval state.
- Reject missing, malformed, denied, or scope-mismatched approvals.
- Do not allow project or skill configuration to weaken global policy.
- Keep research and review read-only.
- Require explicit approval for destructive, security-sensitive, migration,
  deployment, external, production, and money-related actions.
- A Judge recommendation can never downgrade a deterministic block.
