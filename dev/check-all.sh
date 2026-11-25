#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
action=${1:-check}
module=${2:-all}
packages=(. ./core ./cli ./config ./source ./provider ./dev)
case "$module" in
  all) ;;
  core|cli|config|source|provider|dev) packages=("./$module") ;;
  *) echo 'unknown test module' >&2; exit 2 ;;
esac
for tool in go gitleaks; do command -v "$tool" >/dev/null || exit 1; done
gitleaks dir --no-banner --redact --exit-code 1 .
gitleaks git --no-banner --redact --exit-code 1 .
go test -race -count=1 "${packages[@]}"
go vet "${packages[@]}"
if [[ "$action" == test ]]; then exit; fi
[[ "$action" == check && "$module" == all ]] || exit 2
for tool in sops age-keygen jq git python3; do
  command -v "$tool" >/dev/null || { echo "Missing integration dependency: $tool" >&2; exit 1; }
done
python3 -c "import yaml"
bash dev/check-boundary.sh
for suite in skill-validate dag-validate tool-contract-validate; do
  bash "core/${suite}_test.sh"
done
