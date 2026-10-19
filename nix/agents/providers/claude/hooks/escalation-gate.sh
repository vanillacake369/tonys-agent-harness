#!/usr/bin/env bash
# Persistent retry gate. It never stashes, resets, or mutates user changes.
set -euo pipefail
INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)
TOOL_INPUT=$(jq -r '.tool_input // empty' <<<"$INPUT" 2>/dev/null)
TOOL_OUTPUT=$(jq -r '.tool_output // .tool_response.output // .output // empty' <<<"$INPUT" 2>/dev/null)
case "$TOOL_NAME" in Bash|Write|Edit|NotebookEdit) ;; *) exit 0;; esac
if [[ "$TOOL_NAME" == Bash ]]; then
  first=$(jq -r '.command // ""' <<<"$TOOL_INPUT" 2>/dev/null | awk '{print $1}')
  case "$first" in grep|rg|ls|cat|head|tail|find|echo|pwd|which|type|file|wc|sort|uniq|diff|tree|stat|du|df|date|env|printenv|uname) exit 0;; esac
fi
STATE_DIR="${CLAUDE_ESCALATION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-policy/escalation}"
mkdir -p "$STATE_DIR"
SESSION_ID="${AGENT_TASK_ID:-${CLAUDE_TASK_ID:-default}}"
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9._-' | cut -c1-80); [[ -n "$SESSION_ID" ]] || SESSION_ID=default
STATE_FILE="$STATE_DIR/state-${SESSION_ID}.json"
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"
TASK_KEY=$(printf '%s' "$TOOL_INPUT" | head -c 80 | tr -d '\n' | sed 's/[^a-zA-Z0-9_-]/_/g'); [[ -n "$TASK_KEY" ]] || TASK_KEY=unknown
exit_code=$(jq -r '.tool_exit_code // .tool_response.exit_code // .exit_code // "0"' <<<"$INPUT" 2>/dev/null)
failed=false
[[ "$exit_code" != 0 && "$exit_code" != null && -n "$exit_code" ]] && failed=true
echo "$TOOL_OUTPUT" | grep -qiE '(^error:|^FAIL\b|^fatal:|panic:|exception:)' 2>/dev/null && failed=true || true
current=$(jq -r --arg k "$TASK_KEY" '.[$k] // 0' "$STATE_FILE" 2>/dev/null || echo 0)
if [[ "$failed" == true ]]; then
  next=$((current + 1))
  jq --arg k "$TASK_KEY" --argjson v "$next" '.[$k]=$v' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  if (( next >= 3 )); then
    echo "[ESCALATION] Task failed $next times and is BLOCKED; no automatic rollback was performed." >&2; exit 2
  fi
  echo "[RETRY $next/3] Use a materially different approach."; exit 1
fi
if (( current >= 3 )); then
  echo "[ESCALATION] Task remains BLOCKED until explicitly reset by a human." >&2; exit 2
fi
jq --arg k "$TASK_KEY" '.[$k]=0' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
exit 0
