Evidence-first debugging workflow for repeated hook/runtime failures, policy or
guardrail regressions, stale state/config problems, and explicit requests for
the user's preferred senior/reviewer/cross-validator loop with local proof,
deterministic validation, post review, postmortem, and remarks.

# Task
$ARGUMENTS

# Workflow

Use this workflow to turn repeated workflow failures into a proven root cause,
implemented fix, review loop, and concise postmortem.

## Operating Contract

Treat local evidence as the source of truth. Do not claim a cause, fix, or
passing state until it is supported by files, logs, direct tool execution,
tests, or reproducible commands.

Keep the loop small:

1. Reproduce or falsify the failure with local evidence.
2. Label each important evidence source as repo, runtime, generated, external,
   or untrusted.
3. Prove a causal chain: symptom -> failing mechanism -> local source or config
   -> proposed fix.
4. Define at least one falsifiable check that should fail before the fix and
   pass after it.
5. Compare fixes and choose the smallest durable guardrail.
6. Implement only the scoped change.
7. Run focused validation first, then broader validation when risk warrants it.
8. Run post review with independent perspectives when the task asks for it or
   the blast radius is non-trivial.
9. Iterate until review passes or report a concrete blocker.

Mark causal claims as unverified when reproduction is not possible. Avoid
presenting "likely", "probably", or "seems" as root cause proof.

## Evidence Collection

Start by locating the executable contract and generated artifacts involved in
the failure. Prefer `rg` and existing test runners. For hook and agent runtime
issues, inspect the active provider config, generated hook commands, hook state,
event logs, session logs, and the scripts referenced by the config.

When investigating hook failures:

- Run every hook command that is currently configured with realistic minimal
  payloads.
- Capture exit codes, stderr, and the exact command path.
- Distinguish stale session state from a currently failing hook.
- Confirm whether generated provider config still contains the failing hook.
- Search logs for real failure events, not only the literal text of prior user
  prompts or search commands.

Use fresh absolute dates or timestamps when explaining temporal behavior such as
stale state, session-specific config, or regenerated files.

Do not inspect secrets, private keys, `.env`, `.ssh`, `.gnupg`, or credential
stores unless the user explicitly requires it and the repository policy allows
that access.

## Guardrail Design

Prefer deterministic guardrails over agent memory. Put enforceable behavior in
tests, assertions, hook scripts, or provider generation code when practical.
Use skill text for workflow order, escalation rules, and validation discipline.

A guardrail is acceptable only if it has:

- A specific trigger condition.
- A clear expected behavior.
- A focused validation command or local check.
- A rollback path or low-risk failure mode.

Avoid broad provider-specific policy changes before checking the shared
contract under `nix/agents/` and any relevant specs.

## Delegation Loop

Use subagents only when the user asks for multi-agent review or when independent
review materially reduces risk. Keep prompts bounded and do not leak the
intended answer unless the review explicitly requires it.

Use these perspectives:

- Senior/architect: tradeoffs, blast radius, lifecycle fit, rollback, and
  durable guardrail placement.
- AI expert/reviewer: skill trigger precision, context cost, validation
  integrity, and failure modes for future agents.
- Real-user reviewer: whether the workflow matches the user's actual repeated
  requests and produces useful final reports.
- Cross-validator: independent check that local evidence supports the final
  claim.

Post review passes only when reviewers find no blocking issue or all blocking
issues have been fixed and rechecked. If subagent quota, tooling, or external
state prevents review, say so and do not present the review as passed.

Do not require subagents for trivial, local, reversible failures. Prefer a
deterministic check when it answers the question directly.

## Validation Gates

Before declaring completion, run all applicable gates:

- Structure: validate created skills with the skill validation script.
- Behavior: run focused tests or direct hook/script executions that cover the
  reported failure.
- Regression: run the repo's existing checks when the touched surface is shared.
- Diff hygiene: inspect the diff and avoid unrelated changes.
- Review: record reviewer outcomes and any residual risk.

If validation fails, change the approach instead of repeating the same command
without new information.

Do not bypass, disable, or weaken hooks and policy guardrails as a fix unless
the user explicitly asks for that policy change and the local contract supports
it. Prefer fixing stale state handling, provider generation, tests, or hook
behavior.

## Postmortem And Remark

End substantial investigations with a concise postmortem:

- Task
- Outcome
- What worked
- What failed
- Root cause
- Validation evidence
- Follow-up actions
- Policy or skill changes proposed
- Changes deferred

Add a short remark that explains what should be done differently next time. Keep
it operational: the remark should help the next Codex session avoid the same
failure mode.

Persist a handoff or postmortem artifact only when it will be useful beyond the
current conversation. Do not create root-level session logs by default.
