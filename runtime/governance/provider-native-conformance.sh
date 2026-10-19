#!/usr/bin/env bash
# Exercise installed provider validation surfaces without model calls or mutation.
set -euo pipefail
OUTPUT= REPO=.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT=$2; shift 2;; --repo) REPO=$2; shift 2;;
    *) echo "native conformance: invalid argument" >&2; exit 2;;
  esac
done
[[ -n "$OUTPUT" && -d "$REPO" && ! -e "$OUTPUT" ]] || {
  echo "native conformance: new output path and repository required" >&2; exit 2;
}
provider_path=${AGENT_PROVIDER_PATH:-$PATH}
find_bin() { PATH="$provider_path" command -v "$1" 2>/dev/null || true; }
results='[]'
append() {
  results=$(jq -c --arg provider "$1" --arg status "$2" --arg version "$3" --arg evidence "$4" \
    '. + [{provider:$provider,status:$status,version:$version,evidence:$evidence}]' <<<"$results")
}

codex=$(find_bin codex)
if [[ -z "$codex" ]]; then append codex UNAVAILABLE unknown "binary not installed"
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
    append codex FAIL "$version" "sandbox startup failed: exit=$startup_code"
  elif [[ $code -ne 0 && ! -e "$tmp/denied" && $code -ne 134 ]]; then
    append codex PASS "$version" "native reviewer sandbox denied write"
  else
    append codex FAIL "$version" "sandbox denial invalid: exit=$code file=$(test -e "$tmp/denied" && echo present || echo absent)"
  fi
fi

kiro=$(find_bin kiro-cli)
if [[ -z "$kiro" ]]; then append kiro UNAVAILABLE unknown "binary not installed"
else
  version=$($kiro --version 2>&1 | head -n 1)
  reviewer="$HOME/.kiro/agents/independent-reviewer.json"
  if [[ -f "$reviewer" ]] && $kiro agent validate --path "$reviewer" >/dev/null 2>&1 &&
      jq -e '([.tools[]? | select(test("write|delete|append|replace"; "i"))] | length) == 0' "$reviewer" >/dev/null; then
    append kiro PASS "$version" "native agent validation passed; reviewer has no write tool"
  else append kiro FAIL "$version" "native reviewer config missing, invalid, or writable"
  fi
fi

for provider in claude gemini; do
  binary=$(find_bin "$provider")
  if [[ -z "$binary" ]]; then append "$provider" UNAVAILABLE unknown "binary not installed"
  else append "$provider" PASS "$($binary --version 2>&1 | head -n 1)" "native version command passed"
  fi
done

status=$(jq -r 'if all(.[]; .status == "PASS") then "PASS" else "INCOMPLETE" end' <<<"$results")
mkdir -p "$(dirname "$OUTPUT")"; umask 077
jq -n --arg status "$status" --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --argjson providers "$results" \
  '{schema_version:1,status:$status,timestamp:$timestamp,providers:$providers}' > "$OUTPUT"
[[ "$status" == PASS ]] || exit 2
