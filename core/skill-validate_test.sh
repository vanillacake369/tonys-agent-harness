#!/usr/bin/env bash
set -euo pipefail
root=${HARNESS_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}
validator=${1:-$root/core/skill-validate.sh}
sample=${2:-$root/tests/fixtures/skill-layout/harness-smoke}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cp -R "$sample" "$fixture/harness-smoke"
chmod -R u+w "$fixture"
bash "$validator" "$fixture/harness-smoke"
expect_failure() {
  # WHEN the prepared skill is validated.
  local status=0
  bash "$validator" "$fixture/harness-smoke" > "$fixture/log" 2>&1 || status=$?

  # THEN validation fails with the expected diagnostic.
  if [[ "$status" == 0 ]]; then
    echo "unexpected validation success: $1" >&2
    exit 1
  fi
  grep -q "$1" "$fixture/log"
}
printf '\n[missing](references/missing.md)\n' >> "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_RESOURCE
cp "$sample/SKILL.md" "$fixture/harness-smoke/SKILL.md"
ln -s /does-not-exist "$fixture/harness-smoke/escape"
expect_failure UNSAFE_PATH
unlink "$fixture/harness-smoke/escape"
printf '\n/home/example/private\n' >> "$fixture/harness-smoke/SKILL.md"
expect_failure PERSONAL_PATH
cp "$sample/SKILL.md" "$fixture/harness-smoke/SKILL.md"
printf '%s\n' '---' 'name: other' 'description: test' '---' > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL
cp "$sample/SKILL.md" "$fixture/harness-smoke/SKILL.md"
touch "$fixture/harness-smoke/.env"
expect_failure SENSITIVE_FILE

rm "$fixture/harness-smoke/.env"
name=$(printf 'a%.0s' {1..64})
mkdir "$fixture/$name"
description=$(printf 'a%.0s' {1..1024})
printf '%s\n' '---' "name: $name" "description: $description" '---' '# Fixture' > "$fixture/$name/SKILL.md"
bash "$validator" "$fixture/$name"
printf '%s\n' '---' 'name: harness-smoke' 'description: test' '---' > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL
cp "$sample/SKILL.md" "$fixture/harness-smoke/SKILL.md"
printf '%s\n' \
  '---' 'name: harness-smoke' "description: ${description}a" '---' '# Fixture' \
  > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL

compatibility=$(printf 'a%.0s' {1..500})
printf '%s\n' \
  '---' 'name: harness-smoke' 'description: test' "compatibility: $compatibility" \
  'metadata:' '  owner: team' '---' '# Fixture' > "$fixture/harness-smoke/SKILL.md"
bash "$validator" "$fixture/harness-smoke"
printf '%s\n' \
  '---' 'name: harness-smoke' 'description: test' "compatibility: ${compatibility}a" \
  '---' '# Fixture' > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL
printf '%s\n' \
  '---' 'name: harness-smoke' 'description: test' 'metadata:' '  owner: 42' \
  '---' '# Fixture' > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL
printf '%s\n' \
  '---' 'name: harness-smoke' 'description: test' 'allowed-tools: 42' \
  '---' '# Fixture' > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL

# GIVEN a skill references an existing file outside its root.
cp "$sample/SKILL.md" "$fixture/harness-smoke/SKILL.md"
printf '\n[crosses the root](../other.md)\n' >> "$fixture/harness-smoke/SKILL.md"
touch "$fixture/other.md"
expect_failure INVALID_RESOURCE

# GIVEN the frontmatter declares the description twice.
printf '%s\n' '---' 'name: harness-smoke' 'description: test' 'description: duplicate' '---' '# Fixture' \
  > "$fixture/harness-smoke/SKILL.md"
expect_failure INVALID_SKILL
