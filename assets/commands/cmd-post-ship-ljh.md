Prepare a release or external operation for explicit approval.

Use `skl-post-ship-ljh` and the internal deterministic policy gate to verify
environment, target, scope digest, rollback, observation, idempotency, and
evidence. This command does not execute deployment, migration, push, merge, or
external mutation. Missing or ambiguous approval is `BLOCKED`.
