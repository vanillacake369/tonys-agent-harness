#!/usr/bin/env bash
# Single deterministic completion boundary: evidence first, then Git lifecycle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=.; MODE=code; SCOPE=; EVIDENCE=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO=$2; shift 2;; --mode) MODE=$2; shift 2;;
    --scope) SCOPE=$2; shift 2;; --evidence) EVIDENCE=$2; shift 2;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
[[ -n "$EVIDENCE" ]] || { echo "completion gate: evidence is required" >&2; exit 2; }
if ! jq -e '.status == "DONE" or .status == "REVIEW_REQUIRED"' "$EVIDENCE" >/dev/null 2>&1; then
  echo "completion gate: DONE or independently reviewable evidence is required" >&2; exit 2
fi
if [[ "$MODE" == design ]]; then
  if ! jq -e '.mode == "design" and (.artifacts | type == "array" and length > 0) and
    all(.artifacts[]; type == "string" and length > 0) and
    (.unresolved_errors | type == "array" and length == 0)' "$EVIDENCE" >/dev/null; then
    echo "design completion blocked: missing artifacts or unresolved errors" >&2; exit 2
  fi
  while IFS= read -r artifact; do
    [[ "$artifact" != /* && "$artifact" != *..* && -f "$REPO/$artifact" ]] || {
      echo "design completion blocked: invalid artifact" >&2; exit 2;
    }
  done < <(jq -r '.artifacts[]' "$EVIDENCE")
  "$ROOT/git-lifecycle-gate.sh" --repo "$REPO" --mode design
  exit 0
fi
"$ROOT/evidence-gate.sh" "$EVIDENCE"
TDD_EVIDENCE=${AGENT_TDD_EVIDENCE:-}
[[ -n "$TDD_EVIDENCE" && -f "$TDD_EVIDENCE" ]] || {
  echo "completion blocked: Red-before-Green TDD evidence required" >&2; exit 2;
}
"$ROOT/tdd-evidence-gate.sh" < "$TDD_EVIDENCE" >/dev/null
"$ROOT/git-lifecycle-gate.sh" --repo "$REPO" --mode "$MODE" --scope "$SCOPE" --evidence "$EVIDENCE"
if [[ "$MODE" == code ]] && ! jq -e '. as $e | .worktree_clean == true and
  all(.commands[]; .executed_commit == $e.commit)' "$EVIDENCE" >/dev/null; then
  echo "completion blocked: missing snapshot binding or unresolved test review" >&2
  exit 2
fi
test_changes=$(jq -c '.test_changes_requiring_review // []' "$EVIDENCE")
if [[ "$test_changes" != '[]' ]]; then
  receipt=${AGENT_TEST_REVIEW_RECEIPT:-}
  [[ -n "$receipt" ]] || { echo "completion blocked: independent test review required" >&2; exit 2; }
  trusted_home=$(python3 - <<'PY'
import os, pwd
print(pwd.getpwuid(os.getuid()).pw_dir)
PY
  )
  trusted_key="$trusted_home/.config/agents/trust/approval-public.pem"
  "$ROOT/test-review-gate.sh" --repo "$REPO" --receipt "$receipt" \
    --commit "$(jq -r .commit "$EVIDENCE")" --changes-json "$test_changes" \
    --trusted-key "$trusted_key"
fi
if [[ "$(jq -r .status "$EVIDENCE")" == REVIEW_REQUIRED && "$test_changes" == '[]' ]]; then
  echo "completion blocked: review status has no reviewable test changes" >&2; exit 2
fi
echo "completion gate passed"
