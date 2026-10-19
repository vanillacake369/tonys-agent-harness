#!/usr/bin/env bash
# Claude pre-tool boundary. Only documented read-oriented Context7 operations
# are supported in this MVP; browser/external mutations have no execution adapter.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=${1:-pre}
INPUT=$(cat)
if ! jq -e 'type == "object" and (.tool_name | type == "string")' <<<"$INPUT" >/dev/null 2>&1; then
  echo "MCP blocked: invalid hook input" >&2; exit 2
fi
tool=$(jq -r .tool_name <<<"$INPUT")
server=${tool#mcp__}; server=${server%%__*}
method=${tool#*__}; method=${method#*__}
decision_id=${AGENT_DECISION_ID:-$(jq -r 'if (.session_id | type) == "string" and (.session_id | length) > 0 then "session:" + .session_id else "" end' <<<"$INPUT")}
operation_id=${AGENT_OPERATION_ID:-$(jq -r '.operation_id // .tool_use_id // empty' <<<"$INPUT")}
request_fingerprint=${AGENT_REQUEST_FINGERPRINT:-}
if [[ -z "$request_fingerprint" ]]; then
  request_fingerprint=$(jq -S -c '{tool_name,tool_input:(.tool_input // {})}' <<<"$INPUT" | shasum -a 256 | awk '{print $1}')
fi
[[ -n "$decision_id" && -n "$operation_id" && -n "$request_fingerprint" ]] || {
  echo "MCP blocked: decision, operation, and request fingerprint required" >&2; exit 2;
}
if [[ "$MODE" == post ]]; then
  state_home=${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}
  target=${AGENT_MCP_AUDIT_PATH:-$state_home/tonys-agent-harness/telemetry/mcp.jsonl}
  mkdir -p "$(dirname "$target")"; umask 077
  status=VERIFIED
  error=$(jq -r '.tool_response.error // .tool_output.error // .error // ""' <<<"$INPUT")
  is_error=$(jq -r '.tool_response.isError // .tool_output.isError // false' <<<"$INPUT")
  if [[ "$is_error" == true ]]; then status=FAILED; fi
  if grep -qiE 'timeout|timed out|unknown' <<<"$error"; then status=UNKNOWN; fi
  jq -cn --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg server "$server" \
    --arg method "$method" --arg role "${AGENT_ROLE:-unknown}" --arg skill "${AGENT_SKILL:-unknown}" \
    --arg status "$status" --arg evidence "${error:-provider-response}" --arg decision_id "$decision_id" \
    --arg operation_id "$operation_id" --arg request_fingerprint "$request_fingerprint" \
    '{event_version:1,event_type:"mcp-operation",timestamp:$timestamp,decision_id:$decision_id,operation_id:$operation_id,request_fingerprint:$request_fingerprint,server:$server,method:$method,role:$role,skill:$skill,risk:"read",status:$status,evidence:$evidence}' >> "$target"
  chmod 600 "$target"
  exit 0
fi
[[ "$MODE" == pre ]] || { echo "MCP blocked: expected pre or post" >&2; exit 2; }
case "$tool" in
  mcp__context7__resolve-library-id|mcp__context7__query-docs) ;;
  *) echo "MCP blocked: operation has no approved execution adapter" >&2; exit 2;;
esac
case "${AGENT_ROLE:-}" in researcher|architect) ;; *) echo "MCP blocked: explicit read role required" >&2; exit 2;; esac
policy="${AGENT_PROJECT_POLICY:-$PWD/agent-harness-policy.json}"
bash "$ROOT/mcp-allowlist-gate.sh" "$policy" context7 "${AGENT_ROLE:-}" "${AGENT_SKILL:-}"
