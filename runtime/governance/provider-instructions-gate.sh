#!/usr/bin/env bash
# Validate one exported provider bundle against its shared AGENTS.md contract.

set -euo pipefail
ROOT=${1:-build/agent-harness}
MANIFEST="$ROOT/manifest.json"
CAPABILITIES="$ROOT/capabilities.json"
[[ -f "$MANIFEST" && -f "$CAPABILITIES" ]] || {
  echo "provider instruction gate: exported manifest or capabilities missing" >&2
  exit 2
}

providers=$(jq -r '.providers[]' "$MANIFEST") || {
  echo "provider instruction gate: invalid manifest" >&2
  exit 2
}
[[ -n "$providers" ]] || { echo "provider instruction gate: no providers" >&2; exit 2; }

reference_hash=""
while IFS= read -r provider; do
  agents="$ROOT/$provider/AGENTS.md"
  [[ -f "$agents" ]] || {
    echo "provider instruction gate: $provider/AGENTS.md missing" >&2
    exit 2
  }
  hash=$(openssl dgst -sha256 "$agents" | awk '{print $NF}')
  if [[ -z "$reference_hash" ]]; then reference_hash=$hash; fi
  [[ "$hash" == "$reference_hash" ]] || {
    echo "provider instruction gate: instruction drift for $provider" >&2
    exit 2
  }
  case "$provider" in
    claude)
      [[ "$(cat "$ROOT/claude/CLAUDE.md")" == "@AGENTS.md" ]] || {
        echo "provider instruction gate: Claude import missing" >&2; exit 2;
      }
      ;;
    gemini)
      jq -e '.context.fileName | index("AGENTS.md") != null' \
        "$ROOT/gemini/settings.json" >/dev/null || {
        echo "provider instruction gate: Gemini context filename missing" >&2; exit 2;
      }
      ;;
  esac
done <<<"$providers"

echo "provider instruction gate passed: exported adapters share AGENTS.md"
