#!/usr/bin/env bash
# Fail closed when risk-bearing repository changes omit a PRD.
# The caller supplies changed paths on stdin or with --files.

set -euo pipefail

if [[ "${1:-}" == "--files" ]]; then
  changed=$(cat)
else
  echo "usage: $0 --files" >&2
  exit 2
fi

if [[ -z "$changed" ]]; then
  echo "PRD gate passed: no changed files"
  exit 0
fi

has_prd=false
risk=false
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  case "$path" in
    docs/agent/prd/*.md|docs/agent/prd/*/*.md) has_prd=true ;;
    nix/agents/*|nix/agents/providers/*|flake.nix|flake.lock|harness.py|runtime/*|scripts/*)
      risk=true ;;
  esac
done <<< "$changed"

if [[ "$risk" == true && "$has_prd" != true ]]; then
  echo "PRD gate failed: risk-bearing changes require a docs/agent/prd/*.md artifact" >&2
  printf '%s\n' "$changed" >&2
  exit 2
fi

if [[ "$risk" == true ]]; then
  echo "PRD gate passed: risk-bearing changes include a PRD"
else
  echo "PRD gate passed: no risk-bearing changes"
fi
