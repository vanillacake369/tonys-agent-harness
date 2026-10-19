#!/usr/bin/env bats
# auto-lint.sh: consumes the SSoT tool table, runs file-scoped format/lint.

setup() {
  WORK=$(mktemp -d)
  export TMPDIR="$WORK/tmp"
  mkdir -p "$TMPDIR"
  export LANG_TOOLS_JSON="$BATS_TEST_DIRNAME/fixtures/lang-tools.json"
  HOOK="$BATS_TEST_DIRNAME/../../nix/agents/providers/claude/hooks/auto-lint.sh"
}

teardown() { rm -rf "$WORK"; }

# $1=file_path $2=tool_name(default Edit)
mkinput() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "${2:-Edit}" "$1"
}

run_hook() {
  printf '%s' "$1" > "$WORK/input.json"
  run bash "$HOOK" <"$WORK/input.json"
}

@test "surfaces format output when issues present" {
  echo "this has a PROBLEM line" > "$WORK/a.prob"
  run_hook "$(mkinput "$WORK/a.prob")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[AUTO-LINT]"* ]]
  [[ "$output" == *"PROBLEM"* ]]
}

@test "silent when file is clean" {
  echo "all good here" > "$WORK/a.prob"
  run_hook "$(mkinput "$WORK/a.prob")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "runs both format and lint when both defined" {
  printf 'PROBLEM\nWARN\n' > "$WORK/a.both"
  run_hook "$(mkinput "$WORK/a.both")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"grep PROBLEM"* ]]
  [[ "$output" == *"grep WARN"* ]]
}

@test "ignores non-mutation tools" {
  echo "PROBLEM" > "$WORK/a.prob"
  run_hook "$(mkinput "$WORK/a.prob" Read)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent for unknown extension" {
  echo "PROBLEM" > "$WORK/a.unknownext"
  run_hook "$(mkinput "$WORK/a.unknownext")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when tool table missing" {
  export LANG_TOOLS_JSON="$WORK/does-not-exist.json"
  echo "PROBLEM" > "$WORK/a.prob"
  run_hook "$(mkinput "$WORK/a.prob")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dedupes identical consecutive feedback" {
  echo "PROBLEM" > "$WORK/a.prob"
  run_hook "$(mkinput "$WORK/a.prob")"
  [[ "$output" == *"[AUTO-LINT]"* ]]
  run_hook "$(mkinput "$WORK/a.prob")"
  [ -z "$output" ]
}
