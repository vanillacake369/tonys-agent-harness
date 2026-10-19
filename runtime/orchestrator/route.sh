#!/usr/bin/env bash
# Deterministic task router shared by provider adapters.
# It selects a minimum route; it never edits files, delegates agents, or approves writes.

set -euo pipefail

if [[ $# -gt 0 ]]; then
  PROMPT="$*"
else
  PROMPT=$(cat)
fi

lower=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

complex_pattern='rm[[:space:]]+-rf|reset[[:space:]]+--hard|force[[:space:]-]*push|drop|truncate|migrat(e|ion)|revoke|production|credential|secret|authentication|authorization|concurrency|distributed|architecture|redesign|external[[:space:]]+(api|service)|sla|slo'
standard_pattern='multi[-[:space:]]*file|several[[:space:]]+files|feature|bug|fix|refactor|test|performance|documentation|skill|workflow|nix|config|module'

if printf '%s' "$lower" | grep -qE "$complex_pattern"; then
  complexity=complex
  route=full
  workflows='["cmd-vpp-work-ljh","skl-phase-route-ljh","skl-pre-research-ljh","skl-pre-adr-ljh","skl-mid-review-ljh"]'
elif printf '%s' "$lower" | grep -qE "$standard_pattern"; then
  complexity=standard
  route=standard
  workflows='["cmd-vpp-work-ljh","skl-pre-prd-ljh","skl-mid-impl-ljh","skl-mid-review-ljh"]'
else
  complexity=trivial
  route=trivial
  workflows='["cmd-vpp-work-ljh","skl-phase-route-ljh"]'
fi

if command -v shasum >/dev/null 2>&1; then
  REQUEST_DIGEST=$(printf '%s' "$PROMPT" | shasum -a 256 | awk '{print $1}')
else
  REQUEST_DIGEST=$(printf '%s' "$PROMPT" | sha256sum | awk '{print $1}')
fi
DESTRUCTIVE=false
SECURITY=false
MIGRATION=false
DEPLOYMENT=false
EXTERNAL=false
MONEY=false
if printf '%s' "$lower" | grep -qE 'rm[[:space:]]+-rf|reset[[:space:]]+--hard|drop([[:space:]].*)?(table|database)|truncate|force[[:space:]-]*push'; then DESTRUCTIVE=true; fi
if printf '%s' "$lower" | grep -qE 'security|credential|secret|authentication|authorization|permission'; then SECURITY=true; fi
if printf '%s' "$lower" | grep -qE 'migrat(e|ion)|schema[[:space:]]+change'; then MIGRATION=true; fi
if printf '%s' "$lower" | grep -qE 'deploy|release|production|rollout'; then DEPLOYMENT=true; fi
if printf '%s' "$lower" | grep -qE 'external[[:space:]]+(api|service|resource)|provision'; then EXTERNAL=true; fi
if printf '%s' "$lower" | grep -qE 'payment|charge|money|billing|purchase'; then MONEY=true; fi

if [[ "$complexity" == "complex" ]]; then
  llm_action=HUMAN_APPROVAL
  risk_level=high
  uncertainty_level=medium
elif printf '%s' "$lower" | grep -qE 'research|investigate|find out|조사|분석'; then
  llm_action=RESEARCH_REQUIRED
  risk_level=low
  uncertainty_level=medium
else
  llm_action=AUTO_EXECUTE
  risk_level=low
  uncertainty_level=low
fi

decision_input=$(jq -cn \
  --arg id "dec-$(date -u '+%Y%m%d-%H%M%S')-${REQUEST_DIGEST:0:8}" \
  --arg request "$PROMPT" \
  --arg request_digest "$REQUEST_DIGEST" \
  --arg action "$llm_action" \
  --arg risk "$risk_level" \
  --arg uncertainty "$uncertainty_level" \
  --argjson destructive "$DESTRUCTIVE" \
  --argjson security_sensitive "$SECURITY" \
  --argjson migration "$MIGRATION" \
  --argjson deployment "$DEPLOYMENT" \
  --argjson external_resource "$EXTERNAL" \
  --argjson money_movement "$MONEY" \
  '{decision_id:$id, request:$request, request_digest:$request_digest, llm_judgment:{recommended_action:$action, risk_level:$risk, uncertainty_level:$uncertainty}, policy_signals:{destructive:$destructive,security_sensitive:$security_sensitive,migration:$migration,deployment:$deployment,external_resource:$external_resource,money_movement:$money_movement}}')
decision=$(printf '%s' "$decision_input" | "$(dirname "$0")/decision.sh")

state_home=${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}
telemetry_target="${AGENT_TELEMETRY_PATH:-$state_home/tonys-agent-harness/telemetry/decisions.jsonl}"
telemetry_input=$(printf '%s' "$decision" | jq -c --arg route "$route" --argjson workflows "$workflows" '. + {route:$route, provider:(env.AGENT_PROVIDER // "unknown"), workflow_names:$workflows}')
if ! printf '%s' "$telemetry_input" | "$(dirname "$0")/telemetry.sh" "$telemetry_target" >/dev/null 2>&1; then
  decision=$(printf '%s' "$decision" | jq -c '.selected_action = "BLOCKED" | .next_action = "repair-telemetry" | .applicable_policy_rules += ["telemetry-write-failed"]')
fi

jq -cn \
  --arg complexity "$complexity" \
  --arg route "$route" \
  --argjson workflows "$workflows" \
  --argjson decision "$decision" \
  '{complexity: $complexity, selected_route: $route, workflows: $workflows, writes_allowed: false, human_approval_required: ($decision.selected_action == "HUMAN_APPROVAL"), decision: $decision, reason: "deterministic heuristic plus policy engine; confirm against repository evidence"}'
