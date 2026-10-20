#!/usr/bin/env bash
# Fan one provider payload into deterministic pre-execution gates.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
printf '%s' "$INPUT" | "$ROOT/path-guard.sh"
printf '%s' "$INPUT" | python3 "$ROOT/execution-gate.py"
printf '%s' "$INPUT" | "$ROOT/retry-hook.sh" pre

# Codex PreToolUse requires a structured response even when the tool is
# allowed. Keep the deterministic gates silent internally, then emit the
# provider-native allow envelope exactly once.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
