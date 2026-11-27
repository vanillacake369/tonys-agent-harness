#!/bin/sh
set -eu

fail() {
  printf 'harness installer: %s\n' "$*" >&2
  exit 1
}

tag=''
bin_dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$tag" ] || fail 'specify one release tag'
      tag=$2
      shift
      ;;
    --bin-dir)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--bin-dir requires a directory'
      bin_dir=$2
      shift
      ;;
    v*)
      [ -z "$tag" ] || fail 'specify one release tag'
      tag=$1
      ;;
    *) fail 'usage: install.sh [vX.Y.Z | --version vX.Y.Z] [--bin-dir DIR]' ;;
  esac
  shift
done

[ -n "$bin_dir" ] || bin_dir="${HOME:?HOME is required}/.local/bin"
case "$bin_dir" in /*) ;; *) bin_dir="$PWD/$bin_dir" ;; esac
case "$(uname -s)" in
  Darwin) platform=darwin ;;
  Linux) platform=linux ;;
  *) fail 'supported systems are macOS and Linux' ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=amd64 ;;
  *) fail 'supported architectures are amd64 and arm64' ;;
esac

staged=''
work=$(mktemp -d)
cleanup() {
  if [ -n "$staged" ]; then rm -f "$staged"; fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

repo=vanillacake369/tonys-agent-harness
command -v gh >/dev/null 2>&1 || fail 'install GitHub CLI (gh) and run gh auth login'
if [ -z "$tag" ]; then
  tag=$(gh release view --repo "$repo" --json tagName --jq .tagName) ||
    fail "could not find the latest release from $repo"
fi
valid_tag=$(printf '%s\n' "$tag" | awk '/^v[0-9]+\.[0-9]+\.[0-9]+$/ {print}')
[ -n "$tag" ] && [ "$valid_tag" = "$tag" ] || fail 'provide a stable release tag vX.Y.Z'

archive="tonys-agent-harness-${tag#v}-$platform-$arch.tar.gz"
gh release download "$tag" --repo "$repo" --dir "$work" \
  --pattern "$archive" --pattern checksums.txt ||
  fail "could not download $tag from $repo; check gh auth status and release availability"

expected=$(awk -v name="$archive" '$2 == name {print $1}' "$work/checksums.txt")
case "$expected" in
  ''|*[!0123456789abcdef]*) fail "missing or invalid checksum for $archive" ;;
esac
[ "${#expected}" -eq 64 ] || fail "invalid checksum for $archive"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum < "$work/$archive")
else
  command -v shasum >/dev/null 2>&1 || fail 'install sha256sum or shasum'
  actual=$(shasum -a 256 < "$work/$archive")
fi
[ "${actual%% *}" = "$expected" ] || fail "checksum mismatch for $archive"

# 검증을 마친 바이너리를 설치 디렉터리에서 준비한 후 교체한다.
# 압축 해제나 권한 설정에 실패하면 기존 설치 파일을 보존한다.
mkdir -p "$bin_dir"
destination="$bin_dir/harness"
if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
  fail "expected a regular file at $destination"
fi
staged=$(mktemp "$bin_dir/.harness.XXXXXXXX")
tar -xOzf "$work/$archive" "${archive%.tar.gz}/harness" > "$staged"
[ -s "$staged" ] || fail "archive did not contain a harness binary"
chmod 0755 "$staged"
mv -f "$staged" "$destination"
staged=''
printf 'Installed %s at %s\n' "$archive" "$destination"
case ":${PATH:-}:" in
  *":$bin_dir:"*) ;;
  *) printf 'Add %s to your PATH to run harness.\n' "$bin_dir" ;;
esac
