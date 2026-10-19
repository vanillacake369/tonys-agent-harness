#!/usr/bin/env bash
# Convert a policy decision into a phase plan without executing mutations.
# This is the execution boundary: an approval request is not an approval.

set -euo pipefail

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  jq -cn '{status:"BLOCKED",next_action:"repair-plan-input",reason:"invalid-plan-input"}'
  exit 0
fi

printf '%s' "$INPUT" | jq -c '
  . as $root |
  ($root.phase // "") as $phase |
  ($root.decision // {}) as $decision |
  ($root.request_digest // "") as $digest |
  (($root.human_approval.status // "missing") == "approved"
    and ($root.human_approval.scope_digest // "") != ""
    and ($root.human_approval.scope_digest == $digest)) as $approval_valid |
  (($decision.selected_action // "BLOCKED")) as $action |
  (if ($phase | IN("3","4","5")) | not then "BLOCKED"
   elif $action == "BLOCKED" then "BLOCKED"
   elif $action == "SPEC_QUESTION" or $action == "RESEARCH_REQUIRED" then $action
   elif $action != "AUTO_EXECUTE" then "BLOCKED"
   elif (($decision.human_approval_required // false) or $phase == "5") and ($approval_valid | not) then "BLOCKED"
   else "READY_TO_EXECUTE" end) as $status |
  {
    phase: $phase,
    status: $status,
    decision_id: ($decision.decision_id // "unknown"),
    write_owner: (if $status == "READY_TO_EXECUTE" then "single-implementation-owner" else null end),
    roles: (if $phase == "3" then ["repository-archaeologist","code-designer","test-designer","implementer","independent-reviewer"]
            elif $phase == "4" then ["skill-evaluator","independent-reviewer"]
            elif $phase == "5" then ["release-sre-engineer","security-reviewer","independent-reviewer"]
            else [] end),
    gates: ["decision-policy", "scoped-human-approval", "traceability", "evidence", "single-writer"],
    next_action: (if $status == "BLOCKED" then "stop-and-request-or-repair-approval"
                  elif $status == "SPEC_QUESTION" then "resolve-spec-question"
                  elif $status == "RESEARCH_REQUIRED" then "run-research"
                  else "execute-plan-with-independent-review" end)
  }
'
