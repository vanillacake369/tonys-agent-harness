---
name: tool-git-evidence
description: Synthetic read-only Git evidence test fixture for the contract suite.
---

## Inputs

Use only a disposable fixture repository and a relative tracked path.

## Decision and Steps

The fixture contract declares `bash capability/tool/tool-git-evidence/scripts/git-evidence.sh`.
The installed relative executable is `scripts/git-evidence.sh`.

## Output

Return the observed fixture status as JSON.

## Stop Condition

Reject invalid paths and unavailable repositories.
