#!/usr/bin/env bash
# Exercise installed provider validation surfaces without model calls or mutation.
set -euo pipefail
OUTPUT= REPO=. GENERATED=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT=$2; shift 2;; --repo) REPO=$2; shift 2;;
    --generated) GENERATED=$2; shift 2;;
    *) echo "native conformance: invalid argument" >&2; exit 2;;
  esac
done
[[ -n "$OUTPUT" && -d "$REPO" && ! -e "$OUTPUT" ]] || {
  echo "native conformance: new output path and repository required" >&2; exit 2;
}
provider_path=${AGENT_PROVIDER_PATH:-$PATH}
find_bin() { PATH="$provider_path" command -v "$1" 2>/dev/null || true; }
source_digest=unknown generated_digest=unknown activated_path=unavailable
if [[ -n "$GENERATED" ]]; then
  manifest="$GENERATED/manifest.json"
  [[ -f "$manifest" ]] || { echo "native conformance: generated manifest missing" >&2; exit 2; }
  source_digest=$(jq -er '.source_digest | select(type == "string" and length == 64)' "$manifest") || {
    echo "native conformance: source digest missing" >&2; exit 2;
  }
  generated_digest=$(shasum -a 256 "$manifest" | awk '{print $1}')
  activated_path=$(cd "$GENERATED" && pwd -P)
fi
results='[]'
append() {
  native_status=UNVERIFIED
  [[ "$3" == unknown ]] && native_status=UNAVAILABLE
  results=$(jq -c --arg provider "$1" --arg status "$2" --arg version "$3" --arg evidence "$4" --arg command_result "$5" \
    --arg native_status "$native_status" \
    '. + [{
      provider:$provider,
      status:$status,
      version:$version,
      evidence:$evidence,
      command_result:$command_result,
      dynamic_permissions:{
        provider_version:$version,
        adapter:{
          apply:"NOT_IMPLEMENTED",
          revoke:"NOT_IMPLEMENTED",
          observe:"NOT_IMPLEMENTED",
          evidence_kind:"adapter-inventory",
          evidence_ref:"runtime/governance/provider-native-conformance.sh"
        },
        native:{
          apply:$native_status,
          revoke:$native_status,
          observe:$native_status,
          evidence_kind:(if $native_status == "UNAVAILABLE" then "binary-discovery" else "not-probed" end),
          evidence_ref:(if $native_status == "UNAVAILABLE" then "provider binary not installed" else ("provider present at " + $version + "; no version-bound native grant probe executed") end)
        },
        enforcement:"UNENFORCEABLE",
        reason:"harness adapter is absent and native grant capability is not proven"
      }
    }]' <<<"$results")
}

codex=$(find_bin codex)
if [[ -z "$codex" ]]; then append codex UNAVAILABLE unknown "binary not installed" "not-run"
else
  version=$($codex --version 2>&1 | head -n 1)
  tmp=$(mktemp -d)
  set +e
  $codex sandbox -P agent-reviewer -C "$REPO" -- /usr/bin/true >/dev/null 2>&1
  startup_code=$?
  if [[ $startup_code -eq 0 ]]; then
    $codex sandbox -P agent-reviewer -C "$REPO" -- /usr/bin/touch "$tmp/denied" >/dev/null 2>&1
    code=$?
  else
    code=$startup_code
  fi
  set -e
  if [[ $startup_code -ne 0 ]]; then
    status=FAILED
    [[ $startup_code -eq 134 ]] && status=UNAVAILABLE
    append codex "$status" "$version" "sandbox startup unavailable: exit=$startup_code" "harmless=$startup_code"
  elif [[ $code -ne 0 && ! -e "$tmp/denied" && $code -ne 134 ]]; then
    append codex NATIVE_VERIFIED "$version" "native reviewer sandbox denied write" "harmless=0,write=$code"
  else
    append codex FAILED "$version" "sandbox denial invalid: exit=$code file=$(test -e "$tmp/denied" && echo present || echo absent)" "harmless=0,write=$code"
  fi
  rm -rf "$tmp"
fi

kiro=$(find_bin kiro-cli)
if [[ -z "$kiro" ]]; then append kiro UNAVAILABLE unknown "binary not installed" "not-run"
else
  version=$($kiro --version 2>&1 | head -n 1)
  reviewer="$HOME/.kiro/agents/independent-reviewer.json"
  if [[ -f "$reviewer" ]] && $kiro agent validate --path "$reviewer" >/dev/null 2>&1 &&
      jq -e '([.tools[]? | select(test("write|delete|append|replace"; "i"))] | length) == 0' "$reviewer" >/dev/null; then
    append kiro NATIVE_VERIFIED "$version" "native agent validation passed; reviewer has no write tool" "agent-validate=0"
  else append kiro FAILED "$version" "native reviewer config missing, invalid, or writable" "agent-validate=failed"
  fi
fi

for provider in claude gemini; do
  binary=$(find_bin "$provider")
  if [[ -z "$binary" ]]; then append "$provider" UNAVAILABLE unknown "binary not installed" "not-run"
  elif [[ -n "$GENERATED" ]] && [[ -f "$GENERATED/$provider/AGENTS.md" ]] && cmp -s "$REPO/AGENTS.md" "$GENERATED/$provider/AGENTS.md"; then
    append "$provider" STATICALLY_VERIFIED "$($binary --version 2>&1 | head -n 1)" "generated instruction is byte-identical; interactive native denial probe unavailable" "version=0"
  else
    append "$provider" FAILED "$($binary --version 2>&1 | head -n 1)" "generated instruction missing or drifted" "version=0"
  fi
done

status=$(jq -r 'if all(.[]; .status == "NATIVE_VERIFIED" or .status == "STATICALLY_VERIFIED" or .status == "UNAVAILABLE") then "COMPLETE_WITH_EXPLICIT_GAPS" else "FAILED" end' <<<"$results")
mkdir -p "$(dirname "$OUTPUT")"; umask 077
jq -n --arg status "$status" --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg source_digest "$source_digest" --arg generated_digest "$generated_digest" --arg activated_path "$activated_path" \
  --argjson providers "$results" \
  '{schema_version:2,status:$status,timestamp:$timestamp,source_digest:$source_digest,generated_digest:$generated_digest,activated_path:$activated_path,providers:$providers}' > "$OUTPUT"
[[ "$status" == COMPLETE_WITH_EXPLICIT_GAPS ]] || exit 2
