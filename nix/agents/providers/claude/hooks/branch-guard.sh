#!/usr/bin/env bash
# PreToolUse Guard: Branch protection
# Blocks direct push to main/master and force-push to any branch.
#
# Exit codes:
#   0 = allow
#   2 = block

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Only check git push commands
echo "$COMMAND" | grep -qE 'git\s+push' || exit 0

# Strip quoted strings to avoid false positives
STRIPPED=$(echo "$COMMAND" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Block force push on any branch (already in cmd-guard, but explicit here for clarity)
if echo "$STRIPPED" | grep -qE 'git\s+push\s+.*--force($|\s)'; then
  echo "[BRANCH-GUARD] Blocked: --force push. Use --force-with-lease for safety."
  exit 2
fi

# Detect target branch from command or current branch
TARGET_BRANCH=""
# Try to extract from "git push origin main" pattern
TARGET_BRANCH=$(echo "$STRIPPED" | grep -oE 'git\s+push\s+\S+\s+(\S+)' | awk '{print $NF}' || true)

# If no explicit target, check current branch
if [[ -z "$TARGET_BRANCH" ]]; then
  TARGET_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
fi

case "$TARGET_BRANCH" in
  main|master)
    echo "[BRANCH-GUARD] Blocked: direct push to $TARGET_BRANCH. Create a PR instead."
    exit 2 ;;
esac

exit 0
