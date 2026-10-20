#!/usr/bin/env bash
# Minimal file-backed memory lifecycle with project namespace isolation.

set -euo pipefail

COMMAND=${1:-}
ROOT=${2:-}
NAMESPACE=${3:-}
KIND=${4:-}
ID=${5:-}
VALID_KINDS='session|daily|durable'

if [[ -z "$ROOT" || ! "$NAMESPACE" =~ ^[a-zA-Z0-9_-][a-zA-Z0-9._-]*$ || ! "$ID" =~ ^[a-zA-Z0-9_-][a-zA-Z0-9._-]*$ || ! "$KIND" =~ ^($VALID_KINDS)$ ]]; then
  echo "invalid memory namespace, kind, or id" >&2
  exit 2
fi

path="$ROOT/$NAMESPACE/$KIND/$ID.json"
mkdir -p "$ROOT/.locks"
locks=("$ROOT/.locks/$NAMESPACE-$KIND-$ID.lock")
TARGET=
if [[ "$COMMAND" == promote ]]; then
  TARGET=${6:-}
  [[ "$TARGET" =~ ^($VALID_KINDS)$ ]] || { echo "invalid target kind" >&2; exit 2; }
  locks+=("$ROOT/.locks/$NAMESPACE-$TARGET-$ID.lock")
fi
IFS=$'\n' read -r -d '' -a locks < <(printf '%s\n' "${locks[@]}" | sort -u && printf '\0')
acquired=()
temporary=
cleanup() {
  [[ -z "$temporary" ]] || rm -f "$temporary"
  local held
  for held in "${acquired[@]}"; do rmdir "$held" 2>/dev/null || true; done
}
trap cleanup EXIT
for lock in "${locks[@]}"; do
  if ! mkdir "$lock" 2>/dev/null; then
    echo "memory entry locked; retry after the owning operation completes" >&2; exit 2
  fi
  acquired+=("$lock")
done
# Reject symlinks inside the configured root; OS aliases such as /var on macOS
# above that root are not project namespace escapes.
check_path() {
  local candidate=$1
  while [[ "$candidate" != / && "$candidate" != . ]]; do
    [[ ! -L "$candidate" ]] || { echo "symlink memory path rejected" >&2; exit 2; }
    [[ "$candidate" == "$ROOT" ]] && break
    candidate=$(dirname "$candidate")
  done
}
check_path "$path"
atomic_json_write() {
  local destination=$1
  shift
  local parent
  parent=$(dirname "$destination")
  mkdir -p "$parent"
  check_path "$parent"
  temporary=$(mktemp "$parent/.memory.XXXXXX")
  jq "$@" > "$temporary"
  chmod 600 "$temporary"
  check_path "$parent"
  mv -f "$temporary" "$destination"
  temporary=
}
validate_content() {
  local content=$1 kind=$2 max_lines=200
  [[ "$kind" == daily ]] && max_lines=40
  [[ "$kind" == durable ]] && max_lines=120
  if ! jq -e --argjson max "$max_lines" 'type == "object" and ([.. | strings | split("\n") | length] | add // 0) <= $max' <<<"$content" >/dev/null; then
    echo "invalid memory content or decoded line limit exceeded" >&2; exit 2
  fi
  if jq -r '.. | strings, (objects | keys[])' <<<"$content" | grep -qiE 'password|secret|token|private[_-]?key|credential|ssn'; then
    echo "sensitive memory content rejected" >&2; exit 2
  fi
  if jq -r '.. | strings' <<<"$content" | grep -qE '(^|[^[:alnum:]._%+-])[[:alnum:]._%+-]+@[[:alnum:].-]+\.[A-Za-z]{2,}([^[:alnum:]._%+-]|$)|(^|[^0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}([^0-9]|$)'; then
    echo "personal data rejected from automatic memory" >&2; exit 2
  fi
  local policy=${AGENT_MEMORY_POLICY:-}
  if [[ -n "$policy" ]]; then
    [[ -f "$policy" ]] && jq -e '.pii_patterns | type == "array" and all(.[]; type == "string" and length > 0)' "$policy" >/dev/null 2>&1 || {
      echo "invalid project memory policy" >&2; exit 2;
    }
    if ! jq -e --slurpfile policy "$policy" '
      [.. | strings] as $values |
      all($policy[0].pii_patterns[]; . as $pattern | all($values[]; test($pattern; "i") | not))
    ' <<<"$content" >/dev/null 2>&1; then
      echo "project personal data policy rejected memory" >&2; exit 2
    fi
  fi
}
case "$COMMAND" in
  write)
    CONTENT=${6:-}
    EXPIRES_AT=${7:-}
    EXPECTED_REVISION=${8:-}
    validate_content "$CONTENT" "$KIND"
    if [[ -z "$CONTENT" ]] || ! printf '%s' "$CONTENT" | jq -e 'type == "object"' >/dev/null 2>&1; then
      echo "invalid memory content" >&2; exit 2
    fi
    if printf '%s' "$CONTENT" | grep -qiE 'password|secret|token|private[_-]?key|credential|ssn'; then
      echo "sensitive memory content rejected" >&2; exit 2
    fi
    revision=1
    if [[ -f "$path" ]]; then
      current_revision=$(jq -er '.revision // 1' "$path") || { echo "invalid existing memory" >&2; exit 2; }
      if [[ -z "$EXPECTED_REVISION" || "$EXPECTED_REVISION" != "$current_revision" ]]; then
        echo "memory conflict: expected revision required" >&2; exit 2
      fi
      revision=$((current_revision + 1))
    elif [[ -n "$EXPECTED_REVISION" ]]; then
      echo "memory conflict: expected revision supplied for missing entry" >&2; exit 2
    fi
    if [[ -n "$EXPIRES_AT" ]] && ! python3 - "$EXPIRES_AT" <<'PY'
from datetime import datetime
import sys
datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
PY
    then
      echo "invalid memory expiry" >&2; exit 2
    fi
    mkdir -p "$(dirname "$path")"
    chmod 700 "$ROOT" "$ROOT/$NAMESPACE" "$ROOT/$NAMESPACE/$KIND" 2>/dev/null || true
    atomic_json_write "$path" -cn --arg namespace "$NAMESPACE" --arg kind "$KIND" --arg id "$ID" \
      --arg expires_at "$EXPIRES_AT" --argjson revision "$revision" --argjson content "$CONTENT" \
      '{memory_version:1,namespace:$namespace,kind:$kind,id:$id,revision:$revision,expires_at:(if $expires_at == "" then null else $expires_at end),confidence:"unverified",content:$content}'
    echo "memory written: $NAMESPACE/$KIND/$ID"
    ;;
  read)
    [[ -f "$path" ]] || { echo "memory not found" >&2; exit 2; }
    expires=$(jq -r '.expires_at // ""' "$path")
    if [[ -n "$expires" ]] && ! python3 - "$expires" <<'PY'
from datetime import datetime, timezone
import sys
expires = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
raise SystemExit(0 if expires > datetime.now(timezone.utc) else 2)
PY
    then
      atomic_json_write "$path" '.confidence="expired"' "$path"
      echo "memory expired" >&2; exit 2
    fi
    jq -c . "$path"
    ;;
  promote)
    [[ -f "$path" ]] || { echo "memory not found" >&2; exit 2; }
    target_path="$ROOT/$NAMESPACE/$TARGET/$ID.json"
    check_path "$target_path"
    validate_content "$(jq -c .content "$path")" "$TARGET"
    atomic_json_write "$target_path" --arg kind "$TARGET" '.kind=$kind' "$path"
    echo "memory promoted: $NAMESPACE/$TARGET/$ID"
    ;;
  stale)
    [[ -f "$path" ]] || { echo "memory not found" >&2; exit 2; }
    atomic_json_write "$path" '.confidence="stale"' "$path"
    echo "memory marked stale: $NAMESPACE/$KIND/$ID"
    ;;
  delete)
    [[ -f "$path" ]] || { echo "memory not found" >&2; exit 2; }
    mv "$path" "$path.deleted"
    echo "memory deleted recoverably: $NAMESPACE/$KIND/$ID"
    ;;
  *)
    echo "usage: $0 write|read|promote|stale|delete ROOT NAMESPACE KIND ID [CONTENT|TARGET_KIND] [EXPIRES_AT] [EXPECTED_REVISION]" >&2
    exit 2
    ;;
esac
