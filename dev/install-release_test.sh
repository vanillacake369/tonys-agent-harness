#!/bin/sh
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; esac
case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; esac
name="tonys-agent-harness-1.2.3-$platform-$arch"
mkdir -p "$fixture/$name" "$fixture/dist" "$fixture/tools"
printf '#!/bin/sh\nprintf "1.2.3\\n"\n' > "$fixture/$name/harness"
tar -czf "$fixture/dist/$name.tar.gz" -C "$fixture" "$name"
(
  cd "$fixture/dist"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$name.tar.gz"
  else
    shasum -a 256 "$name.tar.gz"
  fi > checksums.txt
)

cat > "$fixture/tools/gh" <<'GH'
#!/bin/sh
set -eu
if [ "$*" = 'release view --repo vanillacake369/tonys-agent-harness --json tagName --jq .tagName' ]; then
  printf 'v1.2.3\n'
  exit 0
fi
[ "$#" -eq 11 ]
[ "$1 $2 $3 $4 $5" = 'release download v1.2.3 --repo vanillacake369/tonys-agent-harness' ]
[ "$6" = '--dir' ] && [ "$8" = '--pattern' ]
[ "${10}" = '--pattern' ] && [ "${11}" = 'checksums.txt' ]
cp "$INSTALL_TEST_DIST/$9" "$INSTALL_TEST_DIST/checksums.txt" "$7"
GH
chmod +x "$fixture/tools/gh"

export INSTALL_TEST_DIST="$fixture/dist" PATH="$fixture/tools:$PATH"
sh "$repo/install.sh" --bin-dir "$fixture/local bin"
[ "$("$fixture/local bin/harness")" = 1.2.3 ]
sh "$repo/install.sh" v1.2.3 --bin-dir "$fixture/download/bin"
[ "$("$fixture/download/bin/harness")" = 1.2.3 ]

printf 'corruption' >> "$fixture/dist/$name.tar.gz"
if sh "$repo/install.sh" --version v1.2.3 --bin-dir "$fixture/local bin" >"$fixture/error" 2>&1; then
  printf 'installer accepted a corrupted archive\n' >&2
  exit 1
fi
grep -F 'checksum mismatch' "$fixture/error"
[ "$("$fixture/local bin/harness")" = 1.2.3 ]
