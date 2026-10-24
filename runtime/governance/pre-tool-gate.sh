#!/usr/bin/env bash
# Fan one provider payload into deterministic pre-execution gates.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
printf '%s' "$INPUT" | "$ROOT/path-guard.sh"
printf '%s' "$INPUT" | python3 "$ROOT/execution-gate.py" "$@"
printf '%s' "$INPUT" | "$ROOT/retry-hook.sh" pre
