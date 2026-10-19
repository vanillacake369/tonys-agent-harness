#!/usr/bin/env bats

@test "agent-notify shell suite passes" {
  run bash "$BATS_TEST_DIRNAME/../../nix/agents/providers/claude/hooks/agent-notify-test.sh"
  [ "$status" -eq 0 ]
}
