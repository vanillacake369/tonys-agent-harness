#!/usr/bin/env bash
# Append a sanitized decision event. Never persist prompts or reasoning traces.

set -euo pipefail
umask 077

STATE_HOME=${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}
TARGET=${1:-${AGENT_TELEMETRY_PATH:-"$STATE_HOME/tonys-agent-harness/telemetry/decisions.jsonl"}}
INPUT=$(cat)

if ! printf '%s' "$INPUT" | jq -e '
  type == "object" and
  (.decision_id | type == "string" and length > 0) and
  (.selected_action | IN("AUTO_EXECUTE","RESEARCH_REQUIRED","SPEC_QUESTION","HUMAN_APPROVAL","BLOCKED")) and
  (.risk_level | type == "string") and
  (.uncertainty_level | type == "string")
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
  {
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
  }
' >> "$TARGET"
chmod 600 "$TARGET"
