#!/usr/bin/env bash
# PreToolUse Guard: Context window cost gate
# Warns or blocks when context usage exceeds thresholds.
# Prevents token budget blowout from runaway agent loops.
#
# Exit codes:
#   0 = allow (under threshold or info not available)
#   2 = block (context >= 80%)
#
# This hook reads context_window.used_percentage from stdin JSON.

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only gate expensive operations (Agent spawning)
case "$TOOL_NAME" in
  Agent) ;;
  *) exit 0 ;;
esac

USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)

# Handle non-numeric or missing values
if ! [[ "$USED_PCT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  exit 0
fi

USED_INT=${USED_PCT%.*}
USED_INT=${USED_INT:-0}

if [[ "$USED_INT" -ge 80 ]]; then
  echo "[COST-GATE] BLOCKED: Context window at ${USED_INT}%. Run /clear or summarize before spawning new agents."
  exit 2
fi

if [[ "$USED_INT" -ge 60 ]]; then
  echo "[COST-GATE] WARNING: Context window at ${USED_INT}%. Consider /clear soon."
  # Warning only — don't block
  exit 0
fi

exit 0
