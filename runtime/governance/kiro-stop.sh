#!/usr/bin/env bash
# Kiro Stop uses a JSON block decision instead of relying on a non-zero exit.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
if output=$(printf '%s' "$INPUT" | python3 "$ROOT/task-lifecycle.py" stop 2>&1); then
  jq -cn --arg message "$output" '{continue:true,systemMessage:$message}'
else
  jq -cn --arg reason "$output" '{decision:"block",reason:$reason}'
fi
