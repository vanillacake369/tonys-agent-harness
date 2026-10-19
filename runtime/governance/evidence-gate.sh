#!/usr/bin/env bash
# Validate evidence before a code task can transition to DONE.

set -euo pipefail

FILE=${1:-}
if [[ -z "$FILE" || ! -f "$FILE" ]] || ! jq -e 'type == "object"' "$FILE" >/dev/null 2>&1; then
  echo "invalid evidence artifact" >&2
  exit 2
fi

status=$(jq -r '.status // ""' "$FILE")
if [[ "$status" != "DONE" && "$status" != "REVIEW_REQUIRED" ]]; then
  echo "evidence gate: status is $status; completion not claimed"
  exit 0
fi

if ! jq -e '
  (.requirements | type == "array" and length > 0) and
  (all(.requirements[]; (.result == "pass" and (.id | type == "string")))) and
  (.commands | type == "array" and length > 0) and
  (all(.commands[]; (.exit_code == 0 and (.command | type == "string" and length > 0) and (.duration_ms | type == "number" and . >= 0) and (.result | type == "string" and length > 0)))) and
  (.changed_files | type == "array" and length > 0) and
  (.diff_summary | type == "string" and length > 0) and
  (.unresolved_errors | type == "array" and length == 0) and
  (.commit | type == "string" and length > 0)
' "$FILE" >/dev/null; then
  echo "evidence gate failed: missing test evidence, failed command, or unresolved error" >&2
  exit 2
fi

echo "evidence gate passed: commands, exit codes, timing, files, diff, requirements, and commit are recorded"
