#!/usr/bin/env bash
# Constrained, read-only Git evidence observation. No arbitrary Git arguments.
set -euo pipefail

emit_failure() {
  local status=$1
  printf '{"tool":"tool-git-evidence","status":"%s","network":"DENIED","writes":false}\n' "$status"
  exit 2
}

safe_git() {
  local git_bin
  git_bin=$(command -v git) || return 127
  env -i PATH=/usr/bin:/bin GIT_OPTIONAL_LOCKS=0 GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    GIT_NO_LAZY_FETCH=1 "$git_bin" "$@"
}

repo=
path=
while (($#)); do
  case $1 in
    --repo)
      (($# >= 2)) || emit_failure INVALID_INPUT
      repo=$2
      shift 2
      ;;
    --path)
      (($# >= 2)) || emit_failure INVALID_INPUT
      path=$2
      shift 2
      ;;
    *) emit_failure INVALID_INPUT ;;
  esac
done

test "$repo" = . && test -n "$path" || emit_failure INVALID_INPUT
[[ "$path" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || emit_failure INVALID_INPUT
[[ "$path" != /* && ! "$path" =~ (^|/)\.\.?(/|$) ]] || emit_failure INVALID_INPUT

test -e .git && test ! -L .git || emit_failure UNAVAILABLE
working_dir=$(pwd -P)
inside=$(safe_git -C . rev-parse --is-inside-work-tree 2>/dev/null) || emit_failure UNAVAILABLE
test "$inside" = true || emit_failure UNAVAILABLE
repo_root=$(safe_git -C . rev-parse --show-toplevel 2>/dev/null) || emit_failure UNAVAILABLE
test "$repo_root" = "$working_dir" || emit_failure INVALID_INPUT

head=$(safe_git -C . rev-parse HEAD 2>/dev/null) || emit_failure UNAVAILABLE
[[ "$head" =~ ^[0-9a-f]{40,64}$ ]] || emit_failure UNKNOWN
tracked_path=$(safe_git -C . ls-files --error-unmatch -- "$path" 2>/dev/null) || emit_failure INVALID_INPUT
test "$tracked_path" = "$path" || emit_failure INVALID_INPUT
path_revision=$(safe_git -C . log -1 --format=%H -- "$path" 2>/dev/null) || emit_failure UNAVAILABLE
[[ "$path_revision" =~ ^[0-9a-f]{40,64}$ ]] || emit_failure UNKNOWN

dirty=false
diff_rc=0
safe_git -C . diff --quiet -- 2>/dev/null || diff_rc=$?
case "$diff_rc" in 0) ;; 1) dirty=true ;; *) emit_failure UNAVAILABLE ;; esac
diff_rc=0
safe_git -C . diff --cached --quiet -- 2>/dev/null || diff_rc=$?
case "$diff_rc" in 0) ;; 1) dirty=true ;; *) emit_failure UNAVAILABLE ;; esac

printf '{"tool":"tool-git-evidence","status":"OK","repository":".","path":"%s","head":"%s","path_revision":"%s","worktree_dirty":%s,"network":"DENIED","writes":false}\n' \
  "$path" "$head" "$path_revision" "$dirty"
