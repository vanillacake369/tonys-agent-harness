#!/usr/bin/env bash
# Enforce Git lifecycle evidence without mutating the repository.

set -euo pipefail

REPO=.
MODE=code
SCOPE=
EVIDENCE=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO=$2; shift 2 ;;
    --mode) MODE=$2; shift 2 ;;
    --scope) SCOPE=$2; shift 2 ;;
    --evidence) EVIDENCE=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$MODE" != "code" && "$MODE" != "design" ]] || ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "invalid git lifecycle input" >&2
  exit 2
fi

status=$(git -C "$REPO" status --porcelain)
if [[ "$MODE" == "design" ]]; then
  echo "git lifecycle passed: design work uses non-code completion policy"
  exit 0
fi

if [[ -n "$status" ]]; then
  echo "git lifecycle blocked: uncommitted files remain" >&2
  printf '%s\n' "$status" >&2
  exit 2
fi
if [[ -z "$SCOPE" || -z "$EVIDENCE" || ! -f "$SCOPE" || ! -f "$EVIDENCE" ]]; then
  echo "git lifecycle blocked: scope and evidence are required" >&2
  exit 2
fi

commit=$(jq -r '.commit // ""' "$EVIDENCE")
baseline=$(jq -r '.baseline_commit // ""' "$EVIDENCE")
if ! jq -e '.changed_files | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' "$EVIDENCE" >/dev/null; then
  echo "git lifecycle blocked: changed_files evidence required" >&2; exit 2
fi
if [[ -z "$baseline" ]] || ! git -C "$REPO" merge-base --is-ancestor "$baseline" "$commit" 2>/dev/null; then
  echo "git lifecycle blocked: valid baseline_commit ancestor required" >&2
  exit 2
fi
if [[ -z "$commit" ]] || ! git -C "$REPO" cat-file -e "$commit^{commit}" 2>/dev/null; then
  echo "git lifecycle blocked: evidence does not reference a commit" >&2
  exit 2
fi
if [[ "$(git -C "$REPO" rev-parse "$commit^{commit}")" != "$(git -C "$REPO" rev-parse HEAD)" ]]; then
  echo "git lifecycle blocked: evidence commit must match HEAD" >&2
  exit 2
fi

while IFS= read -r changed; do
  [[ -n "$changed" ]] || continue
  if ! git -C "$REPO" diff --name-only "$baseline" "$commit" | grep -Fxq "$changed"; then
    echo "git lifecycle blocked: evidence file is not present in referenced commit: $changed" >&2
    exit 2
  fi
done < <(jq -r '.changed_files[]? // empty' "$EVIDENCE")

while IFS= read -r changed; do
  [[ -n "$changed" ]] || continue
  if ! grep -Fxq "$changed" "$SCOPE"; then
    echo "git lifecycle blocked: commit file outside scope: $changed" >&2
    exit 2
  fi
done < <(git -C "$REPO" diff --name-only "$baseline" "$commit")

echo "git lifecycle passed: clean tree, scoped commit, and evidence are linked"
