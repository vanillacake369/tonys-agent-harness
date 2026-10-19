#!/usr/bin/env bash
# Enforce the project MCP role/skill allowlist before an MCP call is made.
set -euo pipefail
POLICY=${1:-}; SERVER=${2:-}; ROLE=${3:-}; SKILL=${4:-}
if [[ -z "$POLICY" || -z "$SERVER" || -z "$ROLE" || -z "$SKILL" || ! -f "$POLICY" ]]; then
  echo "mcp gate: policy, server, role, and skill are required" >&2; exit 2
fi
if ! jq -e --arg server "$SERVER" --arg role "$ROLE" --arg skill "$SKILL" '(.mcp_allowlist // .) | .servers[$server] as $s | $s and ($s.mutation == false) and ($s.roles | index($role)) and ($s.skills | index($skill))' "$POLICY" >/dev/null 2>&1; then
  echo "mcp gate blocked: server is not allowed for role/skill" >&2; exit 2
fi
echo "mcp gate passed: $SERVER/$ROLE/$SKILL"
