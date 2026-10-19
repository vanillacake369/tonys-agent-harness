#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

MODE="${1:-all}"

log() { printf '[a2a] %s\n' "$*"; }
pass() { printf '[a2a] PASS %s\n' "$*"; }
skip() { printf '[a2a] SKIP %s\n' "$*"; }
fail() { printf '[a2a] FAIL %s\n' "$*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

just_has() {
  has just && just --summary 2>/dev/null | tr ' ' '\n' | grep -qx "$1"
}

run_step() {
  local name="$1"
  shift
  log "START ${name}: $*"
  if "$@"; then
    pass "$name"
  else
    local status=$?
    fail "${name} (exit ${status})"
    return "$status"
  fi
}

run_nix_tool() {
  local tool="$1"
  shift
  if has "$tool"; then
    run_step "$tool" "$tool" "$@"
  elif has nix; then
    run_step "$tool" nix run "nixpkgs#${tool}" -- "$@"
  else
    skip "$tool: neither ${tool} nor nix is available"
  fi
}

run_format() {
  if [[ -f flake.nix ]] || find . -path ./.git -prune -o -name '*.nix' -print -quit | grep -q .; then
    run_nix_tool alejandra --check .
  else
    skip "format: no Nix files detected"
  fi
}

run_lint() {
  if [[ -f flake.nix ]] || find . -path ./.git -prune -o -name '*.nix' -print -quit | grep -q .; then
    run_nix_tool deadnix --fail .
    run_nix_tool statix check .
  elif just_has lint; then
    run_step "just lint" just lint
  else
    skip "lint: no supported lint command detected"
  fi
}

run_typecheck() {
  skip "typecheck: no dedicated repository typecheck command detected"
}

run_test() {
  if just_has test; then
    run_step "just test" just test
  elif has nix && [[ -f flake.nix ]]; then
    run_step "nix flake checks" nix flake check
  else
    skip "test: no supported test command detected"
  fi
}

usage() {
  cat <<'USAGE'
Usage: modules/agents/skills/a2a-workflow/scripts/verify.sh [all|format|lint|typecheck|test]

Runs only repository-supported validation steps. It does not install tools or run destructive commands.
USAGE
}

case "$MODE" in
  all)
    run_format
    run_lint
    run_typecheck
    run_test
    ;;
  format) run_format ;;
  lint) run_lint ;;
  typecheck) run_typecheck ;;
  test) run_test ;;
  -h|--help|help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
