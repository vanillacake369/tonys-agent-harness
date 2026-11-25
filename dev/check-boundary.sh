#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
fixture=$(cd "$fixture" && pwd -P)
repo="$fixture/repo"
mkdir -p "$repo" "$fixture/bin"
while IFS= read -r name; do
  mkdir -p "$repo/$(dirname "$name")"
  cp "$root/$name" "$repo/$name"
done < "$root/core/environment-public.txt"
mkdir -p "$repo/capability" "$repo/.private"
printf 'synthetic secret\n' > "$repo/capability/secret.md"
printf 'synthetic secret\n' > "$repo/capability.enc"
printf 'synthetic secret\n' > "$repo/.private/key"
printf 'synthetic private registry\n' > "$repo/source/registry-sources.json"
cat > "$fixture/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == build && $2 == --no-update-lock-file && $3 == --out-link && $5 == path:* ]]
public=${5#path:}
[[ $PWD == "$public" && -f "$public/main.go" && -f "$public/core/environment-public.txt" ]]
[[ ! -e "$public/capability" && ! -e "$public/capability.enc" && ! -e "$public/.private" ]]
[[ ! -e "$public/source/registry-sources.json" ]]
SH
chmod +x "$fixture/bin/nix"
PATH="$fixture/bin:$PATH" bash "$repo/dev/environment-run.sh" build
cp "$repo/core/environment-public.txt" "$fixture/manifest"
printf '%s\n' 'source/registry-sources.json' >> "$repo/core/environment-public.txt"
if PATH="$fixture/bin:$PATH" bash "$repo/dev/environment-run.sh" build; then
  echo 'FAIL: private registry manifest entry was accepted' >&2
  exit 1
fi
cp "$fixture/manifest" "$repo/core/environment-public.txt"
rm "$repo/source/command-source.go"
ln -s "$repo/capability.enc" "$repo/source/command-source.go"
if PATH="$fixture/bin:$PATH" bash "$repo/dev/environment-run.sh" build; then
  echo 'FAIL: public source symlink was accepted' >&2
  exit 1
fi
echo 'PUBLIC_BOUNDARY=PASS (mock Nix, no actual Nix execution)'
