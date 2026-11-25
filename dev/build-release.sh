#!/usr/bin/env bash
set -euo pipefail
umask 077

repo=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repo"
read -r version <cli/version.txt
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo 'BLOCKED: invalid release version' >&2
    exit 1
}
[[ ! -e dist ]] || {
    echo 'BLOCKED: dist already exists' >&2
    exit 1
}
for tool in go tar sha256sum; do command -v "$tool" >/dev/null || exit 1; done

stage="dist/.stage"
mkdir -p "$stage"
trap 'rm -r -- "$stage"' EXIT
for target in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
    os=${target%-*}
    arch=${target#*-}
    name="tonys-agent-harness-${version}-${target}"
    mkdir "$stage/$name"
    CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -mod=readonly -trimpath -o "$stage/$name/harness" .
    cp README.md LICENSE "$stage/$name/"
    tar -czf "dist/$name.tar.gz" -C "$stage" "$name"
done
sha256sum dist/*.tar.gz >dist/checksums.txt
