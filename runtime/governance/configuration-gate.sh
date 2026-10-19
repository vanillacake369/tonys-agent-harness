#!/usr/bin/env bash
# Validate layered policy data and reject project-level security relaxation.

set -euo pipefail

FILE=${1:-}
[[ -n "$FILE" && -f "$FILE" ]] || { echo "usage: $0 POLICY_JSON" >&2; exit 2; }
required='["global-policy","project-policy","agent-role-permissions","skill-workflow-registry","mcp-registry","runtime-sandbox-approval","verification-evidence-policy"]'

if ! jq -e --argjson required "$required" '
  . as $root |
  ($root.layers | type == "object") and
  ($required | all(.[]; $root.layers[.] != null)) and
  ($required | map($root.layers[.].priority) | length == (unique | length)) and
  (.layers["global-policy"].priority == 100) and
  (.layers["project-policy"].priority < .layers["global-policy"].priority) and
  ($required | map($root.layers[.].priority)) == [100,90,80,70,60,50,40] and
  ($required | all(.[]; $root.layers[.].can_weaken == false))
' "$FILE" >/dev/null; then
  echo "configuration gate failed: invalid layers, precedence, or weakening flag" >&2
  exit 2
fi

if jq -e '
  ([.layers["global-policy"].deny[]?] | unique) as $denied |
  ([.layers["project-policy"].allow[]?] | any(. as $candidate | $denied | index($candidate) != null))
' "$FILE" >/dev/null; then
  echo "configuration gate failed: project policy weakens global deny" >&2
  exit 2
fi

echo "configuration gate passed: precedence and non-weakening policy are valid"
