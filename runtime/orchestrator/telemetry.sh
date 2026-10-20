#!/usr/bin/env bash
# Append a sanitized decision event. Never persist prompts or reasoning traces.

set -euo pipefail
umask 077

STATE_HOME=${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}
TARGET=${1:-${AGENT_TELEMETRY_PATH:-"$STATE_HOME/tonys-agent-harness/telemetry/decisions.jsonl"}}
INPUT=$(cat)

if ! printf '%s' "$INPUT" | jq -e '
  type == "object" and
  if (.event_type // "decision") == "decision" then
    (.decision_id | type == "string" and length > 0) and
    (.selected_action | IN("AUTO_EXECUTE","RESEARCH_REQUIRED","SPEC_QUESTION","HUMAN_APPROVAL","BLOCKED")) and
    (.risk_level | type == "string") and
    (.uncertainty_level | type == "string")
  else
    (.event_type | IN("route","approval","tool-outcome","retry","review","completion","external-operation")) and
    (.event_id | type == "string" and length > 0) and
    (.task_id | type == "string" and length > 0) and
    ((.duration_ms // 0) | type == "number" and . >= 0) and
    ((.retry_count // 0) | type == "number" and . >= 0) and
    ((.requirements_total // 0) | type == "number" and . >= 0) and
    ((.requirements_verified // 0) | type == "number" and . >= 0)
  end
' >/dev/null 2>&1; then
  echo "invalid decision telemetry" >&2
  exit 2
fi

TARGET_DIR=$(dirname "$TARGET")
if [[ ! -d "$TARGET_DIR" ]]; then
  mkdir -p "$TARGET_DIR"
  chmod 700 "$TARGET_DIR"
fi

printf '%s\n' "$INPUT" | jq -c --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
  if (.event_type // "decision") == "decision" then {
    event_version: 1,
    event_type: "decision",
    timestamp: $timestamp,
    decision_id,
    selected_action,
    risk_level,
    uncertainty_level,
    route: (.route // "unknown"),
    provider: (.provider // "unknown"),
    workflow_names: (.workflow_names // []),
    human_approval_required: (.human_approval_required // false),
    evidence_count: ((.evidence_references // []) | length),
    result: (.result // "selected")
  } else {
    event_version: 1,
    event_type,
    timestamp: $timestamp,
    event_id,
    task_id,
    route: (.route // "unknown"),
    provider: (.provider // "unknown"),
    duration_ms: (.duration_ms // 0),
    retry_count: (.retry_count // 0),
    human_intervention: (.human_intervention // false),
    review_findings: (.review_findings // 0),
    requirements_total: (.requirements_total // 0),
    requirements_verified: (.requirements_verified // 0),
    result: (.result // "unknown")
  } end
' >> "$TARGET"
chmod 600 "$TARGET"
