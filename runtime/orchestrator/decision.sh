#!/usr/bin/env bash
# Combine an untrusted LLM recommendation with deterministic mandatory policy.
# The command always emits a decision JSON object; malformed input is BLOCKED.

set -euo pipefail

INPUT=$(cat)
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

blocked_invalid() {
  jq -cn --arg now "$NOW" '{decision_id:"unknown", selected_action:"BLOCKED", risk_level:"unknown", uncertainty_level:"unknown", affected_requirements:[], applicable_policy_rules:["invalid-decision-input"], evidence_references:[], assumptions:[], unresolved_questions:[], human_approval_required:false, next_action:"repair-decision-input", timestamp:$now}'
}

if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  blocked_invalid
  exit 0
fi

# Missing classifications are unknown, never false. Typed booleans are required
# from the policy producer; the model recommendation cannot supply them.
if ! jq -e '.policy_signals as $p | ($p | type == "object") and
  (["destructive","security_sensitive","migration","deployment","external_resource","money_movement"] |
    all(.[]; ($p[.] | type == "boolean")))' <<<"$INPUT" >/dev/null 2>&1; then
  blocked_invalid
  exit 0
fi

valid=$(printf '%s' "$INPUT" | jq -r '
  (.decision_id // "") as $id |
  (.request // "") as $request |
  ((.risk_level // .llm_judgment.risk_level) // "") as $risk |
  ((.uncertainty_level // .llm_judgment.uncertainty_level) // "") as $uncertainty |
  ((.llm_judgment.recommended_action // "") as $action |
    ($id != "" and $request != "" and ($risk | IN("low","medium","high","critical")) and ($uncertainty | IN("low","medium","high")) and ($action | IN("AUTO_EXECUTE","RESEARCH_REQUIRED","SPEC_QUESTION","HUMAN_APPROVAL","BLOCKED"))))
')

if [[ "$valid" != "true" ]]; then
  blocked_invalid
  exit 0
fi

decision_json=$(printf '%s' "$INPUT" | jq -c '
  . as $root |
  ((.risk_level // .llm_judgment.risk_level)) as $risk |
  ((.uncertainty_level // .llm_judgment.uncertainty_level)) as $uncertainty |
  (.llm_judgment.recommended_action) as $llm_action |
  ((.policy_signals // {}) as $p |
    (($p.destructive // false) or ($p.security_sensitive // false) or ($p.migration // false) or ($p.deployment // false) or ($p.external_resource // false) or ($p.money_movement // false)) as $mandatory |
    (($p.policy_violation // false) or ($p.policy_engine_error // false)) as $policy_block |
    (($root.human_approval.status // "missing")) as $approval_status |
    (($root.human_approval.scope_digest // "") != "" and ($root.human_approval.scope_digest == ($root.request_digest // "")) and $approval_status == "approved") as $approval_valid |
    (($root.llm_judgment.required_questions // [])) as $questions |
    (($root.llm_judgment.repository_researchable // false)) as $researchable |
    (if $policy_block then "BLOCKED"
     elif $approval_status == "denied" then "BLOCKED"
     elif ($mandatory and ($approval_valid | not)) then "HUMAN_APPROVAL"
     elif ($questions | length) > 0 then "SPEC_QUESTION"
     elif $researchable then "RESEARCH_REQUIRED"
     elif $llm_action == "BLOCKED" then "BLOCKED"
     elif $llm_action == "HUMAN_APPROVAL" then "HUMAN_APPROVAL"
     elif $llm_action == "SPEC_QUESTION" then "SPEC_QUESTION"
     elif $llm_action == "RESEARCH_REQUIRED" then "RESEARCH_REQUIRED"
     elif ($risk | IN("high","critical")) then "HUMAN_APPROVAL"
     elif $llm_action == "AUTO_EXECUTE" and $risk == "low" and $uncertainty == "low" then "AUTO_EXECUTE"
     else "BLOCKED" end) as $selected |
    ([
      (if $mandatory then "mandatory-risk-policy" else empty end),
      (if $policy_block then "policy-engine-failure-or-violation" else empty end),
      (if $approval_status == "denied" then "approval-denied" else empty end),
      (if ($mandatory and ($approval_valid | not)) then "scoped-approval-required" else empty end),
      (if ($questions | length) > 0 then "required-question-unresolved" else empty end),
      (if $researchable then "repository-researchable" else empty end)
    ] | unique) as $rules |
    {
      decision_id: $root.decision_id,
      selected_action: $selected,
      risk_level: $risk,
      uncertainty_level: $uncertainty,
      affected_requirements: ($root.affected_requirements // []),
      applicable_policy_rules: $rules,
      evidence_references: ($root.evidence_references // $root.llm_judgment.evidence_references // []),
      assumptions: ($root.assumptions // $root.llm_judgment.assumptions // []),
      unresolved_questions: $questions,
      human_approval_required: ($selected == "HUMAN_APPROVAL"),
      next_action: (if $selected == "AUTO_EXECUTE" then "execute-selected-workflow" elif $selected == "RESEARCH_REQUIRED" then "run-research" elif $selected == "SPEC_QUESTION" then "ask-high-impact-question" elif $selected == "HUMAN_APPROVAL" then "request-scoped-approval" else "stop-and-report" end)
    }
  )
')

printf '%s\n' "$decision_json"
