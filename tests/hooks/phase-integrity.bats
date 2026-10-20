#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  GOV="$ROOT/runtime/governance"
}

@test "TDD evidence requires a failing Red before passing Green" {
  valid='{"requirement_id":"PH-0302","red":{"sequence":1,"command":"python -m unittest","exit_code":1,"result":"expected failure"},"green":{"sequence":2,"command":"python -m unittest","exit_code":0,"result":"passed"},"exemption":null}'
  run "$GOV/tdd-evidence-gate.sh" <<<"$valid"
  [ "$status" -eq 0 ]
  run "$GOV/tdd-evidence-gate.sh" <<<"$(jq '.red.exit_code=0' <<<"$valid")"
  [ "$status" -eq 2 ]
  run "$GOV/tdd-evidence-gate.sh" <<<"$(jq '.green.sequence=1' <<<"$valid")"
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
  run jq -e '.subject_style == "conventional" and .baseline_commit != "" and .requirements == ["PH-0303"] and (.commits | length == 1) and .commits[0].files == ["a.py"]' <<<"$output"
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
}
