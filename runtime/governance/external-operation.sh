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

echo "usage: $0 reserve REGISTRY OPERATION_ID PROVIDER TARGET FINGERPRINT | mark REGISTRY OPERATION_ID STATUS EVIDENCE" >&2
exit 2
