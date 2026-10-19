#!/usr/bin/env bash
# Claude Code status line hook
# Adaptive layout: single line when terminal is wide, multi-line when narrow.
#
# Input: JSON via stdin from Claude Code (includes `columns` field)
# This hook never exits non-zero — it must not block the agent.

set -uo pipefail

# ANSI colors
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# ===========================================================================
# JSON parsing
# ===========================================================================
INPUT=$(cat 2>/dev/null || true)

_jq() { echo "$INPUT" | jq -r "${1}" 2>/dev/null || true; }

# ===========================================================================
# Data extraction (single parse, SSOT)
# ===========================================================================
_extract_data() {
  MODEL=$(_jq '.model.display_name // "Claude"')
  CURRENT_DIR=$(_jq '.workspace.current_dir // ""')
  USED_PCT=$(_jq '.context_window.used_percentage // 0')
  SESSION_ID=$(_jq '.session_id // "default"')
  AGENT_NAME=$(_jq '.agent.name // ""')
  COLUMNS=$(_jq '.columns // 80')
}

# ===========================================================================
# Git info (cached, DRY — single source for branch/staged/modified)
# ===========================================================================
_get_git_info() {
  local dir="${1:-$(pwd)}"
  git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null || return

  local branch staged modified
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$dir" rev-parse --short HEAD 2>/dev/null \
    || echo "HEAD")
  staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git -C "$dir" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  echo "${branch}|${staged}|${modified}"
}

_cached_git_info() {
  local cache_dir="${TMPDIR:-/tmp}/claude-statusline"
  mkdir -p "$cache_dir"
  local cache_file="$cache_dir/${SESSION_ID//[^a-zA-Z0-9_-]/_}.cache"
  local now
  now=$(date +%s)

  local mtime
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime=$(stat -f %m "$cache_file" 2>/dev/null || echo 0)
  else
    mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
  fi

  if [[ $((now - mtime)) -gt 5 ]]; then
    _get_git_info "${CURRENT_DIR:-$(pwd)}" > "$cache_file"
  fi
  cat "$cache_file" 2>/dev/null || true
}

# ===========================================================================
# Segment builders (SRP — each returns one decorated string)
# ===========================================================================
_seg_model()   { echo "[${MODEL}]"; }
_seg_dir()     { [[ -n "$CURRENT_DIR" ]] && echo "📁 $(basename "$CURRENT_DIR")"; }
_seg_session() { echo "🔑 ${SESSION_ID:0:8}"; }
_seg_agent()   { [[ -n "$AGENT_NAME" ]] && echo "🤖 ${AGENT_NAME}"; }

_seg_git() {
  local data="$1"
  [[ -z "$data" ]] && return
  local branch staged modified
  IFS='|' read -r branch staged modified <<< "$data"
  local parts="🌿 ${branch}"
  [[ "$staged" -gt 0 ]]   && parts+=" ${GREEN}+${staged}${RESET}"
  [[ "$modified" -gt 0 ]] && parts+=" ${YELLOW}~${modified}${RESET}"
  echo "$parts"
}

_seg_progress_bar() {
  local used_int=${USED_PCT%.*}
  used_int=${used_int:-0}
  local filled=$(( (used_int * 10 + 50) / 100 ))
  [[ $filled -gt 10 ]] && filled=10
  [[ $filled -lt 0 ]]  && filled=0
  local empty=$(( 10 - filled ))

  local color="$GREEN"
  [[ $used_int -ge 70 ]] && color="$YELLOW"
  [[ $used_int -ge 90 ]] && color="$RED"

  local bar_filled bar_empty
  bar_filled=$(printf '█%.0s' $(seq 1 "$filled") 2>/dev/null || true)
  bar_empty=$(printf '░%.0s' $(seq 1 "$empty") 2>/dev/null || true)
  echo "${color}${bar_filled}${bar_empty}${RESET} ${used_int}%"
}


# ===========================================================================
# Visible length (strip ANSI escape codes + account for emoji width)
# ===========================================================================
_visible_len() {
  local stripped
  stripped=$(printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*m//g')
  # wc -m counts unicode chars; add 1 per 4-byte char (emoji = 2 cols, counted as 1)
  local chars bytes extra
  chars=$(printf '%s' "$stripped" | wc -m | tr -d ' ')
  bytes=$(printf '%s' "$stripped" | wc -c | tr -d ' ')
  # 4-byte UTF-8 sequences are emoji (2 display cols, wc -m counts as 1)
  # Approximate: extra_width = (bytes - chars) / 3 for 4-byte seqs
  extra=$(( (bytes - chars) / 3 ))
  echo $(( chars + extra ))
}

# ===========================================================================
# Layout: join segments with separator, respecting width
# ===========================================================================
_join_segments() {
  local sep=" ${DIM}|${RESET} "
  local result=""
  local first=true
  for seg in "$@"; do
    [[ -z "$seg" ]] && continue
    if [[ "$first" == "true" ]]; then
      result="$seg"
      first=false
    else
      result+="${sep}${seg}"
    fi
  done
  echo "$result"
}

_render() {
  local git_data
  git_data=$(_cached_git_info)

  # Build all segments
  local s_model s_dir s_git s_agent s_bar s_cost s_elapsed s_session
  s_model=$(_seg_model)
  s_dir=$(_seg_dir)
  s_git=$(_seg_git "$git_data")
  s_agent=$(_seg_agent)
  s_bar=$(_seg_progress_bar)
  s_session=$(_seg_session)

  # Try single line
  local single
  single=$(_join_segments "$s_model" "$s_dir" "$s_git" "$s_agent" "$s_bar" "$s_session")
  local single_len
  single_len=$(_visible_len "$single")

  if [[ "$single_len" -le "$COLUMNS" ]]; then
    printf '%b\n' "$single"
    return
  fi

  # Try 2 lines: identity | metrics
  local line1 line2
  line1=$(_join_segments "$s_model" "$s_dir" "$s_git" "$s_agent")
  line2=$(_join_segments "$s_bar" "$s_session")
  local line1_len
  line1_len=$(_visible_len "$line1")

  if [[ "$line1_len" -le "$COLUMNS" ]]; then
    printf '%b\n%b\n' "$line1" "$line2"
    return
  fi

  # Narrow terminal (< ~60 cols): 3 lines
  local line_a line_b line_c
  line_a=$(_join_segments "$s_model" "$s_dir")
  line_b=$(_join_segments "$s_git" "$s_agent")
  line_c=$(_join_segments "$s_bar" "$s_session")
  printf '%b\n%b\n%b\n' "$line_a" "$line_b" "$line_c"
}

# ===========================================================================
# Main
# ===========================================================================
_extract_data
_render
