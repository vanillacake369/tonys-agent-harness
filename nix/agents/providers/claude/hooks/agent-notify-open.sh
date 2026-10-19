#!/usr/bin/env bash
# Called by terminal-notifier -execute on notification click
# Usage: agent-notify-open.sh [zellij_session_name] [transcript_path]
# Focuses terminal, switches zellij sessions via strategy router, opens transcript.
#
# Strategy Router: detects terminal type (wezterm|ghostty|*) and dispatches
# to the appropriate session-switch implementation.
#
# Note: terminal-notifier -execute runs with minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin).
# Nix binaries are not available, so we prepend ~/.nix-profile/bin.
#
# Env: AGENT_NOTIFY_TERMINAL  - terminal app name (WezTerm|Ghostty|...)
#      AGENT_NOTIFY_PROVIDER  - agent provider (claude|gemini|codex)
#      _TEST_DRY_RUN          - if set, don't execute side effects
#      _TEST_WEZTERM_TITLE    - inject WezTerm pane title for testing
set -uo pipefail

export PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"

_has_zellij() {
    [[ -z "${_TEST_NO_ZELLIJ:-}" ]] && command -v zellij &>/dev/null
}

# ===========================================================================
# Terminal Detection (SSoT)
# Normalizes AGENT_NOTIFY_TERMINAL to lowercase identifier.
# ===========================================================================
_detect_terminal() {
    local raw="${AGENT_NOTIFY_TERMINAL:-}"
    # Normalize: lowercase, strip whitespace
    local term
    term=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    # Map known names
    case "$term" in
    wezterm | wezterm-gui) echo "wezterm" ;;
    ghostty) echo "ghostty" ;;
    "") echo "unknown" ;;
    *) echo "$term" ;;
    esac
}

# ===========================================================================
# Detect current zellij session via zellij list-sessions (socket IPC)
# Fallback: parse WezTerm pane title
# ===========================================================================
_detect_current_session() {
    # Primary: zellij list-sessions (works from outside zellij too)
    if _has_zellij; then
        local session
        session=$(zellij list-sessions 2>/dev/null | grep '(current)' | sed -E 's/\x1b\[[0-9;]*m//g; s/ .*//' || true)
        if [[ -n "$session" ]]; then
            echo "$session"
            return
        fi
    fi
    # Fallback: WezTerm pane title parsing
    local title="${_TEST_WEZTERM_TITLE-__unset__}"
    if [[ "$title" == "__unset__" ]] && command -v wezterm &>/dev/null; then
        title=$(wezterm cli list --format json 2>/dev/null |
            python3 -c "
import sys,json
for p in json.load(sys.stdin):
    print(p.get('title','')); break
" 2>/dev/null || true)
    fi
    local parsed=""
    if [[ -n "${title:-}" ]]; then
        parsed=$(echo "$title" | sed -E 's/ [|] .*//;s/ - .*//' | tr -d '[:space:]' | head -1)
    fi
    echo "$parsed"
}

# ===========================================================================
# Focus terminal app (platform-specific)
# ===========================================================================
_focus_terminal() {
    local app="${AGENT_NOTIFY_TERMINAL:-WezTerm}"
    if [[ -z "${_TEST_DRY_RUN:-}" ]]; then
        open -a "$app" 2>/dev/null || true
    fi
}

# ===========================================================================
# Strategy: Zellij IPC (terminal-agnostic)
# Uses `zellij --session <current> action switch-session <target>` to switch
# via zellij's Unix socket. Safe regardless of pane state (nvim, agent, etc).
# ===========================================================================
_switch_zellij_ipc() {
    local target="$1"
    local current
    current=$(_detect_current_session)

    if [[ -z "$current" ]]; then
        echo "action=focus-only reason=no-current-session"
        return 0
    fi

    if [[ "$current" == "$target" ]]; then
        echo "action=skip reason=already-on-target"
        return 0
    fi

    echo "action=zellij-ipc current=$current target=$target"
    if [[ -z "${_TEST_DRY_RUN:-}" ]]; then
        zellij --session "$current" action switch-session "$target" 2>/dev/null || true
    fi
}

# ===========================================================================
# Strategy: Ghostty
# Placeholder for future libghostty / Ghostty CLI integration.
# ===========================================================================
_switch_ghostty() {
    local target="$1"
    # TODO: implement Ghostty-specific session switch when API is available
    echo "action=focus-only reason=ghostty-not-yet-implemented target=$target"
}

# ===========================================================================
# Strategy: Fallback (unknown terminal)
# Just focus the terminal; user switches manually.
# ===========================================================================
_switch_fallback() {
    local target="$1"
    echo "action=focus-only reason=unknown-terminal target=$target"
}

# ===========================================================================
# Strategy Router: zellij IPC first, terminal-specific fallback
# ===========================================================================
_switch_session() {
    local target="$1"

    if [[ -z "$target" ]]; then
        echo "strategy=none action=focus-only reason=no-target"
        return 0
    fi

    # Primary: zellij socket IPC (terminal-agnostic, pane-state-safe)
    if _has_zellij; then
        echo "strategy=zellij-ipc"
        _switch_zellij_ipc "$target"
        return $?
    fi

    # Fallback: terminal-specific strategies
    local terminal
    terminal=$(_detect_terminal)

    case "$terminal" in
    ghostty)
        echo "strategy=ghostty"
        _switch_ghostty "$target"
        ;;
    *)
        echo "strategy=fallback"
        _switch_fallback "$target"
        ;;
    esac
}

# ===========================================================================
# Transcript opening (provider-gated)
# ===========================================================================
_should_open_transcript() {
    local provider="${AGENT_NOTIFY_PROVIDER:-}"
    local path="$1"
    [[ -n "$path" && "$provider" != "gemini" && "$provider" != "codex" ]]
}

_open_transcript() {
    local path="$1"
    if _should_open_transcript "$path"; then
        if [[ -z "${_TEST_DRY_RUN:-}" ]]; then
            open "$path" 2>/dev/null || true
        fi
        echo "open=true"
    else
        echo "open=false"
    fi
}

# ===========================================================================
# Test modes (invoked by test harness)
# ===========================================================================
case "${1:-}" in
--detect-terminal-test)
    echo "terminal=$(_detect_terminal)"
    exit 0
    ;;
--detect-session-test)
    echo "session=$(_detect_current_session)"
    exit 0
    ;;
--switch-test)
    _switch_session "${2:-}"
    exit 0
    ;;
--transcript-test)
    _open_transcript "${2:-}"
    exit 0
    ;;
esac

# ===========================================================================
# Main
# ===========================================================================
PROVIDER="${AGENT_NOTIFY_PROVIDER:-}"
TARGET="" TRANSCRIPT=""

# Parse args: first non-file arg is zellij session, file arg is transcript
for arg in "$@"; do
    if [[ -f "$arg" ]]; then
        TRANSCRIPT="$arg"
    elif [[ -z "$TARGET" ]]; then
        TARGET="$arg"
    fi
done

_focus_terminal
_switch_session "$TARGET" >/dev/null
sleep 0.1
if _should_open_transcript "$TRANSCRIPT"; then
    open "$TRANSCRIPT" 2>/dev/null || true
fi
