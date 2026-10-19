#!/usr/bin/env bash
# Claude Code subagent status line hook
# Reads a JSON object with a `tasks` array from stdin.
# Outputs one line of JSON per task: {"id": "<task_id>", "content": "<formatted row>"}
#
# Input JSON per task:
#   id, name, type, status, description, tokenCount, startTime
#
# This hook never exits non-zero — it must not block the agent.

set -uo pipefail

# ANSI colors (use $'...' to get real escape byte, not literal backslash)
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
RED=$'\033[31m'
RESET=$'\033[0m'

# ===========================================================================
# Agent icon mapping
# ===========================================================================
_agent_icon() {
  local name
  name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$name" in
    architect)       echo "🏗️" ;;
    implementer)     echo "⚙️" ;;
    reviewer)        echo "🔎" ;;
    tester)          echo "🧪" ;;
    refactorer)      echo "♻️" ;;
    researcher)      echo "🔍" ;;
    cross-validator) echo "✅" ;;
    *)               echo "🤖" ;;
  esac
}

# ===========================================================================
# Status color
# ===========================================================================
_status_color() {
  local status
  status=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$status" in
    running)            echo "$YELLOW" ;;
    done|completed)     echo "$GREEN" ;;
    error|cancelled)    echo "$RED" ;;
    *)                  echo "" ;;
  esac
}

# ===========================================================================
# Process tasks
# ===========================================================================
INPUT=$(cat 2>/dev/null || true)

NOW=$(date +%s)

echo "$INPUT" | jq -c '.tasks[]? // empty' 2>/dev/null | while IFS= read -r TASK; do
  TASK_ID=$(echo "$TASK" | jq -r '.id // ""')
  TASK_NAME=$(echo "$TASK" | jq -r '.name // ""')
  TASK_STATUS=$(echo "$TASK" | jq -r '.status // ""')
  TASK_TOKENS=$(echo "$TASK" | jq -r '.tokenCount // 0')
  TASK_START=$(echo "$TASK" | jq -r '.startTime // 0')

  [[ -z "$TASK_ID" ]] && continue

  ICON=$(_agent_icon "$TASK_NAME")
  COLOR=$(_status_color "$TASK_STATUS")
  STATUS_UPPER=$(echo "$TASK_STATUS" | tr '[:lower:]' '[:upper:]')

  # Token count: divide by 1000
  TOKEN_K=$(echo "$TASK_TOKENS" | awk '{printf "%.1fk", $1/1000}')

  # Elapsed seconds from startTime to now
  ELAPSED_S=$(( NOW - TASK_START ))
  [[ $ELAPSED_S -lt 0 ]] && ELAPSED_S=0

  # Format content with ANSI escape codes embedded in the string
  CONTENT="${ICON} ${TASK_NAME} | ${COLOR}${STATUS_UPPER}${RESET} | ${TOKEN_K} tok | ${ELAPSED_S}s"

  # Output JSON line — escape the content for JSON
  printf '{"id": %s, "content": %s}\n' \
    "$(echo "$TASK_ID" | jq -R '.')" \
    "$(printf '%s' "$CONTENT" | jq -R '.')"
done
