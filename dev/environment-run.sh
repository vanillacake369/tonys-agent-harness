#!/usr/bin/env bash
set -euo pipefail
umask 077

# 공개 allowlist만 Nix 입력으로 전달한다. 개인 checkout 전체를 전달하지 않는다.
repo=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repo"
action=${1:-check}
[[ $# -le 2 ]] || {
    echo 'usage: environment-run.sh build|check|core|test [MODULE]|profile perf|trace|bootstrap' >&2
    exit 2
}
case "$action" in
build | check | core | bootstrap) [[ $# -le 1 ]] || exit 2 ;;
test) ;;
profile) [[ $# -eq 2 && ($2 == perf || $2 == trace) ]] || exit 2 ;;
*)
    echo 'unknown development action' >&2
    exit 2
    ;;
esac
command -v nix >/dev/null || {
    echo 'BLOCKED: install Nix first' >&2
    exit 1
}
public=$(mktemp -d "${TMPDIR:-/tmp}/harness-public.XXXXXX")
trap 'rm -rf -- "$public"' EXIT
public=$(cd "$public" && pwd -P)
[[ "$public" != "$repo" && "$public" != "$repo/"* ]] || {
    echo 'unsafe temporary location' >&2
    exit 1
}
manifest=core/environment-public.txt
[[ -f "$manifest" && ! -L "$manifest" && ! -L core ]] || exit 1
while IFS= read -r file || [[ -n "$file" ]]; do
    [[ "$file" =~ ^[a-zA-Z0-9._/-]+$ && "$file" != /* && "$file" != *//* ]] || exit 1
    [[ "/$file/" != */../* && "/$file/" != */./* ]] || exit 1
    [[ "$file" != */*/* && "$file" != */.* ]] || exit 1
    case "$file" in
    flake.nix | flake.lock | go.mod | go.sum | main.go | core/environment-public.txt) ;;
    core/*.go | core/*.sh | core/*.txtar | core/dag-contract.schema.json | core/metadata-validate.py | \
        cli/*.go | cli/*.txt | config/*.go | \
        source/*.go) ;;
    provider/*.go | provider/*.nix | provider/*.json | dev/*.bats | dev/*.go | dev/*.sh | dev/*.justfile | dev/*.nix | \
        dev/vendor-hash.txt | contract/*.json) ;;
    *)
        echo 'unapproved public path' >&2
        exit 1
        ;;
    esac
    parent=$(dirname "$file")
    [[ $(cd "$parent" && pwd -P) == "$repo/${parent#./}" || "$parent" == . ]] || exit 1
    [[ -f "$file" && ! -L "$file" && ! -e "$public/$file" ]] || exit 1
    [[ $(find "$file" -type f -links 1 -print) == "$file" ]] || exit 1
    mkdir -p "$public/$parent"
    cp -- "$file" "$public/$file"
done <"$manifest"
for file in "$manifest" flake.nix flake.lock; do [[ -f "$public/$file" ]] || exit 1; done
cd "$public"
if [[ $action == bootstrap ]]; then
    printf '%s\n' 'sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' >dev/vendor-hash.txt
    nix flake lock "path:$public"
    if ! log=$(nix build --no-link --no-update-lock-file "path:$public" 2>&1); then
        hash=$(sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[A-Za-z0-9+/]{43}=)[[:space:]]*$/\1/p' <<<"$log")
        [[ "$hash" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]] || {
            printf '%s\n' "$log" >&2
            exit 1
        }
        printf '%s\n' "$hash" >dev/vendor-hash.txt
        nix build --no-link --no-update-lock-file "path:$public"
    fi
    cp flake.lock "$repo/flake.lock"
    cp dev/vendor-hash.txt "$repo/dev/vendor-hash.txt"
    echo 'Dependency lock and vendor hash verified.'
    exit
fi
if [[ $action == build ]]; then
    [[ ! -e "$repo/result" || -L "$repo/result" ]] || {
        echo 'unmanaged result path' >&2
        exit 1
    }
    nix build --no-update-lock-file --out-link "$repo/result" "path:$public"
    echo "Ready: $repo/result/bin/harness"
    exit
fi
if [[ $action == check || $action == core ]]; then
    nix flake check --no-update-lock-file "path:$public"
fi
nix develop --no-update-lock-file "path:$public" -c bash -c '
  cd "$1" || exit 1
  case "$2" in
    core) exec bash dev/check-core.sh ;;
    profile) exec bash dev/profile-core.sh "$3" ;;
    *) exec bash dev/check-all.sh "$2" "$3" ;;
  esac
' _ "$repo" "$action" "${2:-all}"
