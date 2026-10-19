#!/usr/bin/env bash
# PostToolUse Sensor: Auto-lint after file edits.
# Runs file-scoped format/lint commands for the edited file's language and
# feeds results back to Claude.
#
# Language→tool mapping is NOT hardcoded here — it is read from the generated
# SSoT table (modules/language/language.hm.nix → ~/.claude/lang-tools.json). Override the path
# with LANG_TOOLS_JSON (used by the bats suite).
#
# Exit codes: 0 always (non-blocking sensor).

set -uo pipefail

LANG_TOOLS_JSON="${LANG_TOOLS_JSON:-$HOME/.claude/lang-tools.json}"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)

case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ ! -f "$LANG_TOOLS_JSON" ]] && exit 0

EXT="${FILE_PATH##*.}"
BASENAME=$(basename "$FILE_PATH")

# Pull file-scoped commands for this extension from the SSoT table.
FORMAT_CMD=$(jq -r --arg e "$EXT" '.[$e].format // empty' "$LANG_TOOLS_JSON" 2>/dev/null)
LINT_CMD=$(jq -r --arg e "$EXT" '.[$e].lint // empty' "$LANG_TOOLS_JSON" 2>/dev/null)

run_tool() {
  # $1 = command string (e.g. "gofmt -l"); appends the file path.
  local cmd="$1"
  [[ -z "$cmd" ]] && return 0
  local parts
  read -ra parts <<< "$cmd"
  "${parts[@]}" "$FILE_PATH" 2>&1 | head -20 || true
}

LINT_OUTPUT=""
LABEL=""
for spec in "format:$FORMAT_CMD" "lint:$LINT_CMD"; do
  kind="${spec%%:*}"
  cmd="${spec#*:}"
  [[ -z "$cmd" ]] && continue
  out=$(run_tool "$cmd")
  if [[ -n "$out" ]]; then
    LINT_OUTPUT+="[$kind] $cmd"$'\n'"$out"$'\n'
    LABEL+="${LABEL:+, }$cmd"
  fi
done

[[ -z "$LINT_OUTPUT" ]] && exit 0

# Cache: skip if identical to previous run (prevents feedback loops).
CACHE_DIR="${TMPDIR:-/tmp}/claude-autolint"
mkdir -p "$CACHE_DIR"
CACHE_KEY=$(echo "$FILE_PATH" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$BASENAME")
CACHE_FILE="$CACHE_DIR/$CACHE_KEY"
CURRENT_HASH=$(echo "$LINT_OUTPUT" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "none")

if [[ -f "$CACHE_FILE" ]] && [[ "$(cat "$CACHE_FILE")" == "$CURRENT_HASH" ]]; then
  exit 0
fi
echo "$CURRENT_HASH" > "$CACHE_FILE"

echo "[AUTO-LINT] issues in $BASENAME ($LABEL):"
echo "$LINT_OUTPUT" | head -20

exit 0
