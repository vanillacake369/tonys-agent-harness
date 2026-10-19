# Nix가 만든 provider 설정을 CLI가 기대하는 mutable config 파일로 동기화한다.
{
  lib,
  pkgs,
}: let
  jq = lib.getExe' pkgs.jq "jq";
  cp = lib.getExe' pkgs.coreutils "cp";
  chmod = lib.getExe' pkgs.coreutils "chmod";
  mkdir = lib.getExe' pkgs.coreutils "mkdir";
  dirname = lib.getExe' pkgs.coreutils "dirname";
  rm = lib.getExe' pkgs.coreutils "rm";
  date = lib.getExe' pkgs.coreutils "date";
  sponge = lib.getExe' pkgs.moreutils "sponge";
  pythonToml = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  python = lib.getExe pythonToml;
  # Codex TOML은 CLI가 runtime state를 쓰는 영역이 있어 전체 덮어쓰기가 위험하다.
  # 지정 key만 보존하고 나머지는 Nix 생성값으로 수렴시켜 drift를 줄인다.
  tomlMerge = pkgs.writeText "merge-preserved-toml.py" ''
    import pathlib
    import tomllib
    import tomli_w
    import os

    preserve_paths = os.environ["PRESERVE_KEYS"].splitlines()
    obsolete_files = os.environ["OBSOLETE_FILES"].splitlines()
    target_path = pathlib.Path(os.environ["TARGET"])
    existing_path = pathlib.Path(os.environ["EXISTING"])
    source_path = pathlib.Path(os.environ["SOURCE"])
    old_backup = os.environ.get("OLD_BACKUP", "")

    def load_toml(path, fallback=None):
        fallback = {} if fallback is None else fallback
        try:
            with pathlib.Path(path).open("rb") as f:
                return tomllib.load(f)
        except (FileNotFoundError, tomllib.TOMLDecodeError):
            return fallback

    merged = load_toml(source_path)
    existing = load_toml(existing_path)
    backup_existing = load_toml(old_backup) if old_backup else {}

    def get_path(data, dotted):
        current = data
        for part in dotted.split("."):
            if not isinstance(current, dict) or part not in current:
                return None
            current = current[part]
        return current

    def set_path(data, dotted, value):
        current = data
        parts = dotted.split(".")
        for part in parts[:-1]:
            next_value = current.get(part)
            if not isinstance(next_value, dict):
                next_value = {}
                current[part] = next_value
            current = next_value
        current[parts[-1]] = value

    for path in preserve_paths:
        value = get_path(existing, path)
        if value is None:
            value = get_path(backup_existing, path)
        if value is not None:
            set_path(merged, path, value)

    hook_state = get_path(merged, "hooks.state")
    if isinstance(hook_state, dict):
        target_dir = target_path.parent
        obsolete_prefixes = [
            f"{target_dir / obsolete_file}:"
            for obsolete_file in obsolete_files
        ]
        for state_key in list(hook_state.keys()):
            if any(state_key.startswith(prefix) for prefix in obsolete_prefixes):
                del hook_state[state_key]

    target_path.write_text(tomli_w.dumps(merged), encoding="utf-8")
  '';
in {
  # JSON 설정은 기존 사용자 설정을 백업한 뒤 jq merge로 합친다.
  # jq가 없는 환경에서는 생성 파일을 그대로 복사해 early success 경로를 유지한다.
  mkJsonSync = {
    target,
    source,
    ...
  }:
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      TARGET="${target}"
      SOURCE="${source}"

      ${mkdir} -p "$(${dirname} "$TARGET")"

      if [[ -f "$TARGET" ]]; then
        ${cp} "$TARGET" "''${TARGET}.backup"
        if command -v ${jq} &> /dev/null; then
          ${jq} -s '.[0] as $old | .[1] as $new | ($old * $new) | if ($new | has("mcpServers")) then .mcpServers = $new.mcpServers else . end' "$TARGET" "$SOURCE" | ${sponge} "$TARGET"
        else
          ${cp} "$SOURCE" "$TARGET"
        fi
      else
        ${cp} "$SOURCE" "$TARGET"
      fi

      ${chmod} u+w "$TARGET"
    '';

  # JSON/TOML merge가 필요 없는 파일은 symlink를 제거하고 실파일로 복사한다.
  # provider CLI가 설정 파일을 직접 수정할 수 있게 writable 상태를 보장한다.
  mkFileCopy = {
    target,
    source,
    ...
  }:
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      TARGET="${target}"
      SOURCE="${source}"

      ${mkdir} -p "$(${dirname} "$TARGET")"

      if [[ -L "$TARGET" ]]; then
        ${rm} "$TARGET"
      fi

      if [[ -f "$TARGET" ]]; then
        ${cp} "$TARGET" "''${TARGET}.backup"
      fi

      ${cp} "$SOURCE" "$TARGET"
      ${chmod} u+w "$TARGET"
    '';

  # provider가 직접 수정해야 하는 설정은 최초 1회만 생성한다.
  # 기존 실파일은 유지하고, 예전 Home Manager symlink만 실파일로 바꿔 편집 가능하게 한다.
  mkSeedFileCopy = {
    target,
    source,
    ...
  }:
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      TARGET="${target}"
      SOURCE="${source}"

      ${mkdir} -p "$(${dirname} "$TARGET")"

      if [[ -L "$TARGET" ]]; then
        ${rm} "$TARGET"
      fi

      if [[ ! -e "$TARGET" ]]; then
        ${cp} "$SOURCE" "$TARGET"
      fi

      ${chmod} 600 "$TARGET"
    '';

  # TOML 설정은 지정된 key만 보존하고 나머지는 Nix 생성 값을 기준으로 재작성한다.
  # obsolete 파일은 백업 후 제거해서 이전 hook 상태와 충돌하지 않게 한다.
  mkTomlSync = {
    target,
    source,
    preserveKeys ? [],
    obsoleteFiles ? [],
    ...
  }:
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      TARGET="${target}"
      SOURCE="${source}"
      TARGET_DIR="$(${dirname} "$TARGET")"

      ${mkdir} -p "$TARGET_DIR"

      EXISTING="$TARGET"
      if [[ -f "$TARGET" || -L "$TARGET" ]]; then
        OLD_BACKUP=""
        if [[ -f "''${TARGET}.backup" ]]; then
          OLD_BACKUP="''${TARGET}.backup.previous"
          ${cp} "''${TARGET}.backup" "$OLD_BACKUP"
        fi
        ${cp} "$TARGET" "''${TARGET}.backup"
        EXISTING="''${TARGET}.backup"
      fi

      if [[ -L "$TARGET" ]]; then
        ${rm} "$TARGET"
      fi

      if [[ -f "$EXISTING" ]]; then
        PRESERVE_KEYS="${lib.concatStringsSep "\n" preserveKeys}" \
          OBSOLETE_FILES="${lib.concatStringsSep "\n" obsoleteFiles}" \
          TARGET="$TARGET" SOURCE="$SOURCE" EXISTING="$EXISTING" \
          OLD_BACKUP="$OLD_BACKUP" ${python} ${tomlMerge}
        if [[ -n "$OLD_BACKUP" ]]; then
          ${rm} "$OLD_BACKUP"
        fi
      else
        ${cp} "$SOURCE" "$TARGET"
      fi

      ${chmod} u+w "$TARGET"

      for obsolete_name in ${lib.escapeShellArgs obsoleteFiles}; do
        obsolete="$TARGET_DIR/$obsolete_name"
        if [[ -f "$obsolete" || -L "$obsolete" ]]; then
          ${cp} "$obsolete" "$obsolete.backup.$(${date} +%Y%m%d%H%M%S)"
          ${rm} "$obsolete"
        fi
      done
    '';
}
