#!/usr/bin/env bash
# PostToolUse Sensor: Test result summarizer
# Parses test/check command output and provides structured feedback.
# Extracts top failures to minimize tokens while maximizing signal.
#
# Exit codes:
#   0 = always (non-blocking sensor)

set -uo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '
  .tool_output
  // .tool_response.output
  // ((.tool_response.stdout // "") + "\n" + (.tool_response.stderr // ""))
  // .output
  // empty
' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_exit_code // .tool_response.exit_code // .exit_code // 0' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only activate for test/check commands
# Detect test/check commands via grep (avoids shellcheck case pattern warnings)
if ! echo "$COMMAND" | grep -qE '(test|spec|check|jest|pytest|vitest|mocha)'; then
  exit 0
fi

# If test passed, brief confirmation
if [[ "$EXIT_CODE" == "0" ]]; then
  # Count pass/fail if available
  PASS_COUNT=$(echo "$TOOL_OUTPUT" | grep -coiE '(pass|ok|succeeded)' 2>/dev/null || echo "")
  if [[ -n "$PASS_COUNT" && "$PASS_COUNT" -gt 0 ]]; then
    echo "[TEST-SENSOR] All tests passed."
  fi
  exit 0
fi

# Test failed — extract top 3 errors for efficient feedback
echo "[TEST-SENSOR] Test FAILED (exit $EXIT_CODE). Top errors:"

# Try common error patterns across frameworks
ERRORS=$(echo "$TOOL_OUTPUT" | grep -iE '(FAIL|ERROR|error\[|panic|AssertionError|Expected|assert)' 2>/dev/null | head -5)

if [[ -n "$ERRORS" ]]; then
  echo "$ERRORS"
else
  # Fallback: last 10 lines (usually contain the summary)
  echo "$TOOL_OUTPUT" | tail -10
fi

exit 0
