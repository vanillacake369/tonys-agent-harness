#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $# -eq 1 ]] || {
  echo 'usage: profile-core.sh perf|trace' >&2
  exit 2
}
mode=$1
case "$mode" in perf | trace) ;; *) echo 'usage: profile-core.sh perf|trace' >&2; exit 2 ;; esac

[[ $(uname -s) == Linux ]] || {
  echo 'BLOCKED: core profiling requires Linux' >&2
  exit 2
}
tool=perf
[[ $mode == trace ]] && tool=bpftrace
command -v "$tool" >/dev/null || {
  echo "BLOCKED: $tool unavailable" >&2
  exit 1
}

repo=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repo"
work=$(mktemp -d "${TMPDIR:-/tmp}/harness-core-profile.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
work=$(cd "$work" && pwd -P)
binary="$work/harness"
fixture="$work/fixture"
scenario="$work/core-scenario.sh"

cp dev/core-scenario.sh "$scenario"
GOTOOLCHAIN=local go build -mod=readonly -gcflags='all=-N -l' -o "$binary" .
bash "$scenario" setup "$fixture" "$repo/provider/provider-catalog.json"

if [[ $mode == perf ]]; then
  perf stat -r 5 -- bash "$scenario" run "$binary" "$fixture"
  exit
fi

symbol=$(go tool nm "$binary" | awk '$3 == "tonys-agent-harness/core.readStatus" && symbol == "" { symbol = $3 }
  END { print symbol }')
[[ -n "$symbol" ]] || {
  echo 'BLOCKED: core.readStatus symbol unavailable' >&2
  exit 1
}
probe="uprobe:\"$binary\":\"$symbol\" { @calls = count(); }"
printf -v traced_command 'bash %q run %q %q' "$scenario" "$binary" "$fixture"
trace_output=$(bpftrace -e "$probe" -c "$traced_command")
printf '%s\n' "$trace_output"
grep -Eq '@calls:[[:space:]]*[1-9][0-9]*' <<<"$trace_output" || {
  echo 'BLOCKED: core.readStatus call not observed' >&2
  exit 1
}

