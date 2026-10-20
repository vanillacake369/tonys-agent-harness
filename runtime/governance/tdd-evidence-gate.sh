#!/usr/bin/env bash
# Require observable Red-before-Green evidence or a reviewed exemption.
set -euo pipefail
input=$(cat)
if jq -e '
  type == "object" and (.requirement_id | type == "string" and length > 0) and
  (.red.command | type == "string" and length > 0) and (.red.result | type == "string" and length > 0) and
  (.red.exit_code | type == "number" and . != 0) and
  (.green.command | type == "string" and length > 0) and (.green.result | type == "string" and length > 0) and
  .green.exit_code == 0 and (.red.sequence | type == "number") and
  (.green.sequence | type == "number") and .red.sequence < .green.sequence
' <<<"$input" >/dev/null 2>&1; then
  jq -c '{status:"VERIFIED",requirement_id,red,green,exemption:null}' <<<"$input"
  exit 0
fi
if jq -e '
  type == "object" and (.requirement_id | type == "string" and length > 0) and
  (.exemption.reason | type == "string" and length > 0) and
  .exemption.reviewer_role == "independent-reviewer" and
  (.exemption.evidence | type == "string" and length > 0)
' <<<"$input" >/dev/null 2>&1; then
  jq -c '{status:"EXEMPTION_VERIFIED",requirement_id,exemption}' <<<"$input"
  exit 0
fi
echo "TDD evidence blocked: failing Red must precede passing Green or have independent exemption" >&2
exit 2
