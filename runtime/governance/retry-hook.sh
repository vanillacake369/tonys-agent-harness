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
  hook_cwd=$(jq -r '.cwd // empty' <<<"$INPUT")
  [[ -n "$hook_cwd" ]] || hook_cwd=$PWD
  repo=$(git -C "$hook_cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$hook_cwd")
  repo_key=$(printf '%s' "$repo" | shasum -a 256 | awk '{print $1}')
  task_state_dir=${AGENT_TASK_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-policy/tasks}
  task_state="$task_state_dir/$repo_key.json"
  task=$(jq -r '.task_id // empty' "$task_state" 2>/dev/null || true)
  [[ -n "$task" ]] || { echo "retry hook: task identity unavailable; SessionStart required" >&2; exit 2; }
fi
state=${AGENT_RETRY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-policy/retry.json}
if [[ "$MODE" == pre ]]; then
  if budget_output=$("$ROOT/retry-budget.sh" status "$state" "$task"); then
    exit 0
  else
    code=$?
    printf 'retry hook blocked: %s\n' "$budget_output" >&2
    exit "$code"
  fi
fi
[[ "$MODE" == post || "$MODE" == failure ]] || { echo "retry hook: expected pre, post, or failure" >&2; exit 2; }
if [[ "$MODE" == failure ]]; then
  exit_code=1
  output=$(jq -r '
    if (.error? | type) == "string" then .error
    elif (.tool_response? | type) == "object" and (.tool_response.error? | type) == "string" then .tool_response.error
    elif (.tool_output? | type) == "string" then .tool_output
    else "provider tool failure"
    end
  ' <<<"$INPUT")
else
  normalized=$(jq -c '
    def explicit_exit_codes:
      [
        .tool_exit_code?,
        .exit_code?,
        (if (.tool_response? | type) == "object" then .tool_response.exit_code? else null end)
      ]
      | map(select(
          type == "number"
          or (type == "string" and test("^-?[0-9]+$"))
        ))
      | map(tonumber);
    def explicit_error:
      (.isError? == true)
      or (
        (.tool_response? | type) == "object"
        and (.tool_response.isError? == true)
      );
    def error_text:
      if (.error? | type) == "string" then .error
      elif (.tool_response? | type) == "object" and (.tool_response.error? | type) == "string" then .tool_response.error
      else ""
      end;
    def stderr_text:
      if (.tool_response? | type) == "object" and (.tool_response.stderr? | type) == "string" then .tool_response.stderr
      else ""
      end;
    def response_output:
      if (.tool_output? | type) == "string" then .tool_output
      elif (.tool_response? | type) == "object" and (.tool_response.output? | type) == "string" then .tool_response.output
      elif (.tool_response? | type) == "object"
          and (((.tool_response.stdout? | type) == "string") or ((.tool_response.stderr? | type) == "string")) then
        [
          (if (.tool_response.stdout? | type) == "string" then .tool_response.stdout else empty end),
          (if (.tool_response.stderr? | type) == "string" then .tool_response.stderr else empty end)
        ] | join("\n")
      elif (.output? | type) == "string" then .output
      else ""
      end;
    explicit_exit_codes as $exit_codes
    | explicit_error as $is_error
    | error_text as $error
    | stderr_text as $stderr
    | response_output as $output
    | if $is_error or any($exit_codes[]; . != 0) then
        {
          status:"failure",
          exit_code:([$exit_codes[] | select(. != 0)] | first // 1),
          output:(if $error != "" then $error elif $stderr != "" then $stderr else $output end)
        }
      elif ($exit_codes | length) == 0 then
        {status:"unknown", exit_code:null, output:""}
      else
        {status:"success", exit_code:0, output:$output}
      end
  ' <<<"$INPUT")
  status=$(jq -r '.status' <<<"$normalized")
  [[ "$status" != unknown ]] || exit 0
  exit_code=$(jq -r '.exit_code' <<<"$normalized")
  output=$(jq -r '.output' <<<"$normalized")
fi
if [[ "${status:-failure}" == failure || "$exit_code" != 0 ]] || grep -qiE '^(error:|FAIL([^[:alnum:]_]|$)|fatal:|panic:|exception:)' <<<"$output"; then
  reason=$(sed -n '1p' <<<"$output" | cut -c1-160); [[ -n "$reason" ]] || reason="exit-$exit_code"
  outcome=fail
else
  outcome=success
  reason=verified-success
fi
if budget_output=$("$ROOT/retry-budget.sh" record "$state" "$task" "$outcome" "$reason" "$MAX"); then
  exit 0
else
  code=$?
  printf 'retry hook blocked: %s\n' "$budget_output" >&2
  exit "$code"
fi
