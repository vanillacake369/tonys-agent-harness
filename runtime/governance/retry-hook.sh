#!/usr/bin/env bash
# Provider adapter over the shared persistent retry budget.
set -euo pipefail
MODE=${1:-}
MAX=${2:-3}
[[ "$MAX" =~ ^[1-3]$ ]] || { echo "retry hook: max must be 1..3" >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
jq -e 'type == "object" and (.tool_name | type == "string" and length > 0)' <<<"$INPUT" >/dev/null 2>&1 || {
  echo "retry hook: invalid payload" >&2; exit 2;
}
task=${AGENT_TASK_ID:-}
if [[ -z "$task" ]]; then
  repo=$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
  repo_key=$(printf '%s' "$repo" | shasum -a 256 | awk '{print $1}')
  task_state_dir=${AGENT_TASK_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-policy/tasks}
  task_state="$task_state_dir/$repo_key.json"
  task=$(jq -r '.task_id // empty' "$task_state" 2>/dev/null || true)
  [[ -n "$task" ]] || { echo "retry hook: task identity unavailable; SessionStart required" >&2; exit 2; }
fi
state=${AGENT_RETRY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-policy/retry.json}
if [[ "$MODE" == pre ]]; then
  "$ROOT/retry-budget.sh" status "$state" "$task"
  exit $?
fi
[[ "$MODE" == post || "$MODE" == failure ]] || { echo "retry hook: expected pre, post, or failure" >&2; exit 2; }
if [[ "$MODE" == failure ]]; then
  exit_code=1
  output=$(jq -r '.error // .tool_response.error // .tool_output // "provider tool failure"' <<<"$INPUT")
else
  exit_code=$(jq -r '.tool_exit_code // .tool_response.exit_code // .exit_code // 0' <<<"$INPUT")
  output=$(jq -r '.tool_output // .tool_response.output // .output // ""' <<<"$INPUT")
fi
if [[ "$exit_code" != 0 ]] || grep -qiE '(^|\n)(error:|FAIL\b|fatal:|panic:|exception:)' <<<"$output"; then
  reason=$(sed -n '1p' <<<"$output" | cut -c1-160); [[ -n "$reason" ]] || reason="exit-$exit_code"
  "$ROOT/retry-budget.sh" record "$state" "$task" fail "$reason" "$MAX"
else
  "$ROOT/retry-budget.sh" record "$state" "$task" success "verified-success" "$MAX"
fi
