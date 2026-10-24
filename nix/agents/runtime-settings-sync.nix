# Nix가 만든 provider 설정을 CLI가 기대하는 mutable config 파일로 동기화한다.
{
  lib,
  pkgs,
}: let
  cp = lib.getExe' pkgs.coreutils "cp";
  chmod = lib.getExe' pkgs.coreutils "chmod";
  mkdir = lib.getExe' pkgs.coreutils "mkdir";
  dirname = lib.getExe' pkgs.coreutils "dirname";
  rm = lib.getExe' pkgs.coreutils "rm";
  date = lib.getExe' pkgs.coreutils "date";
  pythonToml = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  python = lib.getExe pythonToml;
  managedSync = ../../runtime/governance/managed-config-sync.py;
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

      ${python} ${managedSync} --format json --target "$TARGET" --source "$SOURCE"
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

      ${python} ${managedSync} --format toml --target "$TARGET" --source "$SOURCE"

      for obsolete_name in ${lib.escapeShellArgs obsoleteFiles}; do
        obsolete="$TARGET_DIR/$obsolete_name"
        if [[ -f "$obsolete" || -L "$obsolete" ]]; then
          ${cp} "$obsolete" "$obsolete.backup.$(${date} +%Y%m%d%H%M%S)"
          ${rm} "$obsolete"
        fi
      done
    '';
}
