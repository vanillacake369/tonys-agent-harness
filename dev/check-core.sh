#!/usr/bin/env bash
set -euo pipefail
umask 077

repo=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repo"
work=$(mktemp -d "${TMPDIR:-/tmp}/harness-core-check.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
work=$(cd "$work" && pwd -P)
binary="$work/harness"
fixture="$work/fixture"

export GOTOOLCHAIN=local
go test -mod=readonly -short -race -count=1 ./core
go test -mod=readonly -race -run 'Integration$' -count=1 ./core
go build -mod=readonly -o "$binary" .
HARNESS_CORE_BIN="$binary" go test -mod=readonly -run '^TestCoreCLIScenario$' -count=1 ./core
HARNESS_CORE_BIN="$binary" bats dev/core-scenario.bats
go vet -mod=readonly ./core

go test -mod=readonly -run '^$' -bench '^BenchmarkReadStatus$' -benchmem -count=3 ./core
bash dev/core-scenario.sh setup "$fixture" "$repo/provider/provider-catalog.json"
hyperfine --warmup 1 --runs 5 --command-name core-status \
  "bash dev/core-scenario.sh run '$binary' '$fixture'"

