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

if grep -rIEq '(/Users/[^/[:space:]]+/|/home/[^/[:space:]]+/|BEGIN ([A-Z ]+ )?PRIVATE KEY)' "$skill"; then
    fail PERSONAL_PATH_OR_SECRET
fi

# One parser reads both frontmatter and Markdown links.
python3 "$parser" skill-structure "$skill" "$bundle"
