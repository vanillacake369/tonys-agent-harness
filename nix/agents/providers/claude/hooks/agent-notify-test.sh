#!/usr/bin/env bash
# Tests for agent-notify.sh
# Usage: bash agent-notify-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/agent-notify.sh"

PASS=0
FAIL=0
TOTAL=0

# ===========================================================================
# Test helpers
# ===========================================================================

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: '$needle'"
    echo "    actual:              '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected NOT to contain: '$needle'"
    echo "    actual:                  '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# 1. Input Parsing
# ===========================================================================

echo "=== 1. Input Parsing ==="

# 1-1. Claude Code Stop hook JSON (no prompt field)
result=$(echo '{"session_id":"abc-123","cwd":"/home/user/project","transcript_path":"/tmp/t.jsonl"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "claude: extracts session_id" "session_id=abc-123" "$result"
assert_contains "claude: extracts cwd" "cwd=/home/user/project" "$result"
assert_contains "claude: provider is claude" "provider=claude" "$result"
assert_contains "claude: prompt is empty when missing" "prompt=" "$result"

# 1-2. Codex Stop hook JSON (has last_assistant_message)
result=$(echo '{"session_id":"codex-456","cwd":"/workspace","last_assistant_message":"Fixed the auth bug"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test codex)
assert_contains "codex: extracts session_id" "codex-456" "$result"
assert_contains "codex: extracts last_assistant_message as summary" "summary=Fixed the auth bug" "$result"

# 1-3. Gemini AfterAgent hook JSON (has prompt + prompt_response)
result=$(echo '{"session_id":"gem-789","cwd":"/dev/app","prompt":"Add unit tests for auth module","prompt_response":"Done. Created 5 test cases."}' \
  | bash "$NOTIFY_SCRIPT" --parse-test gemini)
assert_contains "gemini: extracts prompt" "prompt=Add unit tests for auth module" "$result"
assert_contains "gemini: extracts summary from prompt_response" "summary=Done. Created 5 test cases." "$result"

# 1-4. Missing session_id falls back to "unknown"
result=$(echo '{"cwd":"/tmp"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "missing session_id: falls back to unknown" "session_id=unknown" "$result"

# 1-5. Missing cwd falls back to "unknown"
result=$(echo '{"session_id":"x"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "missing cwd: falls back to unknown" "cwd=unknown" "$result"

# 1-6. Empty stdin
result=$(echo '' | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "empty stdin: session_id=unknown" "session_id=unknown" "$result"
assert_contains "empty stdin: cwd=unknown" "cwd=unknown" "$result"

# 1-7. Invalid JSON
result=$(echo 'not-json' | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "invalid json: session_id=unknown" "session_id=unknown" "$result"

# 1-8. JSON parsing quotes shell metacharacters safely
INJECT_DIR=$(mktemp -d)
INJECT_MARK="$INJECT_DIR/marker"
inject_prompt='$(touch '"$INJECT_MARK"')'
inject_json=$(printf '{"session_id":"safe-1","cwd":"/tmp","prompt":"%s"}' "$inject_prompt")
result=$(echo "$inject_json" | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "shell metacharacters: prompt is parsed" "prompt=$inject_prompt" "$result"
TOTAL=$((TOTAL + 1))
if [[ ! -e "$INJECT_MARK" ]]; then
  echo "  PASS: shell metacharacters are not executed"
  PASS=$((PASS + 1))
else
  echo "  FAIL: shell metacharacters executed unexpectedly"
  FAIL=$((FAIL + 1))
fi
rm -rf "$INJECT_DIR"

echo ""

# ===========================================================================
# 2. Notification Args (terminal-notifier params)
# ===========================================================================

echo "=== 2. Notification Args ==="

# 2-1. Claude: title, subtitle (project), group, message (no prompt → session info)
result=$(echo '{"session_id":"abc-123","cwd":"/home/user/my-project"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test claude)
assert_contains "claude title" "title=Claude" "$result"
assert_contains "claude subtitle is project dir" "subtitle=my-project" "$result"
assert_contains "claude group has provider+session" "group=claude-abc-123" "$result"
assert_contains "claude message shows completed" "completed" "$result"

# 2-2. Gemini: prompt shown as message
result=$(echo '{"session_id":"gem-1","cwd":"/dev/app","prompt":"Add retry logic to API calls"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test gemini)
assert_contains "gemini title" "title=Gemini" "$result"
assert_contains "gemini message includes prompt" "Add retry logic" "$result"

# 2-3. Codex: last_assistant_message shown as message
result=$(echo '{"session_id":"cdx-1","cwd":"/workspace","last_assistant_message":"Refactored auth module into 3 files"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test codex)
assert_contains "codex title" "title=Codex" "$result"
assert_contains "codex message includes summary" "Refactored auth" "$result"

# 2-4. Long prompt gets truncated
long_prompt="Implement comprehensive error handling for all API endpoints including retry logic and circuit breaker pattern with exponential backoff"
result=$(echo "{\"session_id\":\"x\",\"cwd\":\"/tmp\",\"prompt\":\"$long_prompt\"}" \
  | bash "$NOTIFY_SCRIPT" --notify-args-test gemini)
# Message should be truncated (max 60 chars for readability)
msg_line=$(echo "$result" | grep '^message=')
msg_len=${#msg_line}
# "message=" is 8 chars, so content should be <= 68
if [[ $msg_len -le 72 ]]; then
  echo "  PASS: long prompt is truncated"
  PASS=$((PASS + 1))
else
  echo "  FAIL: long prompt is truncated (len=$msg_len)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# 2-5. execute calls agent-notify-open.sh with session name when ZELLIJ_SESSION_NAME is set
if [[ "$(uname)" == "Darwin" ]]; then
  result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
    | ZELLIJ_SESSION_NAME=my-session bash "$NOTIFY_SCRIPT" --notify-args-test claude)
  assert_contains "execute calls open script" "agent-notify-open.sh" "$result"
  assert_contains "execute passes session name" "my-session" "$result"
fi

# 2-6. execute without zellij calls open script without session arg
if [[ "$(uname)" == "Darwin" ]]; then
  result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
    | ZELLIJ_SESSION_NAME= bash "$NOTIFY_SCRIPT" --notify-args-test claude)
  assert_contains "execute without zellij: calls open script" "agent-notify-open.sh" "$result"
  assert_not_contains "execute without zellij: no session arg" "agent-notify-open.sh " "$result"
fi

# 2-7. No provider defaults to Agent
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test)
assert_contains "default title is Agent" "title=Agent" "$result"

echo ""

# ===========================================================================
# 2b. AskUserQuestion (PreToolUse) — Claude asks the user
# ===========================================================================

echo "=== 2b. AskUserQuestion Notification ==="

ASK_JSON='{"session_id":"ask-1","cwd":"/dev/my-project","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"header":"Auth method","question":"Which auth method should we use?"}]}}'

# 2b-1. Parses question text from tool_input
result=$(echo "$ASK_JSON" | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "ask: extracts question from tool_input" "question=Which auth method should we use?" "$result"

# 2b-2. Notify args use a question-styled title + question as message
result=$(echo "$ASK_JSON" | bash "$NOTIFY_SCRIPT" --notify-args-test claude)
assert_contains "ask: title indicates a question" "asks" "$result"
assert_contains "ask: subtitle is project dir" "subtitle=my-project" "$result"
assert_contains "ask: message shows the question" "Which auth method should we use?" "$result"

# 2b-3. Stop payload (no tool_input) is NOT treated as a question
result=$(echo '{"session_id":"s-1","cwd":"/dev/app"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "stop: question is empty" "question=" "$result"

# 2b-4. Questions are attention-required and are not suppressed by focus
result=$(echo "$ASK_JSON" \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=1 _TEST_FOCUSED_APP=WezTerm \
    ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_not_contains "ask: focused session still notifies" "skipped" "$result"
assert_contains "ask: dry run shows question" "Which auth method should we use?" "$result"

echo ""

# ===========================================================================
# 3. Backend Selection
# ===========================================================================

echo "=== 3. Backend Selection ==="

result=$(AGENT_NOTIFY_DRY_RUN=1 bash "$NOTIFY_SCRIPT" --backend-test)
assert_contains "dry run: returns a backend name" "backend=" "$result"

result=$(AGENT_NOTIFY_BACKEND=bell AGENT_NOTIFY_DRY_RUN=1 \
  bash "$NOTIFY_SCRIPT" --backend-test)
assert_eq "forced bell backend" "backend=bell" "$result"

result=$(AGENT_NOTIFY_BACKEND=noti AGENT_NOTIFY_DRY_RUN=1 \
  bash "$NOTIFY_SCRIPT" --backend-test)
assert_eq "forced noti backend" "backend=noti" "$result"

result=$(AGENT_NOTIFY_BACKEND=osascript AGENT_NOTIFY_DRY_RUN=1 \
  bash "$NOTIFY_SCRIPT" --backend-test)
assert_eq "forced osascript backend" "backend=osascript" "$result"

result=$(AGENT_NOTIFY_BACKEND=terminal-notifier AGENT_NOTIFY_DRY_RUN=1 \
  bash "$NOTIFY_SCRIPT" --backend-test)
assert_eq "forced terminal-notifier backend" "backend=terminal-notifier" "$result"

echo ""

# ===========================================================================
# 4. Integration (dry-run, full pipeline)
# ===========================================================================

echo "=== 4. Integration (dry-run) ==="

# 4-1. Claude full flow
result=$(echo '{"session_id":"int-001","cwd":"/home/user/my-project"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 bash "$NOTIFY_SCRIPT" claude)
assert_contains "integration claude: title" "title=Claude" "$result"
assert_contains "integration claude: subtitle" "subtitle=my-project" "$result"
assert_contains "integration claude: group" "group=claude-int-001" "$result"
assert_contains "integration claude: backend" "backend=" "$result"

# 4-2. Gemini with prompt
result=$(echo '{"session_id":"int-002","cwd":"/dev/frontend","prompt":"Fix CSS layout bug"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 bash "$NOTIFY_SCRIPT" gemini)
assert_contains "integration gemini: title" "title=Gemini" "$result"
assert_contains "integration gemini: prompt in message" "Fix CSS layout bug" "$result"

# 4-3. Codex with last_assistant_message
result=$(echo '{"session_id":"int-003","cwd":"/workspace/api","last_assistant_message":"Added 3 endpoints"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 bash "$NOTIFY_SCRIPT" codex 2>/dev/null)
assert_eq "integration codex: stdout is Stop JSON" '{"continue":true}' "$result"
result=$(echo '{"session_id":"int-003","cwd":"/workspace/api","last_assistant_message":"Added 3 endpoints"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 bash "$NOTIFY_SCRIPT" codex 2>&1 >/dev/null)
assert_contains "integration codex: diagnostics title" "title=Codex" "$result"
assert_contains "integration codex: diagnostics summary" "Added 3 endpoints" "$result"

# 4-4. No provider
result=$(echo '{"session_id":"no-prov","cwd":"/tmp/test"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 bash "$NOTIFY_SCRIPT")
assert_contains "no provider: defaults to Agent" "title=Agent" "$result"

echo ""

# ===========================================================================
# 5. Focus Suppression
# ===========================================================================

echo "=== 5. Focus Suppression ==="

# 5-1. Skips when session has clients AND terminal is focused
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=1 _TEST_FOCUSED_APP=WezTerm \
    ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_contains "has clients: skipped" "skipped" "$result"

# 5-2. Sends when session has no clients (user is in different session)
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 bash "$NOTIFY_SCRIPT" claude)
assert_not_contains "no clients: not skipped" "skipped" "$result"
assert_contains "no clients: has title" "title=" "$result"

# 5-3. Sends when not in zellij (no ZELLIJ_SESSION_NAME)
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 ZELLIJ_SESSION_NAME= _TEST_CLIENT_COUNT= bash "$NOTIFY_SCRIPT" claude)
assert_not_contains "no zellij: not skipped" "skipped" "$result"

echo ""

# ===========================================================================
# 6. Strategy B: Prompt+Summary Combo Notification
# ===========================================================================

echo "=== 6. Strategy B: Prompt+Summary Combo ==="

# 6-1. Both prompt and summary → subtitle=prompt, message=summary
result=$(echo '{"session_id":"b-1","cwd":"/dev/app","prompt":"Fix auth bug","prompt_response":"Fixed login flow by adding token refresh"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test gemini)
assert_contains "both: subtitle shows prompt" "subtitle=Fix auth bug" "$result"
assert_contains "both: message shows summary" "message=Fixed login flow" "$result"

# 6-2. Only prompt (no summary) → subtitle=project dir, message=prompt
result=$(echo '{"session_id":"b-2","cwd":"/dev/my-project","prompt":"Add retry logic"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test gemini)
assert_contains "prompt only: subtitle is project dir" "subtitle=my-project" "$result"
assert_contains "prompt only: message shows prompt" "message=Add retry logic" "$result"

# 6-3. Only summary (no prompt) → subtitle=project dir, message=summary
result=$(echo '{"session_id":"b-3","cwd":"/workspace/api","last_assistant_message":"Refactored into 3 modules"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test codex)
assert_contains "summary only: subtitle is project dir" "subtitle=api" "$result"
assert_contains "summary only: message shows summary" "message=Refactored into 3 modules" "$result"

# 6-4. Neither prompt nor summary → subtitle=project dir, message=Session completed
result=$(echo '{"session_id":"b-4","cwd":"/dev/app"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test claude)
assert_contains "neither: subtitle is project dir" "subtitle=app" "$result"
assert_contains "neither: message shows session completed" "Session b-4" "$result"

# 6-5. Long prompt+summary both truncated
result=$(echo '{"session_id":"b-5","cwd":"/tmp","prompt":"Implement comprehensive error handling for all API endpoints including retry logic","prompt_response":"Done. I have implemented comprehensive error handling across all API endpoints with retry logic and circuit breaker patterns"}' \
  | bash "$NOTIFY_SCRIPT" --notify-args-test gemini)
sub_line=$(echo "$result" | grep '^subtitle=')
msg_line=$(echo "$result" | grep '^message=')
sub_len=${#sub_line}
msg_len=${#msg_line}
# subtitle= is 10 chars, so content <= 70; message= is 8 chars, so content <= 68
TOTAL=$((TOTAL + 1))
if [[ $sub_len -le 74 ]]; then
  echo "  PASS: long prompt in subtitle is truncated"
  PASS=$((PASS + 1))
else
  echo "  FAIL: long prompt in subtitle is truncated (len=$sub_len)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if [[ $msg_len -le 72 ]]; then
  echo "  PASS: long summary in message is truncated"
  PASS=$((PASS + 1))
else
  echo "  FAIL: long summary in message is truncated (len=$msg_len)"
  FAIL=$((FAIL + 1))
fi

echo ""

# ===========================================================================
# 7. Strategy D: Click Opens Transcript
# ===========================================================================

echo "=== 7. Strategy D: Click Opens Transcript ==="

# 7-1. transcript_path is parsed from input
result=$(echo '{"session_id":"d-1","cwd":"/tmp","transcript_path":"/var/log/transcript.jsonl"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "parses transcript_path" "transcript_path=/var/log/transcript.jsonl" "$result"

# 7-2. transcript_path missing defaults to empty
result=$(echo '{"session_id":"d-2","cwd":"/tmp"}' \
  | bash "$NOTIFY_SCRIPT" --parse-test claude)
assert_contains "missing transcript_path is empty" "transcript_path=" "$result"

# 7-3. execute passes transcript_path to open script
if [[ "$(uname)" == "Darwin" ]]; then
  result=$(echo '{"session_id":"d-3","cwd":"/tmp","transcript_path":"/tmp/t.jsonl"}' \
    | ZELLIJ_SESSION_NAME=sess bash "$NOTIFY_SCRIPT" --notify-args-test claude)
  assert_contains "execute includes transcript path" "/tmp/t.jsonl" "$result"
fi

echo ""

# ===========================================================================
# 8. Strategy F: Notification Log File
# ===========================================================================

echo "=== 8. Strategy F: Notification Log File ==="

LOG_DIR=$(mktemp -d)
LOG_FILE="$LOG_DIR/agent-notify.log"

# 8-1. Log entry is created on notification
echo '{"session_id":"f-1","cwd":"/dev/app","prompt":"Fix bug","prompt_response":"Fixed it"}' \
  | AGENT_NOTIFY_DRY_RUN=1 AGENT_NOTIFY_LOG="$LOG_FILE" _TEST_CLIENT_COUNT=0 \
    bash "$NOTIFY_SCRIPT" gemini >/dev/null
TOTAL=$((TOTAL + 1))
if [[ -f "$LOG_FILE" ]]; then
  echo "  PASS: log file created"
  PASS=$((PASS + 1))
else
  echo "  FAIL: log file not created at $LOG_FILE"
  FAIL=$((FAIL + 1))
fi

# 8-2. Log contains provider, prompt, summary, timestamp
if [[ -f "$LOG_FILE" ]]; then
  log_content=$(cat "$LOG_FILE")
  assert_contains "log has provider" "gemini" "$log_content"
  assert_contains "log has prompt" "Fix bug" "$log_content"
  assert_contains "log has summary" "Fixed it" "$log_content"
  # Timestamp format: YYYY-MM-DD
  TOTAL=$((TOTAL + 1))
  if echo "$log_content" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    echo "  PASS: log has timestamp"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: log missing timestamp"
    FAIL=$((FAIL + 1))
  fi
else
  # Skip if log file doesn't exist (already failed above)
  TOTAL=$((TOTAL + 4))
  FAIL=$((FAIL + 4))
fi

# 8-3. Multiple notifications append (not overwrite)
echo '{"session_id":"f-2","cwd":"/tmp","prompt":"Second task"}' \
  | AGENT_NOTIFY_DRY_RUN=1 AGENT_NOTIFY_LOG="$LOG_FILE" _TEST_CLIENT_COUNT=0 \
    bash "$NOTIFY_SCRIPT" claude >/dev/null
TOTAL=$((TOTAL + 1))
if [[ -f "$LOG_FILE" ]]; then
  line_count=$(wc -l < "$LOG_FILE" | tr -d ' ')
  if [[ $line_count -ge 2 ]]; then
    echo "  PASS: log appends (${line_count} lines)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: log did not append (${line_count} lines)"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: log file missing for append test"
  FAIL=$((FAIL + 1))
fi

# 8-4. Skipped notifications are NOT logged
echo '{"session_id":"f-3","cwd":"/tmp","prompt":"Skipped task"}' \
  | AGENT_NOTIFY_DRY_RUN=1 AGENT_NOTIFY_LOG="$LOG_FILE" _TEST_CLIENT_COUNT=1 \
    _TEST_FOCUSED_APP=WezTerm ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude >/dev/null
if [[ -f "$LOG_FILE" ]]; then
  log_content=$(cat "$LOG_FILE")
  assert_not_contains "skipped notification not logged" "Skipped task" "$log_content"
fi

# 8-5. Question notifications are logged with the question kind
echo "$ASK_JSON" \
  | AGENT_NOTIFY_DRY_RUN=1 AGENT_NOTIFY_LOG="$LOG_FILE" _TEST_CLIENT_COUNT=1 \
    _TEST_FOCUSED_APP=WezTerm ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude >/dev/null
if [[ -f "$LOG_FILE" ]]; then
  log_content=$(cat "$LOG_FILE")
  assert_contains "question log has kind" "question" "$log_content"
  assert_contains "question log has question text" "Which auth method should we use?" "$log_content"
fi

# Cleanup
rm -rf "$LOG_DIR"

echo ""

# ===========================================================================
# 9. Hybrid Focus Detection
# ===========================================================================

echo "=== 9. Hybrid Focus Detection ==="

# 9-1. Terminal NOT focused → always notify (even if zellij has clients)
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=1 _TEST_FOCUSED_APP=Finder \
    ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_not_contains "terminal not focused: not skipped" "skipped" "$result"

# 9-2. Terminal focused + zellij has clients → skip
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=1 _TEST_FOCUSED_APP=WezTerm \
    ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_contains "terminal focused + clients: skipped" "skipped" "$result"

# 9-3. Terminal focused + no clients → notify
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=0 _TEST_FOCUSED_APP=WezTerm \
    ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_not_contains "terminal focused + no clients: not skipped" "skipped" "$result"

# 9-4. Custom terminal app name via AGENT_NOTIFY_TERMINAL
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=1 _TEST_FOCUSED_APP=Ghostty \
    AGENT_NOTIFY_TERMINAL=Ghostty ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_contains "custom terminal focused + clients: skipped" "skipped" "$result"

# 9-5. Custom terminal NOT focused → notify
result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
  | AGENT_NOTIFY_DRY_RUN=1 _TEST_CLIENT_COUNT=1 _TEST_FOCUSED_APP=WezTerm \
    AGENT_NOTIFY_TERMINAL=Ghostty ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" claude)
assert_not_contains "custom terminal not focused: not skipped" "skipped" "$result"

echo ""

# ===========================================================================
# 10. Provider-based Execute Command
# ===========================================================================

echo "=== 10. Provider-based Execute Command ==="

if [[ "$(uname)" == "Darwin" ]]; then
  # 10-1. Claude: execute includes AGENT_NOTIFY_PROVIDER=claude
  result=$(echo '{"session_id":"x","cwd":"/tmp","transcript_path":"/tmp/t.jsonl"}' \
    | ZELLIJ_SESSION_NAME=sess bash "$NOTIFY_SCRIPT" --notify-args-test claude)
  assert_contains "claude execute has provider env" "AGENT_NOTIFY_PROVIDER=claude" "$result"

  # 10-2. Gemini: execute includes AGENT_NOTIFY_PROVIDER=gemini
  result=$(echo '{"session_id":"x","cwd":"/tmp","transcript_path":"/tmp/t.json"}' \
    | ZELLIJ_SESSION_NAME=sess bash "$NOTIFY_SCRIPT" --notify-args-test gemini)
  assert_contains "gemini execute has provider env" "AGENT_NOTIFY_PROVIDER=gemini" "$result"

  # 10-3. Custom terminal passed through execute
  result=$(echo '{"session_id":"x","cwd":"/tmp"}' \
    | ZELLIJ_SESSION_NAME=sess AGENT_NOTIFY_TERMINAL=Ghostty bash "$NOTIFY_SCRIPT" --notify-args-test claude)
  assert_contains "execute has custom terminal" 'AGENT_NOTIFY_TERMINAL="Ghostty"' "$result"
fi

echo ""

# ===========================================================================
# 11. jq Graceful Degradation
# ===========================================================================

echo "=== 11. jq Graceful Degradation ==="

# 11-1. Simulate missing jq via _TEST_NO_JQ injection
result=$(echo '{"session_id":"abc","cwd":"/tmp"}' \
  | _TEST_NO_JQ=1 bash "$NOTIFY_SCRIPT" --parse-test claude)
# Should still get provider and fallback cwd (pwd), session=unknown
assert_contains "no jq: provider still set" "provider=claude" "$result"
assert_contains "no jq: session_id falls back to unknown" "session_id=unknown" "$result"

echo ""

# ===========================================================================
# 12. Exit Code
# ===========================================================================

echo "=== 12. Exit Code ==="

echo '{}' | AGENT_NOTIFY_DRY_RUN=1 bash "$NOTIFY_SCRIPT" claude >/dev/null
assert_eq "exit code is 0" "0" "$?"

echo '{"bad json' | AGENT_NOTIFY_DRY_RUN=1 bash "$NOTIFY_SCRIPT" claude 2>/dev/null >/dev/null
assert_eq "exit code is 0 even with bad json" "0" "$?"

echo ""

# ===========================================================================
# 13. Session Switch Strategy Router (agent-notify-open.sh)
# ===========================================================================

OPEN_SCRIPT="$SCRIPT_DIR/agent-notify-open.sh"

echo "=== 13. Session Switch Strategy Router ==="

# 13-1. Terminal detection: AGENT_NOTIFY_TERMINAL override
result=$(AGENT_NOTIFY_TERMINAL=WezTerm bash "$OPEN_SCRIPT" --detect-terminal-test)
assert_eq "detect: env override WezTerm" "terminal=wezterm" "$result"

result=$(AGENT_NOTIFY_TERMINAL=Ghostty bash "$OPEN_SCRIPT" --detect-terminal-test)
assert_eq "detect: env override Ghostty" "terminal=ghostty" "$result"

result=$(AGENT_NOTIFY_TERMINAL=iTerm2 bash "$OPEN_SCRIPT" --detect-terminal-test)
assert_eq "detect: env override unknown falls to generic" "terminal=iterm2" "$result"

# 13-2. Current session detection from WezTerm title
result=$(_TEST_NO_ZELLIJ=1 _TEST_WEZTERM_TITLE="tonys-nix | some task" bash "$OPEN_SCRIPT" --detect-session-test)
assert_eq "session detect: parses 'name | task'" "session=tonys-nix" "$result"

result=$(_TEST_NO_ZELLIJ=1 _TEST_WEZTERM_TITLE="valkey | ~/d/ossca" bash "$OPEN_SCRIPT" --detect-session-test)
assert_eq "session detect: parses 'valkey | path'" "session=valkey" "$result"

result=$(_TEST_NO_ZELLIJ=1 _TEST_WEZTERM_TITLE="" bash "$OPEN_SCRIPT" --detect-session-test)
assert_eq "session detect: empty title → unknown" "session=" "$result"

# 13-3. Strategy selection: WezTerm + target != current
result=$(AGENT_NOTIFY_TERMINAL=WezTerm _TEST_NO_ZELLIJ=1 _TEST_WEZTERM_TITLE="valkey | task" \
  _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --switch-test tonys-nix)
assert_contains "wezterm switch: strategy=fallback" "strategy=fallback" "$result"
assert_contains "wezterm switch: focuses only" "focus-only" "$result"
assert_contains "wezterm switch: target session" "tonys-nix" "$result"

# 13-4. Strategy selection: WezTerm + target == current → skip
result=$(AGENT_NOTIFY_TERMINAL=WezTerm _TEST_NO_ZELLIJ=1 _TEST_WEZTERM_TITLE="tonys-nix | task" \
  _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --switch-test tonys-nix)
assert_contains "wezterm same session: fallback" "strategy=fallback" "$result"

# 13-5. Strategy selection: WezTerm + no target → focus only
result=$(AGENT_NOTIFY_TERMINAL=WezTerm _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --switch-test "")
assert_contains "wezterm no target: focus-only" "focus-only" "$result"

# 13-6. Strategy selection: Ghostty + target
result=$(AGENT_NOTIFY_TERMINAL=Ghostty _TEST_NO_ZELLIJ=1 _TEST_WEZTERM_TITLE="" \
  _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --switch-test tonys-nix)
assert_contains "ghostty: strategy=ghostty" "strategy=ghostty" "$result"

# 13-7. Strategy selection: Unknown terminal → fallback
result=$(AGENT_NOTIFY_TERMINAL=iTerm2 _TEST_NO_ZELLIJ=1 _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --switch-test tonys-nix)
assert_contains "unknown terminal: strategy=fallback" "strategy=fallback" "$result"

# 13-8. Transcript gating: Claude opens, Gemini/Codex skip
result=$(AGENT_NOTIFY_PROVIDER=claude _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --transcript-test /tmp/t.jsonl)
assert_contains "claude: opens transcript" "open=true" "$result"

result=$(AGENT_NOTIFY_PROVIDER=gemini _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --transcript-test /tmp/t.jsonl)
assert_contains "gemini: skips transcript" "open=false" "$result"

result=$(AGENT_NOTIFY_PROVIDER=codex _TEST_DRY_RUN=1 bash "$OPEN_SCRIPT" --transcript-test /tmp/t.jsonl)
assert_contains "codex: skips transcript" "open=false" "$result"

echo ""

# ===========================================================================
# 14. Codex Stop Hook Timeout Guard
# ===========================================================================

echo "=== 14. Codex Stop Hook Timeout Guard ==="

start_ts=$(date +%s)
result=$(echo '{"session_id":"fast-1","cwd":"/workspace","last_assistant_message":"Done"}' \
  | AGENT_NOTIFY_DRY_RUN=1 ZELLIJ_SESSION_NAME=test bash "$NOTIFY_SCRIPT" codex 2>/dev/null)
elapsed=$(( $(date +%s) - start_ts ))
assert_eq "codex stop: stdout is immediate Stop JSON" '{"continue":true}' "$result"
TOTAL=$((TOTAL + 1))
if [[ $elapsed -le 2 ]]; then
  echo "  PASS: codex stop: dry-run avoids blocking focus checks (${elapsed}s)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: codex stop: dry-run took ${elapsed}s"
  FAIL=$((FAIL + 1))
fi

echo ""

# ===========================================================================
# Summary
# ===========================================================================

echo "==========================================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
