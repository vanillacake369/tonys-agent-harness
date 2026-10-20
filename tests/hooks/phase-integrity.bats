#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  GOV="$ROOT/runtime/governance"
}

@test "TDD evidence requires a failing Red before passing Green" {
  valid='{"requirement_id":"PH-0302","red":{"sequence":1,"command":"python -m unittest","exit_code":1,"result":"expected failure","executed_commit":"base"},"green":{"sequence":2,"command":"python -m unittest","exit_code":0,"result":"passed","executed_commit":"head"},"exemption":null}'
  run "$GOV/tdd-evidence-gate.sh" --requirements-json '["PH-0302"]' --baseline base --green-commit head <<<"$valid"
  [ "$status" -eq 0 ]
  run "$GOV/tdd-evidence-gate.sh" --requirements-json '["PH-0302"]' --baseline base --green-commit head <<<"$(jq '.red.exit_code=0' <<<"$valid")"
  [ "$status" -eq 2 ]
  run "$GOV/tdd-evidence-gate.sh" --requirements-json '["PH-0302"]' --baseline base --green-commit head <<<"$(jq '.green.sequence=1' <<<"$valid")"
  [ "$status" -eq 2 ]
  run "$GOV/tdd-evidence-gate.sh" --requirements-json '["OTHER"]' --baseline base --green-commit head <<<"$valid"
  [ "$status" -eq 2 ]
}

@test "commit planner derives style and blocks staged files outside scope" {
  repo="$BATS_TEST_TMPDIR/repo"; mkdir "$repo"
  git -C "$repo" init -q; git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
  printf 'base\n' > "$repo/base"; git -C "$repo" add base; git -C "$repo" commit -qm 'feat(core): establish base'
  printf 'a\n' > "$repo/a.py"; printf 'b\n' > "$repo/b.py"; git -C "$repo" add a.py b.py
  printf 'a.py\n' > "$BATS_TEST_TMPDIR/scope"
  run python3 "$GOV/commit-plan.py" --repo "$repo" --scope "$BATS_TEST_TMPDIR/scope" --requirement PH-0303
  [ "$status" -eq 2 ]
  [[ "$output" == *'b.py'* ]]
  git -C "$repo" restore --staged b.py
  run python3 "$GOV/commit-plan.py" --repo "$repo" --scope "$BATS_TEST_TMPDIR/scope" --requirement PH-0303
  [ "$status" -eq 0 ]
  plan="$output"
  run jq -e '.subject_style == "conventional" and .baseline_commit != "" and .requirements == ["PH-0303"] and (.commits | length == 1) and .commits[0].files == ["a.py"] and (.commits[0].staged_diff_sha256["a.py"] | length == 64)' <<<"$plan"
  [ "$status" -eq 0 ]
  git -C "$repo" commit -qm 'feat(core): add a'
  commit=$(git -C "$repo" rev-parse HEAD)
  jq --arg commit "$commit" '.commits[0].result_commit=$commit' <<<"$plan" > "$BATS_TEST_TMPDIR/plan.json"
  run python3 "$GOV/commit-plan.py" --repo "$repo" --verify-plan "$BATS_TEST_TMPDIR/plan.json"
  [ "$status" -eq 0 ]
  run jq -e '.status == "VERIFIED" and .bindings[0].requirements == ["PH-0303"] and .bindings[0].files == ["a.py"]' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "memory expiry and optimistic revision conflicts fail closed" {
  memory="$GOV/memory-lifecycle.sh"; root="$BATS_TEST_TMPDIR/memory"
  run "$memory" write "$root" project session expired '{"fact":"old"}' '2000-01-01T00:00:00Z'
  [ "$status" -eq 0 ]
  run "$memory" read "$root" project session expired
  [ "$status" -eq 2 ]
  run jq -e '.confidence == "expired"' "$root/project/session/expired.json"
  [ "$status" -eq 0 ]
  run "$memory" write "$root" project durable fact '{"fact":"one"}' '2099-01-01T00:00:00Z'
  [ "$status" -eq 0 ]
  run "$memory" write "$root" project durable fact '{"fact":"two"}' '2099-01-01T00:00:00Z'
  [ "$status" -eq 2 ]
  run "$memory" write "$root" project durable fact '{"fact":"two"}' '2099-01-01T00:00:00Z' 1
  [ "$status" -eq 0 ]
  run jq -e '.revision == 2 and .content.fact == "two"' "$root/project/durable/fact.json"
  [ "$status" -eq 0 ]
  run "$memory" promote "$root" project session expired durable
  [ "$status" -eq 2 ]
  run "$memory" write "$root" project session promoted '{"fact":"new"}' '2099-01-01T00:00:00Z'
  [ "$status" -eq 0 ]
  run "$memory" write "$root" project durable promoted '{"fact":"existing"}' '2099-01-01T00:00:00Z'
  [ "$status" -eq 0 ]
  run "$memory" promote "$root" project session promoted durable
  [ "$status" -eq 2 ]
  run "$memory" promote "$root" project session promoted durable 1
  [ "$status" -eq 0 ]
}
