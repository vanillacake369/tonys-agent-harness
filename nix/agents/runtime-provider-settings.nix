{
  config,
  lib,
  pkgs,
}: let
  # provider 설정 생성/동기화 helper를 모은 runtime 경계다.
  # provider module은 이 helper를 통해 파일 생성과 mutable config sync를 같은 방식으로 처리한다.
  formats = {
    json = pkgs.formats.json {};
    toml = pkgs.formats.toml {};
  };
  settingsSync = import ./runtime-settings-sync.nix {inherit lib pkgs;};
  # An exported server is executable authority. Until per-provider operation
  # gates are verified, omit unsupported MCP paths rather than merely declaring
  # them read-only. Claude has the explicit Context7 pre-tool adapter.
  renderedMcp = import ./runtime-mcp-render.nix {inherit lib;} config.programs.mcp.servers;
  mcp = {
    claude = lib.filterAttrs (name: _: name == "context7") renderedMcp.claude;
    codex = {};
    gemini = {};
    kiro = {};
  };

  # provider 설정 파일을 Nix store에 생성한다.
  # 호출자는 format/name/value만 넘기고 serialize 구현은 여기서 숨긴다.
  mkFile = {
    format,
    name,
    value,
  }:
    formats.${format}.generate name value;

  # 공통 MCP 렌더 결과와 provider hook을 합쳐 provider 설정 파일을 만든다.
  # provider module은 render 함수만 넘겨서 자기 schema를 유지한다.
  mkSettingsFile = {
    provider,
    format,
    name,
    baseHooks ? {},
    render,
  }:
    mkFile {
      inherit format name;
      value = render {
        hooks = baseHooks;
        mcp = mcp.${provider};
      };
    };

  # 생성된 설정 파일을 실제 CLI mutable config 위치로 동기화한다.
  # TOML은 사용자 상태를 일부 보존하고, 나머지는 단순 copy/json merge를 사용한다.
  mkSync = {
    type ? "json",
    name,
    target,
    source,
    preserveTomlKeys ? [],
    obsoleteFiles ? [],
  }:
    if type == "json"
    then settingsSync.mkJsonSync {inherit name target source;}
    else if type == "toml"
    then
      settingsSync.mkTomlSync {
        inherit name target source;
        preserveKeys = preserveTomlKeys;
        inherit obsoleteFiles;
      }
    else settingsSync.mkFileCopy {inherit name target source;};
in {
  inherit mcp mkFile mkSettingsFile mkSync;
  inherit (settingsSync) mkSeedFileCopy;

  # provider module이 한 번의 호출로 render 파일 생성과 activation sync를 묶게 한다.
  # 인자가 많아서 attrset DTO 형태를 유지한다.
  mkSettingsSync = {
    provider,
    format,
    fileName,
    syncName,
    target,
    type ? "json",
    baseHooks ? {},
    preserveTomlKeys ? [],
    obsoleteFiles ? [],
    render,
  }: let
    rendered = mkSettingsFile {
      inherit provider format baseHooks render;
      name = fileName;
    };
  in
    mkSync {
      inherit type target preserveTomlKeys;
      inherit obsoleteFiles;
      name = syncName;
      source = "${rendered}";
    };
}
