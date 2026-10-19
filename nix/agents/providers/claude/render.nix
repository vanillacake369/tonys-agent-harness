{lib}: let
  attrTools = import ../../runtime-attrs.nix {inherit lib;};
  inherit (attrTools) clean;

  # Claude MCP schema는 command/url 존재 여부에 따라 type을 명시한다.
  # provider가 알 필요 없는 공통 내부 필드는 출력에서 제거한다.
  renderMcpServer = srv: let
    internalAttrs = [
      "bearerTokenEnvVar"
      "disabled"
      "enabled"
      "envHttpHeaders"
      "transport"
    ];
    stdioAttrs = [
      "args"
      "command"
      "cwd"
      "env"
    ];
  in
    if srv ? command && srv.command != null
    then clean ((lib.removeAttrs srv internalAttrs) // {type = "stdio";})
    else if srv ? url && srv.url != null
    then clean ((lib.removeAttrs srv (internalAttrs ++ stdioAttrs)) // {type = "http";})
    else {};
in {
  inherit renderMcpServer;
}
