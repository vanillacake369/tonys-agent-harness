#!/usr/bin/env bash
# Produce local aggregate evidence; never changes policy thresholds.

set -euo pipefail

STATE_HOME=${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}
FILE=${1:-"$STATE_HOME/tonys-agent-harness/telemetry/decisions.jsonl"}
if [[ ! -f "$FILE" ]]; then
  jq -cn '{events:0,actions:{},routes:{},policy_learning:false}'
  exit 0
fi

jq -cs '
  map(select(type == "object")) as $events |
  {
    events: ($events | length),
    actions: (reduce $events[] as $event ({}; .[$event.selected_action // "unknown"] += 1)),
    routes: (reduce $events[] as $event ({}; .[$event.route // "unknown"] += 1)),
    policy_learning: false
  }
' "$FILE"
