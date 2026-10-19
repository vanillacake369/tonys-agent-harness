# programs.mcp.servers를 provider-native MCP 설정 모양으로 변환한다.
# 공통 MCP 정의는 config-mcp.nix에 있고, 이 파일은 schema adapter만 담당한다.
{lib}: servers: let
  codexRender = import ./providers/codex/render.nix {inherit lib;};
  claudeRender = import ./providers/claude/render.nix {inherit lib;};
  geminiRender = import ./providers/gemini/render.nix {inherit lib;};
  kiroRender = import ./providers/kiro/render.nix {inherit lib;};
in {
  codex = lib.mapAttrs (_: codexRender.renderMcpServer) servers;

  gemini = lib.mapAttrs (_: geminiRender.renderMcpServer) servers;

  claude = lib.mapAttrs (_: claudeRender.renderMcpServer) servers;

  kiro = lib.mapAttrs (_: kiroRender.renderMcpServer) servers;
}
