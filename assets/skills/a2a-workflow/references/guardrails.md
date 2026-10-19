# Guardrails

Run the relevant checklist before writes and again before completion when risk warrants it.

## Precheck

- Requirements and plan alignment.
- Security and privacy risk.
- Data loss or destructive behavior.
- Backward compatibility.
- Dependency and license impact.
- Migration and rollback need.
- Testability.
- Existing user changes preservation.
- Provider-specific changes checked against shared contracts.

Status:

- `pass`: no material risk.
- `mitigated`: risk exists and mitigation is in the plan.
- `blocked`: implementation must stop until the user or repository evidence resolves the issue.

## Verification

- Requirements satisfied.
- No scope creep beyond approved plan.
- No secret or credential exposure.
- No unauthorized destructive behavior.
- Compatibility impact is intentional and documented.
- Migration and rollback are documented when needed.
- Test evidence supports the change.
- Documentation remains consistent with code and repository policy.

## Fix Loop

When QA, Reviewer, or Guardrail Verification fails:

1. Deduplicate failed items.
2. Classify each as blocking or non-blocking.
3. Identify the smallest related implementation area.
4. Let the Executor make only the necessary fix.
5. Rerun targeted verification first.
6. Run broader checks only when the fix affects shared behavior.
7. Stop after 3 failed iterations or earlier if the same blocker repeats without new evidence.

Never weaken tests, delete meaningful assertions, or bypass guardrails to pass.

## Blocker Report

```markdown
## Blocked
- task:
- gate:
- attempts:
- failure_reason:
- blocker:
- decision_needed:
```
