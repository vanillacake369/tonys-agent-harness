#!/bin/sh
set -eu

fail() {
  printf 'harness local installer: %s\n' "$*" >&2
  exit 1
}

bin_dir="${HOME:?HOME is required}/.local/bin"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin-dir)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--bin-dir requires a directory'
      bin_dir=$2
      shift
      ;;
    *) fail 'usage: install-local.sh [--bin-dir DIR]' ;;
  esac
  shift
done

case "$bin_dir" in /*) ;; *) bin_dir="$PWD/$bin_dir" ;; esac
repo=$(cd "$(dirname "$0")/.." && pwd -P)
bash "$repo/dev/environment-run.sh" build

source="$repo/result/bin/harness"
[ -f "$source" ] && [ -x "$source" ] || fail "build did not produce an executable at $source"
mkdir -p "$bin_dir"
destination="$bin_dir/harness"
if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
  fail "expected a regular file at $destination"
fi

staged=$(mktemp "$bin_dir/.harness.XXXXXXXX")
cleanup() {
  if [ -n "$staged" ]; then rm -f "$staged"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
cp "$source" "$staged"
chmod 0755 "$staged"
mv -f "$staged" "$destination"
staged=''
printf 'Installed current checkout at %s\n' "$destination"
case ":${PATH:-}:" in
  *":$bin_dir:"*) ;;
  *) printf 'Add %s to your PATH to run harness.\n' "$bin_dir" ;;
esac
