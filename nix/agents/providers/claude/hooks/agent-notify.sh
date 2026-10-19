#!/usr/bin/env bash
# Unified agent attention notification script.
# Shared by Claude Code (Stop/AskUserQuestion), Codex (Stop), Gemini (AfterAgent).
#
# Usage:  echo '<hook-json>' | agent-notify.sh <provider>
# Env:    AGENT_NOTIFY_BACKEND  - force backend (terminal-notifier|noti|osascript|notify-send|bell)
#         AGENT_NOTIFY_DRY_RUN  - if set, print what would happen instead of sending
#         AGENT_NOTIFY_SUPPRESS_ATTENTION_WHEN_FOCUSED
#                                if set, focused sessions may suppress question/human alerts
#
# This script NEVER exits non-zero — hooks must not block the agent.
set -uo pipefail

MAX_MSG_LEN=60

# Global state (populated by _parse_input)
_PROVIDER="" _SESSION_ID="" _CWD="" _PROMPT="" _SUMMARY="" _TRANSCRIPT_PATH="" _QUESTION=""
# Global state (populated by _build_notify_args)
_TITLE="" _SUBTITLE="" _MESSAGE="" _GROUP="" _EXECUTE=""

# ===========================================================================
# Parse input (JSON via stdin or positional arguments)
# ===========================================================================
_parse_input() {
  _PROVIDER="${1:-agent}"
  local input
  input=$(cat 2>/dev/null || true)

  _SESSION_ID="unknown" _CWD="unknown" _PROMPT="" _SUMMARY="" _TRANSCRIPT_PATH="" _QUESTION=""

  if [[ -z "${_TEST_NO_JQ:-}" ]] && command -v jq &>/dev/null && [[ -n "$input" ]]; then
    local parsed
    if parsed=$(jq -r '
      def sh($value; $fallback): (($value // $fallback) | tostring | @sh);
      def first_question:
        if (.tool_input.questions | type) == "array" then
          (.tool_input.questions[0].question // "")
        else
          ""
        end;
      [
        "_SESSION_ID=" + sh(.session_id; "unknown"),
        "_CWD=" + sh(.cwd; "unknown"),
        "_PROMPT=" + sh(.prompt; ""),
        "_SUMMARY=" + sh((.prompt_response // .last_assistant_message); ""),
        "_TRANSCRIPT_PATH=" + sh(.transcript_path; ""),
        "_QUESTION=" + sh(first_question; "")
      ] | .[]
    ' <<< "$input" 2>/dev/null); then
      eval "$parsed"
      return
    fi
  fi

  # Fallback to positional arguments if stdin is empty or not JSON.
  _PROMPT="${2:-}"
  _SUMMARY="${3:-}"
  if [[ -n "$_PROMPT" || -n "$_SUMMARY" ]]; then
    _CWD="$(pwd)"
    _SESSION_ID="${ZELLIJ_SESSION_NAME:-unknown}"
  fi
}

_print_parsed() {
  echo "provider=$_PROVIDER"
  echo "session_id=$_SESSION_ID"
  echo "cwd=$_CWD"
  echo "prompt=$_PROMPT"
  echo "summary=$_SUMMARY"
  echo "transcript_path=$_TRANSCRIPT_PATH"
  echo "question=$_QUESTION"
}

# ===========================================================================
# Truncate string to max length, append ... if truncated
# ===========================================================================
_truncate() {
  local str="$1" max="${2:-$MAX_MSG_LEN}"
  if [[ ${#str} -le $max ]]; then
    echo "$str"
  else
    echo "${str:0:$((max - 3))}..."
  fi
}

_basename() {
  local path="${1%/}"
  [[ -n "$path" ]] || path="$1"
  printf '%s\n' "${path##*/}"
}

# ===========================================================================
# Build notification args → globals
# ===========================================================================
_build_notify_args() {
  local icon="" sound="default"
  if [[ -n "$_QUESTION" ]]; then
    # AskUserQuestion: agent is BLOCKED waiting for the user to answer
    icon="❓ "
    sound="Submarine"
    _TITLE="${icon}Claude asks"
  elif [[ "$_PROVIDER" == "human" ]]; then
    icon="🔴 "
    sound="Basso"
    _TITLE="${icon}[HUMAN REQUIRED]"
  else
    _TITLE="$(echo "${_PROVIDER:0:1}" | tr '[:lower:]' '[:upper:]')${_PROVIDER:1}"
  fi

  _SUBTITLE="$(_basename "$_CWD")"
  _GROUP="${_PROVIDER}-${_SESSION_ID}"

  if [[ -n "$_QUESTION" ]]; then
    # Question takes priority: subtitle stays project dir, message=the question
    _MESSAGE=$(_truncate "$_QUESTION")
  elif [[ -n "$_PROMPT" && -n "$_SUMMARY" ]]; then
    # Both available: subtitle=prompt (what was asked), message=summary (what was done)
    _SUBTITLE=$(_truncate "$_PROMPT")
    _MESSAGE=$(_truncate "$_SUMMARY")
  elif [[ -n "$_PROMPT" ]]; then
    _MESSAGE=$(_truncate "$_PROMPT")
  elif [[ -n "$_SUMMARY" ]]; then
    _MESSAGE=$(_truncate "$_SUMMARY")
  else
    _MESSAGE="Session ${_SESSION_ID:0:8} completed"
  fi

  _EXECUTE=""
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$(uname)" == "Darwin" ]]; then
    local args=()
    local zj_session="${ZELLIJ_SESSION_NAME:-}"
    [[ -n "$zj_session" ]] && args+=("$zj_session")
    [[ -n "$_TRANSCRIPT_PATH" ]] && args+=("$_TRANSCRIPT_PATH")
    # Pass provider and terminal via env so open script can decide behavior.
    # We use 'env' to ensure variables are set correctly even if not run in a full shell.
    local term="${AGENT_NOTIFY_TERMINAL:-WezTerm}"
    _EXECUTE="env AGENT_NOTIFY_PROVIDER=$_PROVIDER AGENT_NOTIFY_TERMINAL=\"$term\" ${script_dir}/agent-notify-open.sh${args:+ ${args[*]}}"
  fi

  _NOTIFY_SOUND="$sound"
}

_print_notify_args() {
  echo "title=$_TITLE"
  echo "subtitle=$_SUBTITLE"
  echo "group=$_GROUP"
  echo "message=$_MESSAGE"
  echo "execute=$_EXECUTE"
}

_print_codex_stop_json() {
  printf '{"continue":true}\n'
}

# ===========================================================================
# Select notification backend
# macOS: terminal-notifier (own app) > noti > osascript > bell
# Linux: noti > notify-send > bell
# Note: osascript/noti on macOS inherit parent app's notification permission.
#       WezTerm is not in macOS notification settings, so they fail silently.
#       terminal-notifier registers as its own app and bypasses this.
# ===========================================================================
_select_backend() {
  if [[ -n "${AGENT_NOTIFY_BACKEND:-}" ]]; then
    echo "${AGENT_NOTIFY_BACKEND}"
    return
  fi

  if [[ "$(uname)" == "Darwin" ]]; then
    if command -v terminal-notifier &>/dev/null; then
      echo "terminal-notifier"
    elif command -v noti &>/dev/null; then
      echo "noti"
    elif command -v osascript &>/dev/null; then
      echo "osascript"
    else
      echo "bell"
    fi
  else
    if command -v noti &>/dev/null; then
      echo "noti"
    elif command -v notify-send &>/dev/null; then
      echo "notify-send"
    else
      echo "bell"
    fi
  fi
}

# ===========================================================================
# Check if the current session is being viewed by the user.
# Hybrid approach:
#   1. macOS: check if terminal app is the frontmost process (OS-level focus)
#   2. Zellij: check if session has attached clients (pane-level)
#   Both must be true to suppress notification.
# Env: _TEST_CLIENT_COUNT - inject zellij client count for testing
#      _TEST_FOCUSED_APP  - inject frontmost app name for testing
#      AGENT_NOTIFY_TERMINAL - terminal app name (default: WezTerm)
# ===========================================================================
_is_session_focused() {
  # Not in zellij → can't detect pane, always notify
  [[ -n "${ZELLIJ_SESSION_NAME:-}" ]] || return 1

  # Step 1: OS-level focus check (macOS only)
  if [[ "$(uname)" == "Darwin" ]]; then
    local terminal_app="${AGENT_NOTIFY_TERMINAL:-WezTerm}"
    local focused_app="${_TEST_FOCUSED_APP:-}"
    if [[ -z "$focused_app" ]]; then
      focused_app=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)
    fi

    # If we couldn't get the focused app, assume not focused to be safe
    [[ -n "$focused_app" ]] || return 1

    if [[ -n "${AGENT_NOTIFY_TERMINAL:-}" ]]; then
      [[ "$focused_app" == "$terminal_app" ]] || return 1
    else
      # Check if the focused app is a terminal.
      case "$focused_app" in
        "WezTerm" | "wezterm-gui" | "iTerm2" | "Alacritty" | "Terminal" | "Ghostty" | "warp")
          ;;
        *)
          return 1 # Not focused on terminal → notify
          ;;
      esac
    fi
  fi

  if [[ -n "${_TEST_CLIENT_COUNT:-}" ]]; then
    [[ "$_TEST_CLIENT_COUNT" -gt 0 ]]
    return
  fi

  # Step 2: Zellij client check (is any client focusing the current pane?)
  local current_pane="${ZELLIJ_PANE_ID:-}"
  if [[ -n "$current_pane" ]]; then
    local clients_output
    clients_output=$(zellij action list-clients 2>/dev/null || true)
    if [[ -n "$clients_output" ]]; then
      # Check if any client is looking at our pane.
      # list-clients output columns: CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND
      if echo "$clients_output" | tail -n +2 | awk '{print $2}' | grep -qE "^(terminal_)?${current_pane}$"; then
        return 0 # Focused
      fi
      return 1 # Current pane is not focused by any client
    fi
  fi

  # Fallback for Step 2 if zellij command fails or PANE_ID is missing
  local count
  count=$(zellij action list-clients 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  [[ "$count" -gt 0 ]]
}

_is_attention_required() {
  [[ -n "$_QUESTION" || "$_PROVIDER" == "human" ]]
}

_should_skip_notification() {
  if _is_attention_required && [[ -z "${AGENT_NOTIFY_SUPPRESS_ATTENTION_WHEN_FOCUSED:-}" ]]; then
    return 1
  fi

  _is_session_focused
}

# ===========================================================================
# Send notification
# ===========================================================================
_send() {
  local backend="$1"

  case "$backend" in
    terminal-notifier)
      local cmd=(terminal-notifier
        -title "$_TITLE" -subtitle "$_SUBTITLE"
        -message "$_MESSAGE" -group "$_GROUP" -sound "$_NOTIFY_SOUND")
      [[ -n "$_EXECUTE" ]] && cmd+=(-execute "$_EXECUTE")
      if ! "${cmd[@]}" 2>/dev/null; then
        # Fallback to osascript if terminal-notifier fails
        _send "osascript"
      fi
      ;;
    noti)
      noti -t "$_TITLE" -m "${_SUBTITLE}: ${_MESSAGE}" 2>/dev/null || _send "osascript"
      ;;
    osascript)
      osascript -e "display notification \"${_MESSAGE}\" with title \"${_TITLE}\" subtitle \"${_SUBTITLE}\" sound name \"Glass\"" 2>/dev/null || true
      ;;
    notify-send)
      notify-send "$_TITLE" "${_SUBTITLE}: ${_MESSAGE}" 2>/dev/null || true
      ;;
    bell)
      printf '\a' 2>/dev/null || true
      ;;
  esac
}

# ===========================================================================
# Test modes (invoked by test harness)
# ===========================================================================
case "${1:-}" in
  --parse-test)
    _parse_input "${2:-agent}"; _print_parsed; exit 0 ;;
  --notify-args-test)
    _parse_input "${2:-agent}"; _build_notify_args; _print_notify_args; exit 0 ;;
  --backend-test)
    echo "backend=$(_select_backend)"; exit 0 ;;
esac

# ===========================================================================
# Log notification to file
# Env: AGENT_NOTIFY_LOG - path to log file (default: ~/.agent-notify.log)
# ===========================================================================
_log_notification() {
  local log_file="${AGENT_NOTIFY_LOG:-$HOME/.agent-notify.log}"
  local ts kind
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  kind="completion"
  [[ -n "$_QUESTION" ]] && kind="question"
  [[ "$_PROVIDER" == "human" ]] && kind="human-required"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "$_PROVIDER" "$kind" "$(_basename "$_CWD")" "$_PROMPT" "$_SUMMARY" "$_QUESTION" \
    >> "$log_file" 2>/dev/null || true
}

_codex_notify_background() {
  (
    local backend
    backend=$(_select_backend)

    if _should_skip_notification; then
      exit 0
    fi

    _log_notification
    _send "$backend" >/dev/null
  ) >/dev/null 2>&1 &
}

# ===========================================================================
# Main
# ===========================================================================
main() {
  _parse_input "${1:-agent}"
  _build_notify_args

  if [[ "$_PROVIDER" == "codex" ]]; then
    if [[ -n "${AGENT_NOTIFY_DRY_RUN:-}" ]]; then
      _print_notify_args >&2
      echo "backend=$(_select_backend)" >&2
      _print_codex_stop_json
      exit 0
    fi

    _print_codex_stop_json
    _codex_notify_background
    exit 0
  fi

  local backend
  backend=$(_select_backend)

  if [[ -n "${AGENT_NOTIFY_DRY_RUN:-}" ]]; then
    if _should_skip_notification; then
      echo "skipped (terminal focused)"
    else
      _log_notification
      _print_notify_args
      echo "backend=$backend"
    fi
    exit 0
  fi

  if _should_skip_notification; then
    exit 0
  fi
  _log_notification
  _send "$backend"
}

main "$@" || exit 0
