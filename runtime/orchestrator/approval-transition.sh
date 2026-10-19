#!/usr/bin/env bash
# Transition only a cryptographically verified approval request to execution.
set -euo pipefail
INPUT=$(cat)
if ! jq -e '
  .decision.selected_action == "HUMAN_APPROVAL" and
  .human_approval.status == "approved" and
  .human_approval.verification == "external-receipt" and
  (.human_approval.scope_digest | type == "string" and length > 0)
' <<<"$INPUT" >/dev/null 2>&1; then
  echo "approval transition blocked: verified approval request required" >&2
  exit 2
fi
jq -c '.decision.selected_action="AUTO_EXECUTE" |
  .decision.next_action="execute-approved-scope"' <<<"$INPUT"
