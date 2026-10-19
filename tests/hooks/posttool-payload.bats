#!/usr/bin/env bats
# PostToolUse payload compatibility: hooks must understand provider variants.

setup() {
  WORK=$(mktemp -d)
  export CLAUDE_ESCALATION_STATE_DIR="$WORK/escalation"
  TEST_FEEDBACK="$BATS_TEST_DIRNAME/../../nix/agents/providers/claude/hooks/test-feedback.sh"
  ESCALATION_GATE="$BATS_TEST_DIRNAME/../../nix/agents/providers/claude/hooks/escalation-gate.sh"
}

teardown() { rm -rf "$WORK"; }

@test "test-feedback reads tool_response output and exit_code" {
  payload='{
    "tool_name":"Bash",
    "tool_input":{"command":"just test"},
    "tool_response":{"exit_code":1,"stdout":"ok 1\nFAIL broken assertion\n","stderr":"error: failed"}
  }'

  run bash "$TEST_FEEDBACK" <<<"$payload"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[TEST-SENSOR] Test FAILED (exit 1)"* ]]
  [[ "$output" == *"FAIL broken assertion"* ]]
}

@test "escalation-gate treats tool_response exit_code as failure" {
  payload='{
    "tool_name":"Bash",
    "tool_input":{"command":"nix build .#broken"},
    "tool_response":{"exit_code":1,"stdout":"","stderr":"error: build failed"}
  }'

  run bash "$ESCALATION_GATE" <<<"$payload"

  [ "$status" -eq 1 ]
  [[ "$output" == *"[RETRY 1/3]"* ]]
}
