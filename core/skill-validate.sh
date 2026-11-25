#!/usr/bin/env bash
# Build-time structural checks only.
# Bundled Skill scripts are never executed during validation.
set -euo pipefail
skill=$1
bundle=${2:-}
parser=$(dirname "$0")/metadata-validate.py
fail() {
    printf '%s\n' "$1" >&2
    exit 1
}
test -d "$skill" && test ! -L "$skill" || fail UNSAFE_PATH
test -z "$(find "$skill" ! -type d ! -type f -print -quit)" || fail UNSAFE_PATH
test -f "$skill/SKILL.md" || fail INVALID_SKILL

test -z "$(find "$skill" \( -name '.env*' -o -name '.git' -o -name 'auth.json' \
    -o -name 'credentials*' -o -name 'id_rsa*' -o -name 'id_ed25519*' \
    -o -name '*.pem' -o -name '*.key' \) -print -quit)" || fail SENSITIVE_FILE

metadata=$(awk 'NR == 1 { if ($0 != "---") exit 1; next }
  $0 == "---" { closed=1; exit } { print }
  END { if (!closed) exit 1 }' "$skill/SKILL.md") || fail INVALID_SKILL
parsed=$(printf '%s\n' "$metadata" | python3 "$parser" yaml) || fail INVALID_SKILL
printf '%s\n' "$parsed" | jq -e --arg name "$(basename "$skill")" '
  type == "object" and .name == $name and
  (.name | type == "string" and length <= 64 and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
  (.description | type == "string" and length <= 1024 and test("[^\\s]")) and
  ((has("license") | not) or ((.license | type) == "string" and (.license | test("[^\\s]")))) and
  ((has("compatibility") | not) or
    ((.compatibility | type) == "string" and
      (.compatibility | length) <= 500 and (.compatibility | test("[^\\s]")))) and
  ((has("allowed-tools") | not) or
    ((.["allowed-tools"] | type) == "string" and (.["allowed-tools"] | test("[^\\s]")))) and
  ((has("metadata") | not) or ((.metadata | type) == "object" and all(.metadata[]; type == "string")))
' >/dev/null || fail INVALID_SKILL

awk 'NR == 1 && $0 != "---" { exit 1 }
  $0 == "---" { separators++; next }
  separators >= 2 && /[^[:space:]]/ { body=1 }
  END { if (separators < 2 || !body) exit 1 }' "$skill/SKILL.md" || fail INVALID_SKILL

if grep -rIEq '(/Users/[^/[:space:]]+/|/home/[^/[:space:]]+/|BEGIN ([A-Z ]+ )?PRIVATE KEY)' "$skill"; then
    fail PERSONAL_PATH_OR_SECRET
fi

root=$(realpath "$skill")
policy=""
if test -n "$bundle"; then
    bundle=$(realpath "$bundle") || fail INVALID_RESOURCE
    case "$root" in "$bundle"/*/*) ;; *) fail INVALID_RESOURCE ;; esac
    if test -f "$bundle/POLICY.md" && test ! -L "$bundle/POLICY.md"; then
        policy="$bundle/POLICY.md"
    fi
fi
while IFS= read -r -d '' markdown; do
    # Check explicit inline Markdown links; other reference syntax needs source review.
    links=$(jq -Rrs '[scan("\\[[^\\]]*\\]\\(([^)]+)\\)") | .[0]] | .[]' "$markdown")
    while IFS= read -r target; do
        test -n "$target" || continue
        case "$target" in
        https://* | http://* | mailto:* | \#*) continue ;;
        /* | *:* | *' '* | *'%'* | *'\\'*) fail INVALID_RESOURCE ;;
        esac
        target=${target%%#*}
        resource_path="$(dirname "$markdown")/$target"
        test -e "$resource_path" || fail INVALID_RESOURCE
        resolved=$(realpath "$resource_path") || fail INVALID_RESOURCE
        case "$resolved" in
            "$root" | "$root"/*) ;;
            *) test -n "$policy" && test "$resolved" = "$policy" || fail INVALID_RESOURCE ;;
        esac
    done <<<"$links"
done < <(find "$skill" -type f -name '*.md' -print0)
