#!/usr/bin/env bash
# Trusted wrapper for execution-plan: mandatory work needs an external receipt.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT=$(cat)
if ! jq -e 'type == "object" and (.repo | type == "string" and length > 0) and
  (.request_digest | type == "string" and length > 0) and (.decision | type == "object")' <<<"$INPUT" >/dev/null; then
  jq -cn '{status:"BLOCKED",reason:"invalid-authorization-input"}'; exit 0
fi
mandatory=$(jq -r '(.phase == "5") or (.decision.human_approval_required == true) or
  ((.decision.applicable_policy_rules // []) | index("mandatory-risk-policy") != null)' <<<"$INPUT")
if [[ "$mandatory" == true ]]; then
  repo=$(jq -r .repo <<<"$INPUT"); receipt=$(jq -r '.approval_receipt // ""' <<<"$INPUT")
  digest=$(jq -r .request_digest <<<"$INPUT"); action=$(jq -r '.operation.action // ""' <<<"$INPUT")
  environment=$(jq -r '.operation.environment // ""' <<<"$INPUT")
  trusted_home=$(python3 - <<'PY'
import os, pwd
print(pwd.getpwuid(os.getuid()).pw_dir)
PY
  )
  trusted_key="$trusted_home/.config/agents/trust/approval-public.pem"
  if ! env -u AGENT_APPROVAL_PUBLIC_KEY AGENT_APPROVAL_PUBLIC_KEY="$trusted_key" \
      bash "$ROOT/governance/approval-gate.sh" --repo "$repo" --receipt "$receipt" \
      --digest "$digest" --action "$action" --environment "$environment" >/dev/null 2>&1; then
    jq -cn '{status:"BLOCKED",reason:"external-approval-required-or-invalid"}'; exit 0
  fi
  INPUT=$(jq -c '.human_approval={status:"approved",scope_digest:.request_digest,verification:"external-receipt"}' <<<"$INPUT")
  if [[ "$(jq -r .decision.selected_action <<<"$INPUT")" == HUMAN_APPROVAL ]]; then
    INPUT=$(printf '%s' "$INPUT" | "$(dirname "$0")/approval-transition.sh")
  fi
fi
printf '%s' "$INPUT" | "$(dirname "$0")/execution-plan.sh"
