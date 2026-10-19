#!/usr/bin/env bash
# Verify a canonical JSON receipt signed by a human-controlled RSA private key.
set -euo pipefail
RECEIPT=${1:-}
PUBLIC_KEY=${AGENT_APPROVAL_PUBLIC_KEY:-}
[[ -f "$RECEIPT" && -f "$PUBLIC_KEY" ]] || {
  echo "receipt signature gate: receipt and trusted public key required" >&2; exit 2;
}
if ! jq -e '.signature.algorithm == "rsa-sha256" and
  (.signature.key_id | type == "string" and length == 64) and
  (.signature.value | type == "string" and length > 0)' "$RECEIPT" >/dev/null 2>&1; then
  echo "receipt signature gate: signature metadata missing" >&2; exit 2
fi
expected=$(openssl pkey -pubin -in "$PUBLIC_KEY" -outform DER 2>/dev/null | shasum -a 256 | awk '{print $1}')
actual=$(jq -r '.signature.key_id' "$RECEIPT")
[[ -n "$expected" && "$actual" == "$expected" ]] || {
  echo "receipt signature gate: untrusted signing key" >&2; exit 2;
}
tmp_dir=$(mktemp -d)
trap 'rm -f "$tmp_dir/payload" "$tmp_dir/signature"; rmdir "$tmp_dir"' EXIT
jq -S -c 'del(.signature)' "$RECEIPT" > "$tmp_dir/payload"
# jq emits a trailing newline; receipt signing canonicalizes without it.
python3 - "$tmp_dir/payload" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_bytes(path.read_bytes().rstrip(b"\n"))
PY
jq -r '.signature.value' "$RECEIPT" | base64 --decode > "$tmp_dir/signature" 2>/dev/null || {
  echo "receipt signature gate: invalid signature encoding" >&2; exit 2;
}
openssl dgst -sha256 -verify "$PUBLIC_KEY" -signature "$tmp_dir/signature" "$tmp_dir/payload" >/dev/null 2>&1 || {
  echo "receipt signature gate: signature verification failed" >&2; exit 2;
}
echo "receipt signature gate passed"
