#!/usr/bin/env bats

setup() {
  test_root=$(mktemp -d "${TMPDIR:-/tmp}/harness-core-bats.XXXXXX")
  test_root=$(cd "$test_root" && pwd -P)
  fixture="$test_root/fixture"
  scenario="$BATS_TEST_DIRNAME/core-scenario.sh"
  catalog="$BATS_TEST_DIRNAME/../provider/provider-catalog.json"
}

teardown() {
  rm -rf -- "$test_root"
}

@test "setup creates only a synthetic public fixture" {
  run bash "$scenario" setup "$fixture" "$catalog"
  [ "$status" -eq 0 ]
  [ -f "$fixture/repo/core/environment-public.txt" ]
  [ -f "$fixture/repo/provider/provider-catalog.json" ]
  [ ! -e "$fixture/state" ]
  [ ! -e "$fixture/vault" ]
  [ ! -e "$fixture/config" ]
}

@test "setup refuses to overwrite an existing target" {
  mkdir -p "$fixture"
  printf 'keep\n' >"$fixture/marker"
  run bash "$scenario" setup "$fixture" "$catalog"
  [ "$status" -eq 2 ]
  [ "$(cat "$fixture/marker")" = keep ]
}

@test "run executes the read-only core status scenario" {
  [ -n "${HARNESS_CORE_BIN:-}" ]
  run bash "$scenario" setup "$fixture" "$catalog"
  [ "$status" -eq 0 ]

  run bash "$scenario" run "$HARNESS_CORE_BIN" "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"provider=codex status=DISABLED"* ]]
  [[ "$output" == *"Next: harness config init PATH or empty"* ]]
  [ ! -e "$fixture/state" ]
}

@test "Taskfile exposes one portable core gate" {
  run task --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"core:"* ]]
  [[ "$output" == *"portable core unit, integration, scenario, Nix, and performance checks"* ]]
}

@test "full gate scans Git history before public release" {
  run grep -F 'gitleaks dir --no-banner --redact --exit-code 1 .' "$BATS_TEST_DIRNAME/check-all.sh"
  [ "$status" -eq 0 ]
  run grep -F 'gitleaks git --no-banner --redact --exit-code 1 .' "$BATS_TEST_DIRNAME/check-all.sh"
  [ "$status" -eq 0 ]
}

@test "core gate evaluates Nix only from the public snapshot" {
  mock_bin="$test_root/bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$PWD" != "$HARNESS_SOURCE_REPO" ]]
[[ -f core/cli-blackbox_test.go ]]
[[ -f core/scenario-status.txtar ]]
[[ -f dev/core-scenario.sh ]]
case "$1" in
flake) [[ "$2" == check && "$3" == --no-update-lock-file && "$4" == path:* ]] ;;
develop) [[ "$2" == --no-update-lock-file && "$3" == path:* ]] ;;
*) exit 2 ;;
esac
SH
  chmod 0700 "$mock_bin/nix"

  run env HARNESS_SOURCE_REPO="$BATS_TEST_DIRNAME/.." PATH="$mock_bin:$PATH" \
    bash "$BATS_TEST_DIRNAME/environment-run.sh" core
  [ "$status" -eq 0 ]
}

@test "bootstrap recomputes the vendor hash instead of reusing a stale fixed output" {
  repo="$test_root/repo"
  mock_bin="$test_root/bin"
  mkdir -p "$repo" "$mock_bin"
  while IFS= read -r name; do
    mkdir -p "$repo/$(dirname "$name")"
    cp "$BATS_TEST_DIRNAME/../$name" "$repo/$name"
  done <"$BATS_TEST_DIRNAME/../core/environment-public.txt"

  cat >"$mock_bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
"flake lock") exit 0 ;;
"build --no-link")
  if [[ ! -e "$MOCK_STATE" ]]; then
    grep -Fx 'sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' dev/vendor-hash.txt
    : >"$MOCK_STATE"
    echo '       got:    sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' >&2
    exit 1
  fi
  grep -Fx 'sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' dev/vendor-hash.txt
  ;;
*) exit 2 ;;
esac
SH
  chmod 0700 "$mock_bin/nix"

  run env MOCK_STATE="$test_root/nix-build-count" PATH="$mock_bin:$PATH" \
    bash "$repo/dev/environment-run.sh" bootstrap
  [ "$status" -eq 0 ]
  grep -Fx 'sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' "$repo/dev/vendor-hash.txt"
}

@test "profiling rejects non-Linux hosts before running tools" {
  mock_bin="$test_root/bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/uname" <<'SH'
#!/bin/sh
printf 'Darwin\n'
SH
  chmod 0700 "$mock_bin/uname"

  run env PATH="$mock_bin" /bin/bash "$BATS_TEST_DIRNAME/profile-core.sh" perf
  [ "$status" -eq 2 ]
  [ "$output" = 'BLOCKED: core profiling requires Linux' ]
}

@test "profiling reports a missing Linux tool without attempting the scenario" {
  mock_bin="$test_root/bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/uname" <<'SH'
#!/bin/sh
printf 'Linux\n'
SH
  chmod 0700 "$mock_bin/uname"

  run env PATH="$mock_bin" /bin/bash "$BATS_TEST_DIRNAME/profile-core.sh" perf
  [ "$status" -eq 1 ]
  [ "$output" = 'BLOCKED: perf unavailable' ]
}

@test "trace rejects a successful probe that observed no core call" {
  mock_bin="$test_root/bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/uname" <<'SH'
#!/bin/sh
printf 'Linux\n'
SH
  cat >"$mock_bin/bpftrace" <<'SH'
#!/bin/sh
printf '@calls: 0\n'
SH
  chmod 0700 "$mock_bin/uname" "$mock_bin/bpftrace"

  run env PATH="$mock_bin:$PATH" /bin/bash "$BATS_TEST_DIRNAME/profile-core.sh" trace
  [ "$status" -eq 1 ]
  [[ "$output" == *'BLOCKED: core.readStatus call not observed'* ]]
}
