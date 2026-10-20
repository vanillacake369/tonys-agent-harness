#!/usr/bin/env bash
# Validate independent, privacy-safe skill before/after evidence.
set -euo pipefail

input=$(cat)
if ! jq -e '
  type == "object"
  and (.skill | type == "string" and startswith("skl-"))
  and .evaluator_role == "independent-reviewer"
  and .privacy_safe == true
  and .policy_relaxation == false
  and (.before | type == "object")
  and (.after | type == "object")
  and (.before.fixture | type == "string" and length > 0)
  and .before.fixture == .after.fixture
  and (.before.completion_rate | type == "number")
  and (.after.completion_rate | type == "number")
  and (.before.human_interventions | type == "number")
  and (.after.human_interventions | type == "number")
  and (.findings | type == "array")
' <<<"$input" >/dev/null 2>&1; then
  echo "skill evaluation blocked: independent privacy-safe comparable evidence required" >&2
  exit 2
fi

jq -c '{status:"VERIFIED",skill,evaluator_role,before,after,findings,policy_relaxation:false}' <<<"$input"
