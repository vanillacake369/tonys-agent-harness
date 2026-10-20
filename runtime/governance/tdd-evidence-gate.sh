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
  (if type == "array" then . else [.] end) as $entries |
  ($entries | map(.requirement_id) | sort | unique) as $covered |
  (($requirements | length) == 0 or (($requirements | sort | unique) == $covered)) and
  ($entries | length > 0) and all($entries[];
    (.requirement_id | type == "string" and length > 0) and
    (if .exemption == null then
      (.red.command | type == "string" and length > 0) and
      (.red.result | type == "string" and length > 0) and
      (.red.exit_code | type == "number" and . != 0) and
      (($baseline == "") or .red.executed_commit == $baseline) and
      (.green.command | type == "string" and length > 0) and
      (.green.result | type == "string" and length > 0) and
      .green.exit_code == 0 and (.red.sequence | type == "number") and
      (.green.sequence | type == "number") and .red.sequence < .green.sequence and
      (($green == "") or .green.executed_commit == $green)
    else
      (.exemption.reason | type == "string" and length > 0) and
      .exemption.reviewer_role == "independent-reviewer" and
      (.exemption.evidence | type == "string" and length > 0) and
      (($green == "") or .exemption.reviewed_commit == $green)
    end))
' <<<"$input" >/dev/null 2>&1; then
  jq -c 'if type == "array" then {status:"VERIFIED",evidence:.} else {status:"VERIFIED",evidence:[.]} end' <<<"$input"
  exit 0
fi
echo "TDD evidence blocked: failing Red must precede passing Green or have independent exemption" >&2
exit 2
