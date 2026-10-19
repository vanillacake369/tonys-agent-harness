#!/usr/bin/env bash
# Validate a human-created receipt stored outside the repository workspace.
set -euo pipefail
REPO= RECEIPT= DIGEST= ACTION= ENVIRONMENT=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO=$2; shift 2;; --receipt) RECEIPT=$2; shift 2;;
    --digest) DIGEST=$2; shift 2;; --action) ACTION=$2; shift 2;;
    --environment) ENVIRONMENT=$2; shift 2;; *) echo "approval gate: invalid argument" >&2; exit 2;;
  esac
done
[[ -d "$REPO" && -f "$RECEIPT" && -n "$DIGEST" && -n "$ACTION" && -n "$ENVIRONMENT" ]] || {
  echo "approval gate: complete scoped input required" >&2; exit 2;
}
repo_real=$(cd "$REPO" && pwd -P)
receipt_dir=$(cd "$(dirname "$RECEIPT")" && pwd -P)
receipt_real="$receipt_dir/$(basename "$RECEIPT")"
case "$receipt_real" in "$repo_real"|"$repo_real"/*) echo "approval gate: receipt must be outside repository" >&2; exit 2;; esac
mode=$(stat -f '%Lp' "$receipt_real" 2>/dev/null || stat -c '%a' "$receipt_real" 2>/dev/null || true)
[[ "$mode" == 600 || "$mode" == 400 ]] || { echo "approval gate: receipt must be private and immutable to peers" >&2; exit 2; }
owner=$(stat -f '%u' "$receipt_real" 2>/dev/null || stat -c '%u' "$receipt_real")
[[ "$owner" == "$(id -u)" ]] || { echo "approval gate: receipt owner mismatch" >&2; exit 2; }
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/receipt-signature-gate.sh" "$receipt_real" >/dev/null
if ! jq -e --arg digest "$DIGEST" --arg action "$ACTION" --arg environment "$ENVIRONMENT" '
  type == "object" and .status == "approved" and .scope_digest == $digest and
  .action == $action and .environment == $environment and
  (.approved_by | type == "string" and length > 0) and
  (.expires_at | type == "string" and length > 0)
' "$receipt_real" >/dev/null; then
  echo "approval gate: receipt scope or schema mismatch" >&2; exit 2
fi
expires=$(jq -r .expires_at "$receipt_real")
python3 - "$expires" <<'PY' || { echo "approval gate: receipt expired or invalid" >&2; exit 2; }
from datetime import datetime, timezone
import sys
expires = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
raise SystemExit(0 if expires > datetime.now(timezone.utc) else 2)
PY
echo "approval gate passed: scoped external receipt"
