#!/usr/bin/env bash
# File-backed idempotency registry; it never calls an external provider.

set -euo pipefail

COMMAND=${1:-}
REGISTRY=${2:-}
[[ -n "$REGISTRY" ]] || { echo "registry path required" >&2; exit 2; }
mkdir -p "$(dirname "$REGISTRY")"
if ! mkdir "$REGISTRY.lock" 2>/dev/null; then
  echo "operation registry locked; inspect existing owner before retry" >&2; exit 2
fi
trap 'rmdir "$REGISTRY.lock"' EXIT
if [[ "$COMMAND" == "plan" && $# -eq 2 ]]; then
  INPUT=$(cat)
  if ! jq -e '
    type == "object" and
    all(.operation_id,.target_provider,.environment,.target_resource,.repository_root,.action,.request_fingerprint,
      .idempotency_key,.approval_digest,.credential_profile,.rollback,.observation_window,
      .dry_run_evidence; type == "string" and length > 0)
  ' <<<"$INPUT" >/dev/null 2>&1; then
    echo "external operation blocked: complete scoped contract required" >&2; exit 2
  fi
  [[ -f "$REGISTRY" ]] || printf '%s\n' '{"operations":{}}' > "$REGISTRY"
  OP=$(jq -r .operation_id <<<"$INPUT")
  if jq -e --arg op "$OP" '.operations[$op] != null' "$REGISTRY" >/dev/null; then
    echo "external operation blocked: operation already exists" >&2; exit 2
  fi
  if jq -e --arg fp "$(jq -r .request_fingerprint <<<"$INPUT")" \
      'any(.operations[]; .request_fingerprint == $fp)' "$REGISTRY" >/dev/null; then
    echo "external operation blocked: request fingerprint already exists" >&2; exit 2
  fi
  jq --arg op "$OP" --argjson contract "$INPUT" '
    .operations[$op] = ($contract + {
      execution_status:"PLANNED", external_resource_id:null,
      verification_evidence:["contract-validated"]
    })
  ' "$REGISTRY" > "$REGISTRY.tmp"
  mv "$REGISTRY.tmp" "$REGISTRY"
  jq -c --arg op "$OP" '.operations[$op]' "$REGISTRY"
  exit 0
fi

if [[ "$COMMAND" == "transition" && ($# -eq 5 || $# -eq 6) ]]; then
  OP=$3; STATUS=$4; EVIDENCE=$5; EXTERNAL_ID=${6:-}
  [[ -f "$REGISTRY" && -n "$EVIDENCE" ]] || { echo "external transition blocked: operation and evidence required" >&2; exit 2; }
  CURRENT=$(jq -er --arg op "$OP" '.operations[$op].execution_status' "$REGISTRY") || {
    echo "external transition blocked: unknown operation" >&2; exit 2;
  }
  case "$CURRENT:$STATUS" in
    PLANNED:APPROVAL_REQUIRED|APPROVAL_REQUIRED:APPROVED|APPROVED:EXECUTING|EXECUTING:SUCCEEDED|EXECUTING:FAILED|EXECUTING:UNKNOWN|SUCCEEDED:VERIFIED|SUCCEEDED:ROLLED_BACK|UNKNOWN:VERIFIED|UNKNOWN:FAILED|FAILED:ROLLED_BACK|*:BLOCKED) ;;
    *) echo "external transition blocked: invalid transition $CURRENT -> $STATUS" >&2; exit 2;;
  esac
  if [[ "$CURRENT:$STATUS" == APPROVAL_REQUIRED:APPROVED ]]; then
    receipt=${AGENT_APPROVAL_RECEIPT:-}
    [[ -n "$receipt" ]] || { echo "external transition blocked: signed approval receipt required" >&2; exit 2; }
    repo=$(jq -r --arg op "$OP" '.operations[$op].repository_root' "$REGISTRY")
    digest=$(jq -r --arg op "$OP" '.operations[$op].approval_digest' "$REGISTRY")
    action=$(jq -r --arg op "$OP" '.operations[$op].action' "$REGISTRY")
    environment=$(jq -r --arg op "$OP" '.operations[$op].environment' "$REGISTRY")
    trusted_home=$(python3 - <<'PY'
import os, pwd
print(pwd.getpwuid(os.getuid()).pw_dir)
PY
    )
    trusted_key="$trusted_home/.config/agents/trust/approval-public.pem"
    env -u AGENT_APPROVAL_PUBLIC_KEY AGENT_APPROVAL_PUBLIC_KEY="$trusted_key" \
      "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/approval-gate.sh" \
      --repo "$repo" --receipt "$receipt" --digest "$digest" \
      --action "$action" --environment "$environment" >/dev/null
  fi
  if [[ "$CURRENT" == UNKNOWN && "$STATUS" == VERIFIED && -z "$EXTERNAL_ID" ]]; then
    echo "external transition blocked: provider lookup resource id required" >&2; exit 2
  fi
  jq --arg op "$OP" --arg status "$STATUS" --arg evidence "$EVIDENCE" --arg external "$EXTERNAL_ID" '
    .operations[$op].execution_status=$status |
    .operations[$op].verification_evidence += [$evidence] |
    if $external != "" then .operations[$op].external_resource_id=$external else . end
  ' "$REGISTRY" > "$REGISTRY.tmp"
  mv "$REGISTRY.tmp" "$REGISTRY"
  jq -c --arg op "$OP" '.operations[$op]' "$REGISTRY"
  exit 0
fi

if [[ "$COMMAND" == "reserve" && $# -eq 6 ]]; then
  OP=$3; PROVIDER=$4; TARGET=$5; FINGERPRINT=$6
  mkdir -p "$(dirname "$REGISTRY")"
  [[ -f "$REGISTRY" ]] || printf '%s\n' '{"operations":{}}' > "$REGISTRY"
  existing=$(jq -c --arg op "$OP" '.operations[$op] // empty' "$REGISTRY")
  if jq -e --arg provider "$PROVIDER" --arg target "$TARGET" --arg fp "$FINGERPRINT" \
    'any(.operations[]; .target_provider == $provider and .target_resource == $target and .request_fingerprint == $fp)' "$REGISTRY" >/dev/null; then
    echo "duplicate request fingerprint; reconcile the existing operation" >&2
    [[ -n "$existing" ]] || exit 2
  fi
  if [[ -n "$existing" ]]; then
    old_fp=$(printf '%s' "$existing" | jq -r '.request_fingerprint')
    [[ "$old_fp" == "$FINGERPRINT" ]] || { echo "fingerprint mismatch" >&2; exit 2; }
    state=$(printf '%s' "$existing" | jq -r '.execution_status')
    echo "operation $OP already exists with status $state" >&2
    exit 2
  fi
  jq --arg op "$OP" --arg provider "$PROVIDER" --arg target "$TARGET" --arg fp "$FINGERPRINT" \
    '.operations[$op] = {operation_id:$op,target_provider:$provider,target_resource:$target,request_fingerprint:$fp,idempotency_key:$op,external_resource_id:null,execution_status:"PENDING",verification_evidence:[]}' \
    "$REGISTRY" > "$REGISTRY.tmp"
  mv "$REGISTRY.tmp" "$REGISTRY"
  jq -c --arg op "$OP" '.operations[$op]' "$REGISTRY"
  exit 0
fi

if [[ "$COMMAND" == "mark" && $# -eq 5 ]]; then
  OP=$3; STATUS=$4; EVIDENCE=$5
  [[ "$STATUS" =~ ^(UNKNOWN|EXECUTED|VERIFIED|FAILED)$ ]] || { echo "invalid external status" >&2; exit 2; }
  [[ -f "$REGISTRY" ]] || { echo "unknown operation" >&2; exit 2; }
  jq -e --arg op "$OP" '.operations[$op] != null' "$REGISTRY" >/dev/null || { echo "unknown operation" >&2; exit 2; }
  jq --arg op "$OP" --arg status "$STATUS" --arg evidence "$EVIDENCE" \
    '.operations[$op].execution_status=$status | .operations[$op].verification_evidence += [$evidence]' \
    "$REGISTRY" > "$REGISTRY.tmp"
  mv "$REGISTRY.tmp" "$REGISTRY"
  jq -c --arg op "$OP" '.operations[$op]' "$REGISTRY"
  exit 0
fi

echo "usage: $0 plan REGISTRY < contract.json | transition REGISTRY OPERATION_ID STATUS EVIDENCE [EXTERNAL_ID] | reserve REGISTRY OPERATION_ID PROVIDER TARGET FINGERPRINT | mark REGISTRY OPERATION_ID STATUS EVIDENCE" >&2
exit 2
