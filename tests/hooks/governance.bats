#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/../../"
  EVIDENCE="$ROOT/runtime/governance/evidence-gate.sh"
  RETRY="$ROOT/runtime/governance/retry-budget.sh"
  GIT_GATE="$ROOT/runtime/governance/git-lifecycle-gate.sh"
  IDEMPOTENCY="$ROOT/runtime/governance/external-operation.sh"
  PROVIDER_GATE="$ROOT/runtime/governance/provider-instructions-gate.sh"
  MEMORY="$ROOT/runtime/governance/memory-lifecycle.sh"
  CONFIG="$ROOT/runtime/governance/configuration-gate.sh"
  PATH_GUARD="$ROOT/runtime/governance/path-guard.sh"
  MCP_GATE="$ROOT/runtime/governance/mcp-allowlist-gate.sh"
  COMPLETION="$ROOT/runtime/governance/completion-gate.sh"
}

@test "path guard blocks secret paths for provider tool input" {
  run bash -c "printf '%s' '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\".env\"}}' | '$PATH_GUARD'"
  [ "$status" -eq 2 ]
  [[ "$output" == *'sensitive path'* ]]
}

@test "path guard permits ordinary repository paths" {
  run bash -c "printf '%s' '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"src/main.nix\"}}' | '$PATH_GUARD'"
  [ "$status" -eq 0 ]
}

@test "MCP allowlist rejects an undeclared role and server" {
  policy="$BATS_TEST_TMPDIR/mcp-policy.json"
  cat > "$policy" <<'JSON'
{"servers":{"context7":{"roles":["researcher"],"skills":["skl-pre-research-ljh"],"mutation":false}}}
JSON
  run "$MCP_GATE" "$policy" context7 implementer skl-mid-impl-ljh
  [ "$status" -eq 2 ]
}

@test "MCP allowlist permits the declared research path" {
  policy="$BATS_TEST_TMPDIR/mcp-policy-valid.json"
  cat > "$policy" <<'JSON'
{"servers":{"context7":{"roles":["researcher"],"skills":["skl-pre-research-ljh"],"mutation":false}}}
JSON
  run "$MCP_GATE" "$policy" context7 researcher skl-pre-research-ljh
  [ "$status" -eq 0 ]
}

@test "completion gate blocks code completion with a dirty tree" {
  repo="$BATS_TEST_TMPDIR/completion-dirty"
  mkdir -p "$repo"; git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
  printf 'x\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm initial
  printf 'dirty\n' >> "$repo/a.txt"
  evidence="$BATS_TEST_TMPDIR/completion-evidence.json"
  cat > "$evidence" <<'JSON'
{"status":"DONE","requirements":[{"id":"FR-1","result":"pass"}],"commands":[{"command":"test","exit_code":0,"duration_ms":1,"result":"synthetic fixture"}],"changed_files":["a.txt"],"diff_summary":"changed","unresolved_errors":[],"commit":"abc"}
JSON
  printf '%s\n' '{"requirement_id":"FR-1","red":{"sequence":1,"command":"test","exit_code":1,"result":"red"},"green":{"sequence":2,"command":"test","exit_code":0,"result":"green"},"exemption":null}' > "$BATS_TEST_TMPDIR/dirty-tdd.json"
  run env AGENT_TDD_EVIDENCE="$BATS_TEST_TMPDIR/dirty-tdd.json" "$COMPLETION" --repo "$repo" --mode code --scope <(printf 'a.txt\n') --evidence "$evidence"
  [ "$status" -eq 2 ]
  [[ "$output" == *'uncommitted'* ]]
}

@test "evidence gate accepts a verified code completion" {
  file="$BATS_TEST_TMPDIR/evidence.json"
  cat > "$file" <<'JSON'
{"status":"DONE","requirements":[{"id":"FR-001","result":"pass"}],"commands":[{"command":"just test","exit_code":0,"duration_ms":12,"result":"125/125"}],"changed_files":["src/a.nix"],"diff_summary":"1 file changed","unresolved_errors":[],"commit":"abc123"}
JSON
  run "$EVIDENCE" "$file"
  [ "$status" -eq 0 ]
}

@test "evidence gate blocks completion with unrun tests" {
  file="$BATS_TEST_TMPDIR/evidence-unrun.json"
  cat > "$file" <<'JSON'
{"status":"DONE","requirements":[{"id":"FR-001","result":"pass"}],"commands":[],"changed_files":["src/a.nix"],"diff_summary":"1 file changed","unresolved_errors":[],"commit":"abc123"}
JSON
  run "$EVIDENCE" "$file"
  [ "$status" -eq 2 ]
  [[ "$output" == *'test evidence'* ]]
}

@test "evidence gate blocks hidden test failure" {
  file="$BATS_TEST_TMPDIR/evidence-fail.json"
  cat > "$file" <<'JSON'
{"status":"DONE","requirements":[{"id":"FR-001","result":"pass"}],"commands":[{"command":"just test","exit_code":1,"duration_ms":12,"result":"failed"}],"changed_files":["src/a.nix"],"diff_summary":"1 file changed","unresolved_errors":[],"commit":"abc123"}
JSON
  run "$EVIDENCE" "$file"
  [ "$status" -eq 2 ]
  [[ "$output" == *'failed command'* ]]
}

@test "retry budget blocks on the third same-task failure" {
  state="$BATS_TEST_TMPDIR/retry.json"
  run "$RETRY" record "$state" task-a fail "root-cause-a"
  [ "$status" -eq 0 ]
  run "$RETRY" record "$state" task-a fail "root-cause-a"
  [ "$status" -eq 0 ]
  run "$RETRY" record "$state" task-a fail "root-cause-a"
  [ "$status" -eq 2 ]
  [[ "$output" == *'BLOCKED'* ]]
}

@test "retry budget does not reset through a new invocation" {
  state="$BATS_TEST_TMPDIR/retry-persist.json"
  "$RETRY" record "$state" task-a fail "root-cause-a"
  "$RETRY" record "$state" task-a fail "root-cause-a"
  run "$RETRY" record "$state" task-a fail "root-cause-b"
  [ "$status" -eq 2 ]
}

@test "git lifecycle gate accepts clean committed code with evidence" {
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf 'base\n' > "$repo/base.txt"
  git -C "$repo" add base.txt
  git -C "$repo" commit -qm base
  baseline=$(git -C "$repo" rev-parse HEAD)
  printf 'x\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm change
  scope="$BATS_TEST_TMPDIR/scope.txt"
  evidence="$BATS_TEST_TMPDIR/git-evidence.json"
  printf 'a.txt\n' > "$scope"
  printf '{"status":"DONE","commit":"%s","baseline_commit":"%s","changed_files":["a.txt"],"commands":[{"command":"test","exit_code":0}]}' "$(git -C "$repo" rev-parse HEAD)" "$baseline" > "$evidence"
  run "$GIT_GATE" --repo "$repo" --mode code --scope "$scope" --evidence "$evidence"
  [ "$status" -eq 0 ]
}

@test "git lifecycle gate blocks uncommitted code completion" {
  repo="$BATS_TEST_TMPDIR/dirty-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf 'x\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm initial
  printf 'changed\n' >> "$repo/a.txt"
  scope="$BATS_TEST_TMPDIR/dirty-scope.txt"
  evidence="$BATS_TEST_TMPDIR/dirty-evidence.json"
  printf 'a.txt\n' > "$scope"
  printf '{"status":"DONE","commit":"abc","commands":[{"command":"test","exit_code":0}]}' > "$evidence"
  run "$GIT_GATE" --repo "$repo" --mode code --scope "$scope" --evidence "$evidence"
  [ "$status" -eq 2 ]
  [[ "$output" == *'uncommitted'* ]]
}

@test "external operation registry prevents duplicate unknown execution" {
  registry="$BATS_TEST_TMPDIR/operations.json"
  run "$IDEMPOTENCY" reserve "$registry" op-1 github repo-a fp-1
  [ "$status" -eq 0 ]
  run "$IDEMPOTENCY" mark "$registry" op-1 UNKNOWN "timeout evidence"
  [ "$status" -eq 0 ]
  run "$IDEMPOTENCY" reserve "$registry" op-1 github repo-a fp-1
  [ "$status" -eq 2 ]
  [[ "$output" == *'UNKNOWN'* ]]
}

@test "external operation fingerprint mismatch blocks reuse" {
  registry="$BATS_TEST_TMPDIR/operations-mismatch.json"
  "$IDEMPOTENCY" reserve "$registry" op-1 github repo-a fp-1
  run "$IDEMPOTENCY" reserve "$registry" op-1 github repo-a fp-2
  [ "$status" -eq 2 ]
  [[ "$output" == *'fingerprint mismatch'* ]]
}

@test "provider instruction gate accepts the shared AGENTS source" {
  project="$BATS_TEST_TMPDIR/project"
  generated="$BATS_TEST_TMPDIR/generated"
  run python3 "$ROOT/harness.py" init --project "$project" --preset regulated
  [ "$status" -eq 0 ]
  run python3 "$ROOT/harness.py" export --project "$project" --output "$generated"
  [ "$status" -eq 0 ]
  run "$PROVIDER_GATE" "$generated"
  [ "$status" -eq 0 ]
}

@test "memory lifecycle rejects secret-like content" {
  root="$BATS_TEST_TMPDIR/memory"
  run "$MEMORY" write "$root" project-a session item-1 '{"token":"do-not-store"}'
  [ "$status" -eq 2 ]
  [[ "$output" == *'sensitive'* ]]
}

@test "memory lifecycle isolates namespace and promotes durable knowledge" {
  root="$BATS_TEST_TMPDIR/memory-safe"
  run "$MEMORY" write "$root" project-a session item-1 '{"fact":"confirmed"}'
  [ "$status" -eq 0 ]
  run "$MEMORY" promote "$root" project-a session item-1 durable
  [ "$status" -eq 0 ]
  [ -f "$root/project-a/durable/item-1.json" ]
  [ ! -e "$root/project-b/durable/item-1.json" ]
}

@test "configuration gate rejects project relaxation of global deny" {
  policy="$BATS_TEST_TMPDIR/policy-relax.json"
  cat > "$policy" <<'JSON'
{"layers":{"global-policy":{"priority":100,"can_weaken":false,"deny":["secret_access"]},"project-policy":{"priority":90,"can_weaken":false,"allow":["secret_access"]},"agent-role-permissions":{"priority":80,"can_weaken":false},"skill-workflow-registry":{"priority":70,"can_weaken":false},"mcp-registry":{"priority":60,"can_weaken":false},"runtime-sandbox-approval":{"priority":50,"can_weaken":false},"verification-evidence-policy":{"priority":40,"can_weaken":false}}}
JSON
  run "$CONFIG" "$policy"
  [ "$status" -eq 2 ]
  [[ "$output" == *'weakens global deny'* ]]
}

@test "configuration gate accepts ordered non-weakening layers" {
  policy="$BATS_TEST_TMPDIR/policy-valid.json"
  cat > "$policy" <<'JSON'
{"layers":{"global-policy":{"priority":100,"can_weaken":false,"deny":["secret_access"]},"project-policy":{"priority":90,"can_weaken":false,"allow":["read_repository"]},"agent-role-permissions":{"priority":80,"can_weaken":false},"skill-workflow-registry":{"priority":70,"can_weaken":false},"mcp-registry":{"priority":60,"can_weaken":false},"runtime-sandbox-approval":{"priority":50,"can_weaken":false},"verification-evidence-policy":{"priority":40,"can_weaken":false}}}
JSON
  run "$CONFIG" "$policy"
  [ "$status" -eq 0 ]
}
