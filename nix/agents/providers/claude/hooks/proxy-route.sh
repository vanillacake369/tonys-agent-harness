#!/usr/bin/env bash
# Pattern A: Automatic routing check via cli-proxy-api
# Called by Claude Code PreToolUse hook
# Checks if proxy is available and logs tool usage for cost tracking
#
# Exit codes:
#   0 = allow (proxy available, logged)
#   0 = allow (proxy unavailable, skip silently)
# This hook never blocks — it only observes and logs.

PROXY_URL="http://127.0.0.1:4001"

# Read hook input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Skip if proxy is not running
if ! curl -s --max-time 1 "$PROXY_URL/health" > /dev/null 2>&1; then
  exit 0
fi

# Log tool usage to proxy for cost tracking
curl -s --max-time 2 \
  -X POST "$PROXY_URL/api/hooks/log" \
  -H "Content-Type: application/json" \
  -d "{\"tool\": \"$TOOL_NAME\", \"source\": \"claude-code\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  > /dev/null 2>&1

exit 0
