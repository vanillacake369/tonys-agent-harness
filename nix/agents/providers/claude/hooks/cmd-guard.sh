#!/usr/bin/env bash
# PreToolUse Guard: Dangerous command blocker
# Blocks destructive shell commands before execution.
#
# Exit codes:
#   0 = allow
#   2 = block (dangerous pattern detected)
#
# This hook runs on PreToolUse for Bash matcher.

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# --- Dangerous pattern detection ---
# We check the actual command structure, not string literals in quotes.
# Strip quoted strings to avoid false positives on echo "rm -rf" etc.
STRIPPED=$(echo "$COMMAND" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

# 1. Destructive rm -rf targeting root, home, or wildcard root children
# Block: rm -rf /, rm -rf ~, rm -rf /*, rm -rf $HOME
# Allow: rm -f /tmp/test.txt (specific file with absolute path)
# shellcheck disable=SC2016
if echo "$STRIPPED" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|(-[a-zA-Z]*f[a-zA-Z]*\s+)?-[a-zA-Z]*r)\s+.*(\/\s*$|\/\*|~|\/\*\s|\$HOME)'; then
  echo "[CMD-GUARD] Blocked: recursive rm on root/home path."
  exit 2
fi

# 2. Force push
if echo "$STRIPPED" | grep -qE 'git\s+push\s+.*--force'; then
  echo "[CMD-GUARD] Blocked: git push --force. Use --force-with-lease if needed."
  exit 2
fi

# 3. Hard reset
if echo "$STRIPPED" | grep -qE 'git\s+reset\s+--hard'; then
  echo "[CMD-GUARD] Blocked: git reset --hard. This discards uncommitted work."
  exit 2
fi

# 4. SQL destructive operations
if echo "$STRIPPED" | grep -qiE '(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)'; then
  echo "[CMD-GUARD] Blocked: destructive SQL operation."
  exit 2
fi

# 5. Chmod 777
if echo "$STRIPPED" | grep -qE 'chmod\s+777'; then
  echo "[CMD-GUARD] Blocked: chmod 777 is a security risk."
  exit 2
fi

# 6. Pipe from network to shell (curl|sh, wget|bash, etc.)
if echo "$STRIPPED" | grep -qE '(curl|wget)\s+.*\|\s*(sh|bash|zsh|fish)'; then
  echo "[CMD-GUARD] Blocked: piping remote content to shell."
  exit 2
fi

# 7. dd to disk devices
if echo "$STRIPPED" | grep -qE 'dd\s+.*of=\/dev\/(sd|nvme|disk)'; then
  echo "[CMD-GUARD] Blocked: dd to raw disk device."
  exit 2
fi

exit 0
