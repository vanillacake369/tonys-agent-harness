# Google Gemini CLI 설정을 provider 계약 기반 산출물로 구성한다.
# Gemini가 직접 읽는 context와 hook 설정만 이 module에서 연결한다.
{
  config,
  lib,
  pkgs,
  ...
}: let
  providerSettings = import ../../runtime-provider-settings.nix {inherit config lib pkgs;};
  geminiRender = import ./render.nix {inherit lib;};
  workflowIndex = import ../../contract-workflow-index.nix {inherit lib;};
in {
  programs.antigravity-cli = {
    enable = true;
    settings = {};
    context = {
      "GEMINI" = ../../../../AGENTS.md;
      "AGENTS" = ../../../../AGENTS.md;
      "AGENT_WORKFLOWS" = workflowIndex.sharedGuide;
    };
  };

  home.activation.syncGeminiSettings = providerSettings.mkSettingsSync {
    provider = "gemini";
    format = "json";
    fileName = "antigravity-cli-settings.json";
    syncName = "gemini-settings";
    target = "$HOME/.gemini/settings.json";
    baseHooks = geminiRender.providerHooks;
    render = {
      hooks,
      mcp,
    }: {
      mcpServers = mcp;
      context.fileName = "AGENTS.md";
      inherit hooks;
    };
  };
}
