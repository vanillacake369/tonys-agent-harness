#!/bin/sh
set -eu

fail() {
  printf 'worktree: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 1 ] || fail 'usage: just worktree NAME'
name=$1
case "$name" in
  ''|[!a-z0-9]*|*[!a-z0-9-]*) fail 'use a single name with lowercase letters, digits and hyphens' ;;
esac

checkout=$(cd "$(dirname "$0")/.." && pwd -P)
common=$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir)
[ "${common##*/}" = .git ] || fail 'expected the main checkout to own the common .git directory'
primary=$(cd "${common%/*}" && pwd -P)
target="${primary%/*}/$name"
branch="codex/$name"

# Reserve the name so even an empty pre-existing path is left alone.
mkdir "$target" || fail 'destination already exists or cannot be created'
if ! git -C "$primary" -c core.hooksPath=/dev/null worktree add -b "$branch" "$target" refs/heads/main >&2; then
  rmdir "$target" 2>/dev/null || true
  fail 'worktree creation failed'
fi
printf '%s\n' "$target"
