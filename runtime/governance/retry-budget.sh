#!/usr/bin/env bash
# Persist a per-task retry budget. The state file survives session restarts.

set -euo pipefail

if [[ "${1:-}" == status && $# -eq 3 ]]; then
  STATE=$2; TASK=$3
  [[ -f "$STATE" ]] || { echo '{"status":"ACTIVE","attempts":0}'; exit 0; }
  result=$(jq -c --arg task "$TASK" '.tasks[$task] // {status:"ACTIVE",attempts:0}' "$STATE")
  printf '%s\n' "$result"
  [[ "$(jq -r .status <<<"$result")" != BLOCKED ]] || exit 2
  exit 0
fi
if [[ $# -lt 5 || "$1" != "record" ]]; then
  echo "usage: $0 status STATE TASK | record STATE TASK success|fail REASON [MAX_ATTEMPTS]" >&2
  exit 2
fi

STATE=$2
TASK=$3
OUTCOME=$4
REASON=$5
MAX=${6:-3}

if [[ "$OUTCOME" != "success" && "$OUTCOME" != "fail" ]] || [[ ! "$MAX" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid retry record" >&2
  exit 2
fi

mkdir -p "$(dirname "$STATE")"
if ! mkdir "$STATE.lock" 2>/dev/null; then
  echo "retry state locked; stop and inspect the owning process" >&2
  exit 2
fi
trap 'rmdir "$STATE.lock"' EXIT
if [[ ! -f "$STATE" ]]; then printf '%s\n' '{"tasks":{}}' > "$STATE"; fi

old=$(jq -c --arg task "$TASK" \
  '.tasks[$task] // {attempts: 0, status: "ACTIVE", history: []}' "$STATE")

result=$(jq -c \
  --arg task "$TASK" \
  --arg outcome "$OUTCOME" \
  --arg reason "$REASON" \
  --argjson max "$MAX" \
  --argjson old "$old" '
  ($old.attempts + (if $outcome == "fail" then 1 else 0 end)) as $attempts |
  (if $old.status == "BLOCKED" or $old.attempts >= $max then "BLOCKED"
   elif $outcome == "fail" and $attempts >= $max then "BLOCKED"
   elif $outcome == "success" then "DONE"
   else "ACTIVE" end) as $status |
  .tasks[$task] = ($old + {
    attempts: $attempts,
    status: $status,
    last_reason: $reason,
    history: ($old.history + [{outcome: $outcome, reason: $reason, attempt: $attempts}])
  })
  | .last_task = $task
  | .last_status = $status
' "$STATE")
printf '%s\n' "$result" > "$STATE"
printf '%s\n' "$result"

if [[ "$result" == *'"last_status":"BLOCKED"'* ]]; then exit 2; fi
