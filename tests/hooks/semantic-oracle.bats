#!/usr/bin/env bats
# semantic-oracle.sh: diagnose dispatch, A/B arm, tiered scope (L blocks, M advises), telemetry.

setup() {
  WORK=$(mktemp -d)
  export TMPDIR="$WORK/tmp"
  mkdir -p "$TMPDIR"
  export AGENT_POLICY_STATE="$WORK/state"
  export LANG_TOOLS_JSON="$BATS_TEST_DIRNAME/fixtures/lang-tools.json"
  export EXPERIMENT_ARM_FILE="$WORK/arm"
  export COMPLEXITY_DIR="$WORK/complexity"
  export TELEMETRY_FILE="$WORK/telemetry.jsonl"
  mkdir -p "$COMPLEXITY_DIR"
  echo "L" > "$COMPLEXITY_DIR/s1" # default session = L complexity
  HOOK="$BATS_TEST_DIRNAME/../../nix/agents/providers/claude/hooks/semantic-oracle.sh"
  for ext in ok bad nd miss; do echo "code" > "$WORK/a.$ext"; done
}

teardown() { rm -rf "$WORK"; }

# $1=file $2=tool(default Edit) $3=session(default s1)
mkinput() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' \
    "${2:-Edit}" "$1" "${3:-s1}"
}

run_hook() {
  printf '%s' "$1" > "$WORK/input.json"
  run bash "$HOOK" <"$WORK/input.json"
}

last_result() { tail -1 "$TELEMETRY_FILE" | jq -r '.result'; }
last_field() { tail -1 "$TELEMETRY_FILE" | jq -r ".$1"; }

@test "ignores non-mutation tools (no telemetry)" {
  run_hook "$(mkinput "$WORK/a.ok" Read)"
  [ "$status" -eq 0 ]
  [ ! -f "$TELEMETRY_FILE" ]
}

@test "arm=off records sample and skips check" {
  echo "off" > "$EXPERIMENT_ARM_FILE"
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "skip-arm-off" ]
  [ "$(last_field arm)" = "off" ]
}

@test "S complexity is exempt from scope" {
  echo "S" > "$COMPLEXITY_DIR/s1"
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "skip-scope" ]
}

@test "L + clean diagnose = pass" {
  run_hook "$(mkinput "$WORK/a.ok")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "pass" ]
  [ "$(last_field arm)" = "on" ]
}

@test "M complexity is in scope" {
  echo "M" > "$COMPLEXITY_DIR/s1"
  run_hook "$(mkinput "$WORK/a.ok")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "pass" ]
}

@test "L + failing diagnose = new breakage forces exit 2" {
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"[SEMANTIC-ORACLE]"* ]]
  [ "$(last_result)" = "fail-new" ]
}

@test "M + new breakage = soft advisory, exit 0, advisory-new telemetry" {
  echo "M" > "$COMPLEXITY_DIR/s1"
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SEMANTIC-ORACLE][advisory]"* ]]
  [ "$(last_result)" = "advisory-new" ]
}

@test "repeated identical failure is not re-blocked" {
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 2 ]
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "fail-unchanged" ]
}

@test "no diagnose command = grep fallback" {
  run_hook "$(mkinput "$WORK/a.nd")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "fallback-no-diagnose" ]
  [ "$(last_field fallback)" = "true" ]
}

@test "missing diagnose tool = fallback" {
  run_hook "$(mkinput "$WORK/a.miss")"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = "fallback-tool-missing" ]
}

@test "silent when tool table missing" {
  export LANG_TOOLS_JSON="$WORK/nope.json"
  run_hook "$(mkinput "$WORK/a.bad")"
  [ "$status" -eq 0 ]
  [ ! -f "$TELEMETRY_FILE" ]
}
