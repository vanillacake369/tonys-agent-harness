#!/usr/bin/env bash
# Verify an independent review receipt for changed tests.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO= RECEIPT= COMMIT= CHANGES= TRUSTED_KEY=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO=$2; shift 2;; --receipt) RECEIPT=$2; shift 2;;
    --commit) COMMIT=$2; shift 2;; --changes-json) CHANGES=$2; shift 2;;
    --trusted-key) TRUSTED_KEY=$2; shift 2;;
    *) echo "test review gate: invalid argument" >&2; exit 2;;
  esac
done
[[ -n "$REPO" && -f "$RECEIPT" && -n "$COMMIT" && -f "$TRUSTED_KEY" ]] || { echo "test review gate: missing input" >&2; exit 2; }
normalized=$(jq -c 'if type == "array" and all(.[]; type == "string") then sort else error("invalid") end' <<<"$CHANGES" 2>/dev/null) || {
  echo "test review gate: invalid changes" >&2; exit 2;
}
digest=$(printf '%s' "$normalized" | shasum -a 256 | awk '{print $1}')
# Reuse external location, ownership, permissions, and expiry semantics with a
# synthetic review scope. Review receipts intentionally require no future expiry.
repo_real=$(cd "$REPO" 2>/dev/null && pwd -P || { mkdir -p "$REPO" && cd "$REPO" && pwd -P; })
receipt_real=$(cd "$(dirname "$RECEIPT")" && pwd -P)/$(basename "$RECEIPT")
case "$receipt_real" in "$repo_real"|"$repo_real"/*) echo "test review gate: receipt must be external" >&2; exit 2;; esac
mode=$(stat -c '%a' "$receipt_real" 2>/dev/null || stat -f '%Lp' "$receipt_real" 2>/dev/null || true)
[[ "$mode" == 600 || "$mode" == 400 ]] || { echo "test review gate: private receipt required" >&2; exit 2; }
env -u AGENT_APPROVAL_PUBLIC_KEY AGENT_APPROVAL_PUBLIC_KEY="$TRUSTED_KEY" \
  "$ROOT/receipt-signature-gate.sh" "$receipt_real" >/dev/null
if ! jq -e --arg commit "$COMMIT" --arg digest "$digest" '
  .status == "approved" and .reviewer_role == "independent-reviewer" and
  .commit == $commit and .test_changes_digest == $digest and
  (.findings | type == "array") and (.reviewed_at | type == "string" and length > 0)
' "$receipt_real" >/dev/null; then
  echo "test review gate: receipt binding mismatch" >&2; exit 2
fi
echo "test review gate passed"
