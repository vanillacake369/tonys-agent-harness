#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GOV="$ROOT/runtime/governance"
}

sign_receipt() {
  local receipt=$1 key_dir=${2:-$BATS_TEST_TMPDIR/signing}
  mkdir -p "$key_dir"
  if [[ ! -f "$key_dir/private.pem" ]]; then
    openssl genrsa -out "$key_dir/private.pem" 2048 >/dev/null 2>&1
    openssl rsa -in "$key_dir/private.pem" -pubout -out "$key_dir/public.pem" >/dev/null 2>&1
  fi
  local payload signature key_id
  payload=$(jq -S -c 'del(.signature)' "$receipt")
  signature=$(printf '%s' "$payload" | openssl dgst -sha256 -sign "$key_dir/private.pem" | base64 | tr -d '\n')
  key_id=$(openssl pkey -pubin -in "$key_dir/public.pem" -outform DER 2>/dev/null | shasum -a 256 | awk '{print $1}')
  jq --arg value "$signature" --arg key_id "$key_id" \
    '.signature={algorithm:"rsa-sha256",key_id:$key_id,value:$value}' "$receipt" > "$receipt.signed"
  mv "$receipt.signed" "$receipt"
  chmod 600 "$receipt"
  export AGENT_APPROVAL_PUBLIC_KEY="$key_dir/public.pem"
}

@test "original audit regressions remain closed" {
  run python3 "$ROOT/tests/fixtures/harness-audit.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"failed": 0'* ]]
}

@test "memory allows 40 decoded lines and rejects oversized promotion" {
  content=$(jq -cn '{text: ([range(40) | "line"] | join("\n"))}')
  run bash "$GOV/memory-lifecycle.sh" write "$BATS_TEST_TMPDIR/memory" project daily forty "$content"
  [ "$status" -eq 0 ]
  content=$(jq -cn '{text: ([range(121) | "line"] | join("\n"))}')
  run bash "$GOV/memory-lifecycle.sh" write "$BATS_TEST_TMPDIR/memory" project session long "$content"
  [ "$status" -eq 0 ]
  run bash "$GOV/memory-lifecycle.sh" promote "$BATS_TEST_TMPDIR/memory" project session long durable
  [ "$status" -eq 2 ]
}

@test "memory rejects namespace symlink escape" {
  mkdir -p "$BATS_TEST_TMPDIR/memory" "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$BATS_TEST_TMPDIR/memory/project"
  run bash "$GOV/memory-lifecycle.sh" write "$BATS_TEST_TMPDIR/memory" project session entry '{"fact":"fixture"}'
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/outside/session/entry.json" ]
}

@test "HUMAN_APPROVAL action cannot be executed by dropping its boolean flag" {
  run bash "$ROOT/runtime/orchestrator/execution-plan.sh" <<'JSON'
{"phase":"3","decision":{"selected_action":"HUMAN_APPROVAL","human_approval_required":false}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"BLOCKED"'* ]]
}

@test "retry state lock fails closed" {
  mkdir "$BATS_TEST_TMPDIR/retry.json.lock"
  run bash "$GOV/retry-budget.sh" record "$BATS_TEST_TMPDIR/retry.json" task fail cause
  [ "$status" -eq 2 ]
}

@test "evidence runner records real command failure without DONE" {
  repo="$BATS_TEST_TMPDIR/failure-repo"; mkdir "$repo"
  git -C "$repo" init -q; git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
  printf 'base\n' > "$repo/base"; git -C "$repo" add base; git -C "$repo" commit -qm base
  baseline=$(git -C "$repo" rev-parse HEAD)
  printf 'change\n' > "$repo/change"; git -C "$repo" add change; git -C "$repo" commit -qm change
  run python3 "$GOV/record-verification.py" --repo "$repo" --output "$BATS_TEST_TMPDIR/evidence.json" --baseline "$baseline" --requirement FR-013 -- bash -c 'printf "fixture failed"; exit 7'
  [ "$status" -eq 7 ]
  run jq -e '.status == "BLOCKED" and .commands[0].exit_code == 7 and .commands[0].result == "fixture failed"' "$BATS_TEST_TMPDIR/evidence.json"
  [ "$status" -eq 0 ]
}

@test "completion rejects evidence without executed commit binding" {
  printf '{"status":"DONE"}\n' > "$BATS_TEST_TMPDIR/evidence.json"
  run bash "$GOV/completion-gate.sh" --repo "$ROOT" --evidence "$BATS_TEST_TMPDIR/evidence.json"
  [ "$status" -eq 2 ]
}

@test "file guard is before execution and no longer after execution" {
  run jq -e '[.hooks.PreToolUse[] | select(.matcher == "Read|Write|Edit|NotebookEdit") | .hooks[].command | contains("path-guard.sh")] | any' "$ROOT/nix/agents/providers/claude/settings.json"
  [ "$status" -eq 0 ]
  run jq -e '[.hooks.PostToolUse[].hooks[].command | contains("path-guard.sh")] | any | not' "$ROOT/nix/agents/providers/claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "MCP hook blocks unknown role and external mutation but permits scoped docs" {
  payload='{"tool_name":"mcp__context7__query-docs"}'
  run env AGENT_DECISION_ID=d AGENT_OPERATION_ID=o AGENT_REQUEST_FINGERPRINT=f AGENT_ROLE= AGENT_SKILL= bash "$GOV/mcp-hook.sh" <<<"$payload"
  [ "$status" -eq 2 ]
  run env AGENT_DECISION_ID=d AGENT_OPERATION_ID=o AGENT_REQUEST_FINGERPRINT=f AGENT_ROLE=researcher AGENT_SKILL=skl-pre-research-ljh AGENT_PROJECT_POLICY="$ROOT/tests/fixtures/project-policy.json" bash "$GOV/mcp-hook.sh" <<<"$payload"
  [ "$status" -eq 0 ]
  run env AGENT_DECISION_ID=d AGENT_OPERATION_ID=o AGENT_REQUEST_FINGERPRINT=f AGENT_ROLE=researcher AGENT_SKILL=skl-pre-research-ljh bash "$GOV/mcp-hook.sh" <<<'{"tool_name":"mcp__atlassian__create_issue"}'
  [ "$status" -eq 2 ]
}

@test "different operation ID cannot duplicate an UNKNOWN fingerprint" {
  registry="$BATS_TEST_TMPDIR/registry.json"
  bash "$GOV/external-operation.sh" reserve "$registry" first provider target fingerprint
  bash "$GOV/external-operation.sh" mark "$registry" first UNKNOWN timeout
  run bash "$GOV/external-operation.sh" reserve "$registry" second provider target fingerprint
  [ "$status" -eq 2 ]
}

@test "recorded verification completes clean root commit and blocks a changed snapshot" {
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf 'fixture\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm fixture
  baseline=$(git -C "$repo" rev-parse HEAD)
  printf 'implementation\n' > "$repo/impl.py"
  git -C "$repo" add impl.py
  git -C "$repo" commit -qm implementation
  printf 'impl.py\n' > "$BATS_TEST_TMPDIR/scope"
  evidence="$BATS_TEST_TMPDIR/actual.json"
  run python3 "$GOV/record-verification.py" --repo "$repo" --output "$evidence" --baseline "$baseline" --requirement FR-013 -- bash -c 'printf "actual fixture result"'
  [ "$status" -eq 0 ]
  run bash "$GOV/completion-gate.sh" --repo "$repo" --scope "$BATS_TEST_TMPDIR/scope" --evidence "$evidence"
  [ "$status" -eq 0 ]
  run python3 "$GOV/record-verification.py" --repo "$repo" --output "$BATS_TEST_TMPDIR/mutated.json" --baseline "$baseline" --requirement FR-013 -- bash -c 'printf "changed" >> a.txt'
  [ "$status" -eq 2 ]
  run jq -e '.status == "BLOCKED" and .worktree_clean == false' "$BATS_TEST_TMPDIR/mutated.json"
  [ "$status" -eq 0 ]
}

@test "design completion uses artifacts instead of requiring a code commit" {
  repo="$BATS_TEST_TMPDIR/design"
  mkdir "$repo"
  git -C "$repo" init -q
  printf 'design fixture\n' > "$repo/design.md"
  printf '{"status":"DONE","mode":"design","artifacts":["design.md"],"unresolved_errors":[]}' > "$BATS_TEST_TMPDIR/design-evidence.json"
  run bash "$GOV/completion-gate.sh" --repo "$repo" --mode design --evidence "$BATS_TEST_TMPDIR/design-evidence.json"
  [ "$status" -eq 0 ]
}

@test "task lifecycle advances a clean task and preserves the next-turn baseline" {
  repo="$BATS_TEST_TMPDIR/task-repo"
  mkdir "$repo"
  git -C "$repo" init -q
  printf 'initial\n' > "$repo/main.py"
  payload=$(jq -cn --arg cwd "$repo" '{session_id:"fixture",cwd:$cwd}')
  run env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" start <<<"$payload"
  [ "$status" -eq 0 ]
  run env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" stop <<<"$payload"
  [ "$status" -eq 0 ]
  printf 'modified\n' >> "$repo/main.py"
  payload=$(jq -cn --arg cwd "$repo" '{session_id:"new-session",cwd:$cwd}')
  run env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" start <<<"$payload"
  [ "$status" -eq 0 ]
  run env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" stop <<<"$payload"
  [ "$status" -eq 2 ]
  [[ "$output" == *'completion evidence and scope required'* ]]
}

@test "task lifecycle permits documentation work and rejects absent baseline" {
  repo="$BATS_TEST_TMPDIR/docs-repo"
  mkdir "$repo"
  git -C "$repo" init -q
  payload=$(jq -cn --arg cwd "$repo" '{session_id:"docs",cwd:$cwd}')
  run env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" stop <<<"$payload"
  [ "$status" -eq 2 ]
  env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" start <<<"$payload"
  printf 'design\n' > "$repo/design.md"
  run env AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/state" python3 "$GOV/task-lifecycle.py" stop <<<"$payload"
  [ "$status" -eq 0 ]
}

@test "approval receipt is scoped, external, immutable to group and unexpired" {
  repo="$BATS_TEST_TMPDIR/approval-repo"; mkdir "$repo"
  receipt="$BATS_TEST_TMPDIR/approval.json"
  printf '%s\n' '{"status":"approved","scope_digest":"digest-1","action":"deploy","environment":"staging","expires_at":"2999-01-01T00:00:00Z","approved_by":"human-fixture"}' > "$receipt"
  sign_receipt "$receipt"
  run bash "$GOV/approval-gate.sh" --repo "$repo" --receipt "$receipt" --digest digest-1 --action deploy --environment staging
  [ "$status" -eq 0 ]
  run bash "$GOV/approval-gate.sh" --repo "$repo" --receipt "$receipt" --digest changed --action deploy --environment staging
  [ "$status" -eq 2 ]
  jq '.action="destroy"' "$receipt" > "$receipt.tampered"; mv "$receipt.tampered" "$receipt"; chmod 600 "$receipt"
  run bash "$GOV/approval-gate.sh" --repo "$repo" --receipt "$receipt" --digest digest-1 --action destroy --environment staging
  [ "$status" -eq 2 ]
  cp "$receipt" "$repo/forged.json"
  run bash "$GOV/approval-gate.sh" --repo "$repo" --receipt "$repo/forged.json" --digest digest-1 --action deploy --environment staging
  [ "$status" -eq 2 ]
}

@test "execution authorization cannot use inline approval for mandatory work" {
  repo="$BATS_TEST_TMPDIR/exec-repo"; mkdir "$repo"
  input=$(jq -cn --arg repo "$repo" '{repo:$repo,phase:"5",request_digest:"digest-1",operation:{action:"deploy",environment:"staging"},human_approval:{status:"approved",scope_digest:"digest-1"},decision:{decision_id:"d",selected_action:"AUTO_EXECUTE",human_approval_required:false,applicable_policy_rules:["mandatory-risk-policy"]}}')
  run bash "$ROOT/runtime/orchestrator/execution-authorize.sh" <<<"$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"BLOCKED"'* ]]
  receipt="$BATS_TEST_TMPDIR/exec-approval.json"
  printf '%s\n' '{"status":"approved","scope_digest":"digest-1","action":"deploy","environment":"staging","expires_at":"2999-01-01T00:00:00Z","approved_by":"human-fixture"}' > "$receipt"; sign_receipt "$receipt"
  input=$(jq -c --arg receipt "$receipt" '.approval_receipt=$receipt' <<<"$input")
  run env AGENT_APPROVAL_PUBLIC_KEY="$BATS_TEST_TMPDIR/signing/public.pem" bash "$ROOT/runtime/orchestrator/execution-authorize.sh" <<<"$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"BLOCKED"'* ]]
}

@test "test review receipt binds finding, commit, and changed tests" {
  tests='["tests/example.bats"]'
  digest=$(printf '%s' "$tests" | shasum -a 256 | awk '{print $1}')
  receipt="$BATS_TEST_TMPDIR/review.json"
  jq -cn --arg digest "$digest" '{status:"approved",reviewer_role:"independent-reviewer",commit:"abc",test_changes_digest:$digest,findings:[],reviewed_at:"2026-10-18T00:00:00Z"}' > "$receipt"
  sign_receipt "$receipt"
  run bash "$GOV/test-review-gate.sh" --repo "$BATS_TEST_TMPDIR/repo" --receipt "$receipt" --commit abc --changes-json "$tests" --trusted-key "$BATS_TEST_TMPDIR/signing/public.pem"
  [ "$status" -eq 0 ]
  run bash "$GOV/test-review-gate.sh" --repo "$BATS_TEST_TMPDIR/repo" --receipt "$receipt" --commit def --changes-json "$tests" --trusted-key "$BATS_TEST_TMPDIR/signing/public.pem"
  [ "$status" -eq 2 ]
  run env AGENT_APPROVAL_PUBLIC_KEY="$BATS_TEST_TMPDIR/signing/public.pem" bash "$GOV/test-review-gate.sh" --repo "$BATS_TEST_TMPDIR/repo" --receipt "$receipt" --commit abc --changes-json "$tests"
  [ "$status" -eq 2 ]
}

@test "shared retry hook survives session and command text changes" {
  state="$BATS_TEST_TMPDIR/retry-state.json"
  for command in 'make test' 'make test --verbose' 'just test'; do
    payload=$(jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command},tool_response:{exit_code:1,output:"FAIL same-root"}}')
    run env AGENT_RETRY_STATE="$state" AGENT_TASK_ID=stable-task bash "$GOV/retry-hook.sh" post <<<"$payload"
  done
  [ "$status" -eq 2 ]
  run env AGENT_RETRY_STATE="$state" AGENT_TASK_ID=stable-task bash "$GOV/retry-hook.sh" pre <<<'{"tool_name":"Bash","tool_input":{"command":"another command"}}'
  [ "$status" -eq 2 ]
}

@test "provider failure event increments the shared retry budget" {
  state="$BATS_TEST_TMPDIR/failure-event.json"
  payload='{"tool_name":"Bash","error":"command failed"}'
  for attempt in 1 2 3; do
    run env AGENT_RETRY_STATE="$state" AGENT_TASK_ID=failure-task bash "$GOV/retry-hook.sh" failure <<<"$payload"
  done
  [ "$status" -eq 2 ]
  run jq -e '.tasks["failure-task"].attempts == 3 and .tasks["failure-task"].status == "BLOCKED"' "$state"
  [ "$status" -eq 0 ]
}

@test "retry hook fails closed without an explicit or lifecycle task identity" {
  payload='{"tool_name":"Bash","tool_input":{"command":"false"},"tool_response":{"exit_code":1,"output":"FAIL fixture"}}'
  run env -u AGENT_TASK_ID AGENT_TASK_STATE_DIR="$BATS_TEST_TMPDIR/missing" AGENT_RETRY_STATE="$BATS_TEST_TMPDIR/retry.json" bash "$GOV/retry-hook.sh" post <<<"$payload"
  [ "$status" -eq 2 ]
  [[ "$output" == *"task identity unavailable"* ]]
}

@test "lifecycle task identity preserves retry budget across provider sessions" {
  repo="$BATS_TEST_TMPDIR/retry-repo"; mkdir "$repo"; git -C "$repo" init -q
  state_dir="$BATS_TEST_TMPDIR/tasks"; retry_state="$BATS_TEST_TMPDIR/retries.json"
  start=$(jq -cn --arg cwd "$repo" '{session_id:"session-one",cwd:$cwd}')
  env AGENT_TASK_STATE_DIR="$state_dir" python3 "$GOV/task-lifecycle.py" start <<<"$start"
  payload='{"tool_name":"Bash","tool_response":{"exit_code":1,"output":"FAIL same cause"}}'
  for session in one two three; do
    run env -u AGENT_TASK_ID AGENT_TASK_STATE_DIR="$state_dir" AGENT_RETRY_STATE="$retry_state" bash -c "cd '$repo' && bash '$GOV/retry-hook.sh' post" <<<"$payload"
  done
  [ "$status" -eq 2 ]
  run jq -e '[.tasks[].attempts] == [3] and [.tasks[].status] == ["BLOCKED"]' "$retry_state"
  [ "$status" -eq 0 ]
}

@test "non-code stop cannot rotate a blocked retry identity" {
  repo="$BATS_TEST_TMPDIR/blocked-repo"; mkdir "$repo"; git -C "$repo" init -q
  state_dir="$BATS_TEST_TMPDIR/blocked-tasks"; retry_state="$BATS_TEST_TMPDIR/blocked-retries.json"
  payload=$(jq -cn --arg cwd "$repo" '{session_id:"blocked",cwd:$cwd}')
  env AGENT_TASK_STATE_DIR="$state_dir" python3 "$GOV/task-lifecycle.py" start <<<"$payload"
  task=$(jq -r .task_id "$state_dir"/*.json)
  for attempt in 1 2 3; do bash "$GOV/retry-budget.sh" record "$retry_state" "$task" fail fixture >/dev/null || true; done
  run env AGENT_TASK_STATE_DIR="$state_dir" AGENT_RETRY_STATE="$retry_state" python3 "$GOV/task-lifecycle.py" stop <<<"$payload"
  [ "$status" -eq 2 ]
  [[ "$output" == *'retry budget remains BLOCKED'* ]]
  [ "$(jq -r .task_id "$state_dir"/*.json)" = "$task" ]
}

@test "traceability cross-check rejects PRD state mismatch and accepts matching state" {
  mkdir -p "$BATS_TEST_TMPDIR/prd"
  printf '### FR-X — Fixture\n\n- Status: ready\n' > "$BATS_TEST_TMPDIR/prd/fixture.md"
  printf 'repository\trevision\tphase\trequirement_id\tstatus\tdesign\timplementation\ttest\tverification\nself\tWORKTREE\t0\tFR-X\tready\tprd/fixture.md\t-\tfixture.test\t-\n' > "$BATS_TEST_TMPDIR/trace.tsv"
  run bash "$ROOT/runtime/orchestrator/traceability-gate.sh" "$BATS_TEST_TMPDIR/trace.tsv" --repo-root "$BATS_TEST_TMPDIR" --prd-root "$BATS_TEST_TMPDIR/prd"
  [ "$status" -eq 0 ]
  sed 's/WORKTREE\t0\tFR-X\tready/deadbeef\t0\tFR-X\timplemented/' "$BATS_TEST_TMPDIR/trace.tsv" > "$BATS_TEST_TMPDIR/mismatch.tsv"
  run bash "$ROOT/runtime/orchestrator/traceability-gate.sh" "$BATS_TEST_TMPDIR/mismatch.tsv" --repo-root "$BATS_TEST_TMPDIR" --prd-root "$BATS_TEST_TMPDIR/prd"
  [ "$status" -eq 2 ]
}

@test "MCP audit records UNKNOWN on timeout and never success" {
  target="$BATS_TEST_TMPDIR/mcp.jsonl"
  payload='{"tool_name":"mcp__context7__query-docs","tool_response":{"isError":true,"error":"timeout"}}'
  run env AGENT_DECISION_ID=decision-1 AGENT_OPERATION_ID=operation-1 AGENT_REQUEST_FINGERPRINT=fingerprint-1 AGENT_MCP_AUDIT_PATH="$target" AGENT_ROLE=researcher AGENT_SKILL=skl-pre-research-ljh bash "$GOV/mcp-hook.sh" post <<<"$payload"
  [ "$status" -eq 0 ]
  run jq -e '.status == "UNKNOWN" and .server == "context7" and .role == "researcher" and .decision_id == "decision-1" and .operation_id == "operation-1"' "$target"
  [ "$status" -eq 0 ]
}

@test "MCP hook derives request-scoped correlation for native provider payloads" {
  target="$BATS_TEST_TMPDIR/native-mcp.jsonl"
  payload='{"session_id":"session-1","tool_use_id":"call-1","tool_name":"mcp__context7__query-docs","tool_input":{"topic":"nix"},"tool_response":{"content":"fixture"}}'
  run env -u AGENT_DECISION_ID -u AGENT_OPERATION_ID -u AGENT_REQUEST_FINGERPRINT AGENT_MCP_AUDIT_PATH="$target" AGENT_ROLE=researcher AGENT_SKILL=skl-pre-research-ljh AGENT_PROJECT_POLICY="$ROOT/tests/fixtures/project-policy.json" bash "$GOV/mcp-hook.sh" post <<<"$payload"
  [ "$status" -eq 0 ]
  run jq -e '.decision_id == "session:session-1" and .operation_id == "call-1" and (.request_fingerprint | length == 64)' "$target"
  [ "$status" -eq 0 ]
}

@test "memory lock and common PII values fail closed" {
  root="$BATS_TEST_TMPDIR/memory"
  mkdir -p "$root/.locks" "$root/.locks/project-session-entry.lock"
  run bash "$GOV/memory-lifecycle.sh" write "$root" project session entry '{"fact":"fixture"}'
  [ "$status" -eq 2 ]
  rmdir "$root/.locks/project-session-entry.lock"
  run bash "$GOV/memory-lifecycle.sh" write "$root" project session entry '{"contact":"person@example.com"}'
  [ "$status" -eq 2 ]
  run env AGENT_MEMORY_POLICY="$ROOT/tests/fixtures/memory-policy.json" bash "$GOV/memory-lifecycle.sh" write "$root" project session entry '{"contact":"010-1234-5678"}'
  [ "$status" -eq 2 ]
}

@test "memory promotion fails closed when its destination is locked" {
  root="$BATS_TEST_TMPDIR/promotion-memory"
  bash "$GOV/memory-lifecycle.sh" write "$root" project session entry '{"fact":"fixture"}'
  mkdir -p "$root/.locks/project-durable-entry.lock"
  run bash "$GOV/memory-lifecycle.sh" promote "$root" project session entry durable
  [ "$status" -eq 2 ]
  [ ! -e "$root/project/durable/entry.json" ]
}

@test "Codex and Gemini lifecycle adapters include start and blocking stop" {
  run rg -n 'SessionStart|task-lifecycle.py start|task-lifecycle.py stop' "$ROOT/nix/agents/providers/codex/render.nix"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SessionStart'* && "$output" == *'task-lifecycle.py start'* && "$output" == *'task-lifecycle.py stop'* ]]
  run rg -n 'BeforeAgent|AfterAgent|task-lifecycle.py start|task-lifecycle.py stop' "$ROOT/nix/agents/providers/gemini/render.nix"
  [ "$status" -eq 0 ]
  [[ "$output" == *'BeforeAgent'* && "$output" == *'AfterAgent'* && "$output" == *'task-lifecycle.py start'* && "$output" == *'task-lifecycle.py stop'* ]]
  run rg -n 'AgentSpawn|PreToolUse|PostToolUse|engineering-completion|kiro-stop.sh' "$ROOT/nix/agents/providers/kiro/module.nix"
  [ "$status" -eq 0 ]
  run jq -e '.hooks.PostToolUseFailure[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("retry-hook.sh failure"))' "$ROOT/nix/agents/providers/claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "completion boundary ignores caller-selected review key" {
  repo="$BATS_TEST_TMPDIR/review-repo"; mkdir "$repo"
  git -C "$repo" init -q; git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
  printf 'base\n' > "$repo/base"; git -C "$repo" add base; git -C "$repo" commit -qm base
  baseline=$(git -C "$repo" rev-parse HEAD)
  mkdir "$repo/tests"; printf 'fixture\n' > "$repo/tests/example.bats"; git -C "$repo" add .; git -C "$repo" commit -qm fixture
  evidence="$BATS_TEST_TMPDIR/review-evidence.json"
  run python3 "$GOV/record-verification.py" --repo "$repo" --output "$evidence" --baseline "$baseline" --requirement FR-013 -- bash -c 'printf "tests passed"'
  [ "$status" -eq 2 ]
  run jq -e '.status == "REVIEW_REQUIRED"' "$evidence"; [ "$status" -eq 0 ]
  printf 'tests/example.bats\n' > "$BATS_TEST_TMPDIR/review-scope"
  changes=$(jq -c '.test_changes_requiring_review | sort' "$evidence")
  digest=$(printf '%s' "$changes" | shasum -a 256 | awk '{print $1}')
  commit=$(git -C "$repo" rev-parse HEAD)
  receipt="$BATS_TEST_TMPDIR/test-review.json"
  jq -cn --arg digest "$digest" --arg commit "$commit" '{status:"approved",reviewer_role:"independent-reviewer",commit:$commit,test_changes_digest:$digest,findings:[],reviewed_at:"2026-10-18T00:00:00Z"}' > "$receipt"; chmod 600 "$receipt"
  sign_receipt "$receipt"
  run env AGENT_TEST_REVIEW_RECEIPT="$receipt" bash "$GOV/completion-gate.sh" --repo "$repo" --scope "$BATS_TEST_TMPDIR/review-scope" --evidence "$evidence"
  [ "$status" -eq 2 ]
  [[ "$output" == *'test review gate: missing input'* ]]
}

@test "native conformance records unavailable providers without treating them as pass" {
  report="$BATS_TEST_TMPDIR/native.json"
  run env AGENT_PROVIDER_PATH=/nonexistent bash "$GOV/provider-native-conformance.sh" --output "$report" --repo "$ROOT"
  [ "$status" -eq 0 ]
  run jq -e '.status == "COMPLETE_WITH_EXPLICIT_GAPS" and ([.providers[] | select(.status == "UNAVAILABLE")] | length == 4) and ([.providers[] | select(.status | test("VERIFIED$"))] | length == 0)' "$report"
  [ "$status" -eq 0 ]
}

@test "native conformance does not mistake Codex startup failure for sandbox denial" {
  bindir="$BATS_TEST_TMPDIR/bin"; mkdir "$bindir"
  cat > "$bindir/codex" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && { echo 'codex-fixture 1'; exit 0; }
exit 2
SH
  chmod +x "$bindir/codex"
  report="$BATS_TEST_TMPDIR/native-startup-failure.json"
  run env AGENT_PROVIDER_PATH="$bindir" bash "$GOV/provider-native-conformance.sh" --output "$report" --repo "$ROOT"
  [ "$status" -eq 2 ]
  run jq -e '.providers[] | select(.provider == "codex") | .status == "FAILED" and (.evidence | contains("startup")) and .command_result == "harmless=2"' "$report"
  [ "$status" -eq 0 ]
}

@test "native conformance binds generated and source digests without treating exit 134 as denial" {
  generated="$BATS_TEST_TMPDIR/generated"; mkdir "$generated"
  printf '{"source_digest":"%064d"}\n' 0 > "$generated/manifest.json"
  bindir="$BATS_TEST_TMPDIR/abort-bin"; mkdir "$bindir"
  cat > "$bindir/codex" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && { echo 'codex-fixture 134'; exit 0; }
exit 134
SH
  chmod +x "$bindir/codex"
  report="$BATS_TEST_TMPDIR/native-bound.json"
  run env AGENT_PROVIDER_PATH="$bindir" bash "$GOV/provider-native-conformance.sh" --output "$report" --repo "$ROOT" --generated "$generated"
  [ "$status" -eq 0 ]
  expected=$(shasum -a 256 "$generated/manifest.json" | awk '{print $1}')
  run jq -e --arg generated "$expected" --arg activated "$(cd "$generated" && pwd -P)" '
    .source_digest == ("0" * 64)
    and .generated_digest == $generated
    and .activated_path == $activated
    and (.providers[] | select(.provider == "codex") | .status == "UNAVAILABLE" and .command_result == "harmless=134")
  ' "$report"
  [ "$status" -eq 0 ]
}
