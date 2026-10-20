#!/usr/bin/env bash
# Require observable Red-before-Green evidence or a reviewed exemption.
set -euo pipefail
REQUIREMENTS_JSON= GREEN_COMMIT= BASELINE=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --requirements-json) REQUIREMENTS_JSON=$2; shift 2;;
    --green-commit) GREEN_COMMIT=$2; shift 2;;
    --baseline) BASELINE=$2; shift 2;;
    *) echo "TDD evidence blocked: invalid argument" >&2; exit 2;;
  esac
done
input=$(cat)
if jq -e --argjson requirements "${REQUIREMENTS_JSON:-[]}" --arg green "$GREEN_COMMIT" --arg baseline "$BASELINE" '
  . as $e | type == "object" and (.requirement_id | type == "string" and length > 0) and
  (($requirements | length) == 0 or ($requirements | index($e.requirement_id))) and
  (.red.command | type == "string" and length > 0) and (.red.result | type == "string" and length > 0) and
  (.red.exit_code | type == "number" and . != 0) and
  (($baseline == "") or .red.executed_commit == $baseline) and
  (.green.command | type == "string" and length > 0) and (.green.result | type == "string" and length > 0) and
  .green.exit_code == 0 and (.red.sequence | type == "number") and
  (.green.sequence | type == "number") and .red.sequence < .green.sequence and
  (($green == "") or .green.executed_commit == $green)
' <<<"$input" >/dev/null 2>&1; then
  jq -c '{status:"VERIFIED",requirement_id,red,green,exemption:null}' <<<"$input"
  exit 0
fi
if jq -e --argjson requirements "${REQUIREMENTS_JSON:-[]}" --arg green "$GREEN_COMMIT" '
  . as $e | type == "object" and (.requirement_id | type == "string" and length > 0) and
  (($requirements | length) == 0 or ($requirements | index($e.requirement_id))) and
  (.exemption.reason | type == "string" and length > 0) and
  .exemption.reviewer_role == "independent-reviewer" and
  (.exemption.evidence | type == "string" and length > 0) and
  (($green == "") or .exemption.reviewed_commit == $green)
' <<<"$input" >/dev/null 2>&1; then
  jq -c '{status:"EXEMPTION_VERIFIED",requirement_id,exemption}' <<<"$input"
  exit 0
fi
echo "TDD evidence blocked: failing Red must precede passing Green or have independent exemption" >&2
exit 2
