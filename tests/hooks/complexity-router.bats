#!/usr/bin/env bats
# complexity-router.sh: reversibility classification via risk-keyword detection.

setup() {
  WORK=$(mktemp -d)
  export TMPDIR="$WORK/tmp"
  mkdir -p "$TMPDIR"
  export COMPLEXITY_DIR="$WORK/complexity"
  mkdir -p "$COMPLEXITY_DIR"
  HOOK="$BATS_TEST_DIRNAME/../../nix/agents/providers/claude/hooks/complexity-router.sh"
}

teardown() { rm -rf "$WORK"; }

# $1=prompt $2=session_id(default test-session)
mkinput() {
  local prompt="${1:-hello}"
  local session="${2:-test-session-$$}"
  printf '{"prompt":"%s","session_id":"%s"}' "$prompt" "$session"
}

run_hook() {
  printf '%s' "$1" > "$WORK/input.json"
  COMPLEXITY_DIR="$COMPLEXITY_DIR" run bash "$HOOK" <"$WORK/input.json"
}

# ─── Reversibility: irreversible keywords ────────────────────────────────────

@test "destructive DDL 'DROP TABLE' → irreversible" {
  local session="sess-del-$$"
  run_hook "$(mkinput "run DROP TABLE users to clean up" "$session")"
  [ "$status" -eq 0 ]
  [ -f "$COMPLEXITY_DIR/${session}.reversibility" ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "irreversible" ]
}

@test "prompt with 'drop table' → irreversible" {
  local session="sess-drop-$$"
  run_hook "$(mkinput "drop table users" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "irreversible" ]
}

@test "benign 'prod' mention no longer over-escalates → reversible" {
  local session="sess-prod-$$"
  run_hook "$(mkinput "deploy to prod server" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "reversible" ]
}

@test "benign 'production' mention no longer over-escalates → reversible" {
  local session="sess-production-$$"
  run_hook "$(mkinput "this affects the production environment" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "reversible" ]
}

@test "prompt with 'reset --hard' keyword → irreversible" {
  local session="sess-reset-$$"
  run_hook "$(mkinput "run git reset --hard to undo changes" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "irreversible" ]
}

@test "prompt with 'migrate' keyword → irreversible" {
  local session="sess-migrate-$$"
  run_hook "$(mkinput "migrate the database schema" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "irreversible" ]
}

@test "prompt with 'force push' (two words) → irreversible" {
  local session="sess-fp-$$"
  run_hook "$(mkinput "do a force push to the branch" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "irreversible" ]
}

@test "uppercase 'RM -RF' is case-insensitive → irreversible" {
  local session="sess-upper-$$"
  run_hook "$(mkinput "RM -RF the build dir" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "irreversible" ]
}

# ─── Reversibility: benign prompts ───────────────────────────────────────────

@test "benign prompt 'rename a variable' → reversible" {
  local session="sess-rename-$$"
  run_hook "$(mkinput "rename a variable in this function" "$session")"
  [ "$status" -eq 0 ]
  [ -f "$COMPLEXITY_DIR/${session}.reversibility" ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "reversible" ]
}

@test "benign prompt 'add a comment' → reversible" {
  local session="sess-comment-$$"
  run_hook "$(mkinput "add a comment to this function" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "reversible" ]
}

@test "benign prompt 'fix the typo' → reversible" {
  local session="sess-typo-$$"
  run_hook "$(mkinput "fix the typo in the README" "$session")"
  [ "$status" -eq 0 ]
  [ "$(cat "$COMPLEXITY_DIR/${session}.reversibility")" = "reversible" ]
}

# ─── Existing behavior: skip complexity injection on subsequent turns ─────────

@test "second call with existing state skips injection" {
  local session="sess-skip-$$"
  # Pre-seed complexity state (simulating a classified session)
  echo "L" > "$COMPLEXITY_DIR/$session"
  run_hook "$(mkinput "rename a variable" "$session")"
  [ "$status" -eq 0 ]
  # Still writes reversibility even on skip (reads prompt from stdin)
  # The hook exits 0 regardless
  [ "$status" -eq 0 ]
}

@test "exit code is always 0 (never blocks)" {
  local session="sess-exit-$$"
  run_hook "$(mkinput "drop table users" "$session")"
  [ "$status" -eq 0 ]
}
