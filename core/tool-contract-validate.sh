#!/usr/bin/env bash
# Static contract validation only.
# The referenced Tool is never executed during validation.
set -euo pipefail

contract=${1:?usage: validate-tool-contract.sh TOOL_JSON TOOL_MD SKILL_MD SCHEMA_JSON [REPO_ROOT]}
tool_doc=${2:?usage: validate-tool-contract.sh TOOL_JSON TOOL_MD SKILL_MD SCHEMA_JSON [REPO_ROOT]}
skill_doc=${3:?usage: validate-tool-contract.sh TOOL_JSON TOOL_MD SKILL_MD SCHEMA_JSON [REPO_ROOT]}
schema=${4:?usage: validate-tool-contract.sh TOOL_JSON TOOL_MD SKILL_MD SCHEMA_JSON [REPO_ROOT]}
root=${5:-}

fail() {
    printf '%s\n' "INVALID_TOOL_CONTRACT:$1" >&2
    exit 2
}

for file in "$contract" "$tool_doc" "$skill_doc" "$schema"; do
    test -f "$file" && test ! -L "$file" || fail UNSAFE_PATH
done

jq -e '
  type == "object" and ."$schema" == "https://json-schema.org/draft/2020-12/schema" and
  .type == "object" and .additionalProperties == false and
  (.required | sort) == [
    "authority", "evidence", "failure_statuses", "id", "input",
    "invocation", "kind", "output", "schema_version", "source"
  ] and
  .properties.id.pattern == "^[a-z0-9]+(-[a-z0-9]+)*$" and
  .properties.source.properties.path.pattern == "^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*/SKILL\\.md$" and
  .properties.invocation.properties.command.pattern == "^[A-Za-z0-9_./-]+( [A-Za-z0-9_./-]+)*$" and
  .properties.invocation.properties.skill_relative_executable.pattern ==
    "^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*/[A-Za-z0-9_-][A-Za-z0-9_.-]*$" and
  .properties.authority.properties.network.const == false and
  .properties.authority.properties.writes.const == false and
  .properties.authority.properties.credential_source.const == "none" and
  .properties.authority.properties.allowed_repository.const == "."
' "$schema" >/dev/null || fail SCHEMA_SHAPE

jq -e --slurpfile schema "$schema" '
  def exact_keys($names): type == "object" and (keys | sort) == $names;
  def nonempty_object: type == "object" and length > 0;
  def matches($pattern): type == "string" and test($pattern);
  ($schema[0] | .properties) as $rules |
  exact_keys([
    "authority", "evidence", "failure_statuses", "id", "input",
    "invocation", "kind", "output", "schema_version", "source"
  ]) and
  .schema_version == 1 and .kind == "tool" and
  (.id | matches($rules.id.pattern)) and
  (.source | exact_keys(["path"]) and (.path | matches($rules.source.properties.path.pattern))) and
  (.invocation | exact_keys(["arguments", "command", "skill_relative_executable"]) and
    (.command | matches($rules.invocation.properties.command.pattern)) and
    (.skill_relative_executable | matches($rules.invocation.properties.skill_relative_executable.pattern)) and
    (.arguments | type == "array" and all(.[]; type == "string"))) and
  .authority == {network:false, writes:false, credential_source:"none", allowed_repository:"."} and
  (.input | nonempty_object) and (.output | nonempty_object) and
  (.failure_statuses | type == "array" and length > 0 and
    length == (unique | length) and all(.[]; matches($rules.failure_statuses.items.pattern))) and
  (.evidence | nonempty_object)
' "$contract" >/dev/null || fail JSON_SHAPE

if test -n "$root"; then
    root=$(cd "$root" && pwd -P) || fail SOURCE_ROOT
    source_path=$(jq -r '.source.path' "$contract")
    current=$root
    IFS='/' read -r -a components <<<"$source_path"
    for component in "${components[@]}"; do
        current="$current/$component"
        test ! -L "$current" || fail SOURCE_SYMLINK
    done
    test -f "$current" || fail SOURCE_UNAVAILABLE
fi

for heading in '## Purpose' '## Invocation' '## Authority' '## Output' '## Failure and evidence'; do
    grep -Fqx "$heading" "$tool_doc" || fail "TOOL_DOC:${heading}"
done
frontmatter=$(awk '
  NR == 1 { if ($0 != "---") exit 1; next }
  $0 == "---" { closed=1; exit } { print }
  END { if (!closed) exit 1 }
' "$skill_doc") || fail SKILL_FRONTMATTER
test "$(grep -c '^name:' <<<"$frontmatter")" = 1 || fail SKILL_ID
tool_id=$(jq -r '.id' "$contract")
test "$(sed -n 's/^name:[[:space:]]*//p' <<<"$frontmatter")" = "$tool_id" || fail SKILL_ID
for heading in '## Inputs' '## Decision and Steps' '## Output' '## Stop Condition'; do
    grep -Fqx "$heading" "$skill_doc" || fail "SKILL_DOC:${heading}"
done
command=$(jq -r '.invocation.command' "$contract")
packaged_executable=$(jq -r '.invocation.skill_relative_executable' "$contract")
grep -Fq "$command" "$tool_doc" || fail TOOL_INVOCATION
grep -Fq "$command" "$skill_doc" || fail SKILL_INVOCATION
grep -Fq "$packaged_executable" "$tool_doc" || fail TOOL_PACKAGED_INVOCATION
grep -Fq "$packaged_executable" "$skill_doc" || fail SKILL_PACKAGED_INVOCATION

printf 'TOOL_CONTRACT=PASS (%s)\n' "$tool_id"
