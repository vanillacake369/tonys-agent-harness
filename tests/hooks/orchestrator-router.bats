#!/usr/bin/env bats

setup() {
  ROUTER="$BATS_TEST_DIRNAME/../../runtime/orchestrator/route.sh"
  GATE="$BATS_TEST_DIRNAME/../../runtime/orchestrator/traceability-gate.sh"
  PLAN="$BATS_TEST_DIRNAME/../../runtime/orchestrator/execution-plan.sh"
  SUMMARY="$BATS_TEST_DIRNAME/../../runtime/orchestrator/telemetry-summary.sh"
  PRD_GATE="$BATS_TEST_DIRNAME/../../scripts/prd-presence-gate.sh"
  export AGENT_TELEMETRY_PATH="$BATS_TEST_TMPDIR/router-telemetry.jsonl"
}

@test "complex request selects full route and human approval" {
  run "$ROUTER" "migrate production database with rollback and SLO"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"complexity":"complex"'* ]]
  [[ "$output" == *'"selected_route":"full"'* ]]
  [[ "$output" == *'"human_approval_required":true'* ]]
}

@test "ordinary feature selects standard route without approval" {
  run "$ROUTER" "add a feature and tests to several files"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"complexity":"standard"'* ]]
  [[ "$output" == *'"selected_route":"standard"'* ]]
  [[ "$output" == *'"human_approval_required":false'* ]]
  [[ "$output" == *'"cmd-vpp-work-ljh"'* ]]
  [[ "$output" == *'"skl-pre-prd-ljh"'* ]]
  [[ "$output" == *'"skl-mid-impl-ljh"'* ]]
  [[ "$output" != *'"to-prd"'* ]]
}

@test "simple wording selects trivial route" {
  run "$ROUTER" "rename this variable"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"complexity":"trivial"'* ]]
}

@test "complete traceability passes" {
  file="$BATS_TEST_TMPDIR/traceability.tsv"
  artifact="$BATS_TEST_TMPDIR/artifact.md"
  printf 'persisted fixture evidence\n' > "$artifact"
  printf 'requirement_id\tstatus\tdesign\tcode\ttest\tverification\nFR-001\tverified\t%s\t%s\t%s\t%s\n' "$artifact" "$artifact" "$artifact" "$artifact" > "$file"
  run "$GATE" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'traceability gate passed: 1 requirements'* ]]
}

@test "incomplete traceability fails closed" {
  file="$BATS_TEST_TMPDIR/traceability.tsv"
  printf 'requirement_id\tstatus\tdesign\tcode\ttest\tverification\nFR-001\tverified\tdesign.md:10\t-\ttest/a.bats:4\tjust test\n' > "$file"
  run "$GATE" "$file"
  [ "$status" -eq 2 ]
  [[ "$output" == *'missing traceability field 4'* ]]
}

@test "proposed requirement does not require implementation evidence" {
  file="$BATS_TEST_TMPDIR/traceability-proposed.tsv"
  printf 'requirement_id\tstatus\tdesign\tcode\ttest\tverification\nFR-002\tproposed\tdesign.md:20\t-\t-\t-\n' > "$file"
  run "$GATE" "$file"
  [ "$status" -eq 0 ]
}

@test "implemented requirement requires every evidence field" {
  file="$BATS_TEST_TMPDIR/traceability-implemented.tsv"
  printf 'requirement_id\tstatus\tdesign\tcode\ttest\tverification\nFR-003\timplemented\tdesign.md:30\tsrc/a.nix:3\t-\tjust test\n' > "$file"
  run "$GATE" "$file"
  [ "$status" -eq 2 ]
  [[ "$output" == *'missing traceability field 5'* ]]
}

@test "unknown requirement status fails closed" {
  file="$BATS_TEST_TMPDIR/traceability-unknown.tsv"
  printf 'requirement_id\tstatus\tdesign\tcode\ttest\tverification\nFR-004\tunknown\tdesign.md:40\t-\t-\t-\n' > "$file"
  run "$GATE" "$file"
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown status'* ]]
}

@test "decision engine selects safe actions" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"decision_id":"dec-1","request":"rename a local variable","llm_judgment":{"recommended_action":"AUTO_EXECUTE","risk_level":"low","uncertainty_level":"low"},"policy_signals":{"destructive":false,"security_sensitive":false,"migration":false,"deployment":false,"external_resource":false,"money_movement":false}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"AUTO_EXECUTE"'* ]]
}

@test "mandatory policy overrides LLM auto execute" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"decision_id":"dec-2","request":"drop production table","policy_signals":{"destructive":true,"security_sensitive":false,"migration":false,"deployment":false,"external_resource":false,"money_movement":false},"llm_judgment":{"recommended_action":"AUTO_EXECUTE","risk_level":"low","uncertainty_level":"low"}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"HUMAN_APPROVAL"'* ]]
}

@test "matching scoped approval permits the requested risky action" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"decision_id":"dec-approval","request":"drop production table","request_digest":"scope-1","policy_signals":{"destructive":true,"security_sensitive":false,"migration":false,"deployment":false,"external_resource":false,"money_movement":false},"human_approval":{"status":"approved","scope_digest":"scope-1"},"llm_judgment":{"recommended_action":"AUTO_EXECUTE","risk_level":"low","uncertainty_level":"low"}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"AUTO_EXECUTE"'* ]]
}

@test "approval scope mismatch requires re-approval" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"decision_id":"dec-scope","request":"drop production table","request_digest":"scope-new","policy_signals":{"destructive":true,"security_sensitive":false,"migration":false,"deployment":false,"external_resource":false,"money_movement":false},"human_approval":{"status":"approved","scope_digest":"scope-old"},"llm_judgment":{"recommended_action":"AUTO_EXECUTE","risk_level":"low","uncertainty_level":"low"}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"HUMAN_APPROVAL"'* ]]
}

@test "required question takes precedence over auto execute" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"decision_id":"dec-question","request":"implement booking cancellation","llm_judgment":{"recommended_action":"AUTO_EXECUTE","risk_level":"low","uncertainty_level":"low","required_questions":["cancellation cutoff"]},"policy_signals":{"destructive":false,"security_sensitive":false,"migration":false,"deployment":false,"external_resource":false,"money_movement":false}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"SPEC_QUESTION"'* ]]
}

@test "policy engine error blocks even when LLM says auto execute" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"decision_id":"dec-policy-error","request":"rename a local variable","policy_signals":{"destructive":false,"security_sensitive":false,"migration":false,"deployment":false,"external_resource":false,"money_movement":false,"policy_engine_error":true},"llm_judgment":{"recommended_action":"AUTO_EXECUTE","risk_level":"low","uncertainty_level":"low"}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"BLOCKED"'* ]]
}

@test "missing policy information blocks safely" {
  run "$BATS_TEST_DIRNAME/../../runtime/orchestrator/decision.sh" <<'JSON'
{"request":"change infrastructure"}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selected_action":"BLOCKED"'* ]]
}

@test "telemetry records minimum decision evidence without prompt" {
  decision='{"decision_id":"dec-3","selected_action":"RESEARCH_REQUIRED","risk_level":"medium","uncertainty_level":"medium","route":"standard","provider":"codex","workflow_names":["repository-archaeology"],"human_approval_required":false,"evidence_references":["repo:README.md"],"result":"selected"}'
  file="$BATS_TEST_TMPDIR/telemetry.jsonl"
  run bash -c "printf '%s\\n' '$decision' | '$BATS_TEST_DIRNAME/../../runtime/orchestrator/telemetry.sh' '$file'"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$file")" -eq 1 ]
  ! grep -q 'prompt' "$file"
}

@test "risk-bearing changed files require a PRD" {
  run bash -c "printf '%s\\n' 'nix/agents/contract-roles.nix' | '$PRD_GATE' --files"
  [ "$status" -eq 2 ]
  [[ "$output" == *'require a docs/agent/prd/*.md artifact'* ]]
}

@test "execution plan blocks complex work until scoped approval exists" {
  run "$PLAN" <<'JSON'
{"phase":"3","request_digest":"scope-1","decision":{"decision_id":"dec-1","selected_action":"HUMAN_APPROVAL","human_approval_required":true}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"BLOCKED"'* ]]
}

@test "execution plan accepts only matching approval scope" {
  run "$PLAN" <<'JSON'
{"phase":"3","request_digest":"scope-1","human_approval":{"status":"approved","scope_digest":"scope-1"},"decision":{"decision_id":"dec-2","selected_action":"AUTO_EXECUTE","human_approval_required":false}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"READY_TO_EXECUTE"'* ]]
}

@test "phase five remains blocked without approval even for auto execute" {
  run "$PLAN" <<'JSON'
{"phase":"5","request_digest":"scope-5","decision":{"decision_id":"dec-5","selected_action":"AUTO_EXECUTE","human_approval_required":false}}
JSON
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"BLOCKED"'* ]]
}

@test "telemetry summary reports actions and never enables policy learning" {
  file="$BATS_TEST_TMPDIR/summary.jsonl"
  printf '%s\n' '{"selected_action":"AUTO_EXECUTE","route":"trivial"}' '{"selected_action":"HUMAN_APPROVAL","route":"full"}' > "$file"
  run "$SUMMARY" "$file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"events":2'* ]]
  [[ "$output" == *'"policy_learning":false'* ]]
}

@test "risk-bearing changed files pass with a PRD" {
  run bash -c "printf '%s\\n' 'nix/agents/contract-roles.nix' 'docs/agent/prd/change.md' | '$PRD_GATE' --files"
  [ "$status" -eq 0 ]
  [[ "$output" == *'include a PRD'* ]]
}

@test "non-risk documentation changes do not require a PRD" {
  run bash -c "printf '%s\\n' 'README.md' 'tests/hooks/example.bats' | '$PRD_GATE' --files"
  [ "$status" -eq 0 ]
  [[ "$output" == *'no risk-bearing changes'* ]]
}
