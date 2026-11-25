#!/usr/bin/env bash
# Direct Tool tests: no provider, network, user HOME, or real repository state.
set -euo pipefail

root=${HARNESS_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}
skill="$root/tests/fixtures/review/capability/tool/tool-git-evidence"
tool="$skill/scripts/git-evidence.sh"
validator="$root/core/tool-contract-validate.sh"
contract="$root/contract/git-evidence.json"
schema="$root/contract/git-evidence.schema.json"
tool_doc="$skill/TOOL.md"
skill_doc="$skill/SKILL.md"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/harness-git-evidence.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

fail() {
  printf 'GIT_EVIDENCE_TEST=FAIL (%s)\n' "$1" >&2
  exit 1
}

expect_failure() {
  local expected=$1
  shift
  local output status
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  test "$status" -eq 2 || fail "EXPECTED_EXIT_2:${expected}:${status}"
  if ! jq -e --arg expected "$expected" '.status == $expected' <<< "$output" >/dev/null; then
    fail "EXPECTED_STATUS:${expected}:$(tr '\n' ' ' <<< "$output")"
  fi
}

run_tool() {
  (cd "$fixture/repo" && bash "$tool" "$@")
}

fixture_git() {
  local git_bin
  git_bin=$(command -v git)
  env -i PATH=/usr/bin:/bin HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/home/.config" TMPDIR="$fixture" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    "$git_bin" -c core.hooksPath=/dev/null "$@"
}

test -x "$tool" || fail MISSING_TOOL
test -x "$validator" || fail MISSING_VALIDATOR
test -f "$contract" && test -f "$schema" && test -f "$tool_doc" && test -f "$skill_doc" || fail MISSING_CONTRACT
bash "$validator" "$contract" "$tool_doc" "$skill_doc" "$schema" "$root/tests/fixtures/review"
jq -e '
  .id == "tool-git-evidence" and
  .source.path == "capability/tool/tool-git-evidence/SKILL.md" and
  .invocation == {
    command:"bash capability/tool/tool-git-evidence/scripts/git-evidence.sh",
    arguments:["--repo", ".", "--path", "<safe-relative-tracked-path>"],
    skill_relative_executable:"scripts/git-evidence.sh"
  } and
  .authority == {network:false, writes:false, credential_source:"none", allowed_repository:"."} and
  .output == {
    success_required:[
      "tool", "status", "repository", "path", "head", "path_revision",
      "worktree_dirty", "network", "writes"
    ],
    success_status:"OK"
  } and
  .failure_statuses == ["INVALID_INPUT", "UNAVAILABLE", "UNKNOWN"]
' "$contract" >/dev/null || fail GIT_EVIDENCE_CONTRACT_DRIFT

jq '.properties.id.pattern = ".*"' "$schema" > "$fixture/schema-drift.json"
if bash "$validator" "$contract" "$tool_doc" "$skill_doc" \
  "$fixture/schema-drift.json" "$root/tests/fixtures/review"; then
  fail SCHEMA_DRIFT_ACCEPTED
fi
sed 's/^name: tool-git-evidence$/name: wrong-id/' "$skill_doc" > "$fixture/wrong-frontmatter.md"
printf '%s\n' 'name: tool-git-evidence' >> "$fixture/wrong-frontmatter.md"
if bash "$validator" "$contract" "$tool_doc" "$fixture/wrong-frontmatter.md" \
  "$schema" "$root/tests/fixtures/review"; then
  fail WRONG_FRONTMATTER_ACCEPTED
fi

mkdir "$fixture/repo" "$fixture/nonrepo" "$fixture/home" "$fixture/template" "$fixture/hooks"
printf '%s\n' '#!/usr/bin/env bash' ': > "$GIT_EVIDENCE_HOOK_MARKER"' > "$fixture/hooks/pre-commit"
chmod 700 "$fixture/hooks/pre-commit"
git config --file "$fixture/poison.gitconfig" core.hooksPath "$fixture/hooks"
export GIT_CONFIG_GLOBAL="$fixture/poison.gitconfig"
export GIT_TEMPLATE_DIR="$fixture/template"
export GIT_EVIDENCE_HOOK_MARKER="$fixture/hook-ran"
fixture_git -C "$fixture/repo" init -q --template="$fixture/template"
fixture_git -C "$fixture/repo" config user.email fixture@example.invalid
fixture_git -C "$fixture/repo" config user.name Fixture
printf '%s\n' 'route = "pay"' > "$fixture/repo/routes.py"
mkdir "$fixture/repo/nested"
printf '%s\n' 'nested = true' > "$fixture/repo/nested/file.py"
fixture_git -C "$fixture/repo" add routes.py nested/file.py
fixture_git -C "$fixture/repo" commit --no-verify -qm fixture
test ! -e "$fixture/hook-ran" || fail CALLER_GIT_HOOK_RAN

head_before=$(fixture_git -C "$fixture/repo" rev-parse HEAD)
status_before=$(fixture_git -C "$fixture/repo" status --porcelain=v1 --untracked-files=all)
output=$(cd "$fixture/repo" && bash "$tool" --repo . --path routes.py)
jq -e --arg head "$head_before" '
  .tool == "tool-git-evidence" and .status == "OK" and .repository == "." and
  .path == "routes.py" and .head == $head and .path_revision == $head and
  .worktree_dirty == false and .network == "DENIED" and .writes == false
' <<< "$output" >/dev/null || fail INVALID_CLEAN_OUTPUT
jq -e --slurpfile contract "$contract" '. as $actual |
  .status == $contract[0].output.success_status and
  all($contract[0].output.success_required[]; . as $key | $actual | has($key))
' <<< "$output" >/dev/null || fail OUTPUT_CONTRACT_DRIFT
status_after=$(fixture_git -C "$fixture/repo" status --porcelain=v1 --untracked-files=all)
test "$status_after" = "$status_before" || fail TOOL_MUTATED_CLEAN_FIXTURE

printf '%s\n' 'dirty = true' >> "$fixture/repo/routes.py"
dirty_before=$(fixture_git -C "$fixture/repo" status --porcelain=v1 --untracked-files=all)
output=$(cd "$fixture/repo" && bash "$tool" --repo . --path routes.py)
jq -e '.status == "OK" and .worktree_dirty == true' <<< "$output" >/dev/null || fail INVALID_DIRTY_OUTPUT
status_after=$(fixture_git -C "$fixture/repo" status --porcelain=v1 --untracked-files=all)
test "$status_after" = "$dirty_before" || fail TOOL_MUTATED_DIRTY_FIXTURE

expect_failure INVALID_INPUT run_tool --repo ../outside --path routes.py
expect_failure INVALID_INPUT run_tool --repo /tmp --path routes.py
expect_failure INVALID_INPUT run_tool --repo . --path ../escape
expect_failure INVALID_INPUT run_tool --repo . --path /tmp/escape
expect_failure INVALID_INPUT run_tool --repo . --path untracked.txt
expect_failure INVALID_INPUT run_tool --repo . --path nested
expect_failure UNAVAILABLE bash -c 'cd "$1" && bash "$2" --repo . --path routes.py' _ "$fixture/nonrepo" "$tool"

fixture_git -C "$fixture/repo" checkout -- routes.py
blob=$(fixture_git -C "$fixture/repo" rev-parse HEAD:routes.py)
blob_path="$fixture/repo/.git/objects/${blob:0:2}/${blob:2}"
sleep 1
touch "$fixture/repo/routes.py"
rm -f "$blob_path"
expect_failure UNAVAILABLE run_tool --repo . --path routes.py

jq '.id = "wrong-id"' "$contract" > "$fixture/mismatched-id.json"
if bash "$validator" "$fixture/mismatched-id.json" "$tool_doc" "$skill_doc" \
  "$schema" "$root/tests/fixtures/review"; then
  fail MISMATCHED_ID_ACCEPTED
fi
jq '.unexpected = true' "$contract" > "$fixture/unknown-key.json"
if bash "$validator" "$fixture/unknown-key.json" "$tool_doc" "$skill_doc" "$schema" "$root/tests/fixtures/review"; then
  fail UNKNOWN_KEY_ACCEPTED
fi

# A second Tool with the same read-only contract shape must validate without
# changing the shared schema or this validator.
cat > "$fixture/inspect.md" <<'EOF'
# Inspect Tool

## Purpose

Read one fixture input.

## Invocation

`bash tools/inspect.sh --input fixture.txt`

Installed Skill executable: `scripts/inspect.sh`.

## Authority

Read-only and offline.

## Output

Return JSON.

## Failure and evidence

Report an invalid input.
EOF
cat > "$fixture/inspect-skill.md" <<'EOF'
---
name: inspect
description: Inspect a disposable fixture using bash tools/inspect.sh.
---

## Inputs

Receive a fixture path.

## Decision and Steps

Call `bash tools/inspect.sh --input fixture.txt`.
The installed executable is `scripts/inspect.sh` relative to this Skill.

## Output

Return observed JSON.

## Stop Condition

Stop on invalid input.
EOF
jq '.id = "inspect" |
    .source.path = "capability/skill/skill-review-evidence/SKILL.md" |
    .invocation = {
      command:"bash tools/inspect.sh",
      arguments:["--input", "fixture.txt"],
      skill_relative_executable:"scripts/inspect.sh"
    } |
    .input = {path:{type:"safe-relative-path"}} |
    .output = {success_required:["status", "path"], success_status:"OK"} |
    .failure_statuses = ["INVALID_INPUT"]' "$contract" > "$fixture/inspect.json"
bash "$validator" "$fixture/inspect.json" "$fixture/inspect.md" \
  "$fixture/inspect-skill.md" "$schema" "$root/tests/fixtures/review" \
  || fail SECOND_TOOL_REJECTED

jq '.source.path = "capability/skill/../escape/SKILL.md"' "$fixture/inspect.json" > "$fixture/unsafe-source.json"
if bash "$validator" "$fixture/unsafe-source.json" "$fixture/inspect.md" \
  "$fixture/inspect-skill.md" "$schema" "$root/tests/fixtures/review"; then
  fail UNSAFE_SOURCE_ACCEPTED
fi
jq '.source.path = "capability/skill/ghost/SKILL.md"' "$fixture/inspect.json" > "$fixture/missing-source.json"
if bash "$validator" "$fixture/missing-source.json" "$fixture/inspect.md" \
  "$fixture/inspect-skill.md" "$schema" "$root/tests/fixtures/review"; then
  fail MISSING_SOURCE_ACCEPTED
fi
jq '.invocation.skill_relative_executable = "../escape.sh"' "$fixture/inspect.json" \
  > "$fixture/unsafe-packaged-path.json"
if bash "$validator" "$fixture/unsafe-packaged-path.json" "$fixture/inspect.md" \
  "$fixture/inspect-skill.md" "$schema" "$root/tests/fixtures/review"; then
  fail UNSAFE_PACKAGED_PATH_ACCEPTED
fi
jq '.authority.writes = "false"' "$fixture/inspect.json" > "$fixture/invalid-authority.json"
if bash "$validator" "$fixture/invalid-authority.json" "$fixture/inspect.md" \
  "$fixture/inspect-skill.md" "$schema" "$root/tests/fixtures/review"; then
  fail INVALID_AUTHORITY_ACCEPTED
fi

printf '%s\n' 'GIT_EVIDENCE_TEST=PASS (clean, dirty, unsafe-input, nonrepo, generic contract, and Git-error controls)'
