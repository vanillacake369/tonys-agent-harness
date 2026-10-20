#!/usr/bin/env bash
# Produce local aggregate evidence; never changes policy thresholds.

set -euo pipefail

STATE_HOME=${XDG_STATE_HOME:-${HOME:?HOME is required}/.local/state}
FILE=${1:-"$STATE_HOME/tonys-agent-harness/telemetry/decisions.jsonl"}
if [[ ! -f "$FILE" ]]; then
  jq -cn '{events:0,actions:{},routes:{},latency_ms:{total:0,average:0},retries:0,human_interventions:0,review_findings:0,evidence_coverage:0,policy_learning:false}'
  exit 0
fi

jq -cs '
  map(select(type == "object")) as $events |
  {
    events: ($events | length),
    actions: (reduce $events[] as $event ({}; .[$event.selected_action // "unknown"] += 1)),
    routes: (reduce $events[] as $event ({}; .[$event.route // "unknown"] += 1)),
    latency_ms: {
      total: ([$events[].duration_ms // 0] | add // 0),
      average: (if ($events | length) == 0 then 0 else (([$events[].duration_ms // 0] | add // 0) / ($events | length)) end)
    },
    retries: ([$events[].retry_count // 0] | add // 0),
    human_interventions: ([$events[] | select(.human_intervention == true)] | length),
    review_findings: ([$events[].review_findings // 0] | add // 0),
    evidence_coverage: (([$events[].requirements_verified // 0] | add // 0) as $verified |
      ([$events[].requirements_total // 0] | add // 0) as $total |
      if $total == 0 then 0 else $verified / $total end),
    policy_learning: false
  }
' "$FILE"
