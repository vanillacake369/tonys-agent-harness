#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  echo 'usage: core-scenario.sh setup ROOT CATALOG | run BINARY ROOT' >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
action=$1
first=$2
second=$3

case "$action" in
setup)
  root=$first
  catalog=$second
  [[ "$root" == /* && ! -e "$root" ]] || usage
  [[ "$catalog" == /* && -f "$catalog" && ! -L "$catalog" ]] || usage
  mkdir -m 0700 "$root"
  mkdir -m 0700 "$root/home" "$root/repo" "$root/repo/core" "$root/repo/provider"
  printf 'synthetic core scenario\n' >"$root/repo/core/environment-public.txt"
  cp -- "$catalog" "$root/repo/provider/provider-catalog.json"
  ;;
run)
  binary=$first
  root=$second
  [[ "$binary" == /* && -f "$binary" && -x "$binary" ]] || usage
  [[ "$root" == /* && -d "$root/repo" && -d "$root/home" ]] || usage
  exec env -i \
    HOME="$root/home" \
    HARNESS_REPO="$root/repo" \
    HARNESS_STATE="$root/state" \
    HARNESS_VAULT="$root/vault/capability.enc" \
    HARNESS_AGE_KEY="$root/config/age.key" \
    "$binary"
  ;;
*) usage ;;
esac
