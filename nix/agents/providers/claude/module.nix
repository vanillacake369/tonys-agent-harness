# Claude Code 설정을 Home Manager 파일/activation으로 구성한다.
# 공식 module이 없어서 provider 설정 동기화 경계만 여기서 관리한다.
{
  config,
  lib,
  pkgs,
  ...
}: let
  providerSettings = import ../../runtime-provider-settings.nix {inherit config lib pkgs;};
  workflowIndex = import ../../contract-workflow-index.nix {inherit lib;};

  mcpSourceFile = providerSettings.mkFile {
    format = "json";
    name = "claude-mcp.json";
    value = {
      mcpServers = providerSettings.mcp.claude;
    };
  };

  baseSettings = builtins.fromJSON (builtins.readFile ./settings.json);

  publicCommandFiles =
    lib.mapAttrs' (_: workflow: {
      name = ".claude/commands/${workflow.name}.md";
      value.text = workflow.body;
    })
    workflowIndex.commandWorkflows;
in {
  home.file =
    publicCommandFiles
    // {
      ".claude/WORKFLOWS.md".text = workflowIndex.sharedGuide;
      ".claude/AGENTS.md".source = ../../../../AGENTS.md;
      ".claude/CLAUDE.md".text = "@AGENTS.md\n";
      ".claude/agents".source = ./agents;
      ".claude/skills".source = ./skills;
      ".claude/hooks".source = ./hooks;
    };

  home.activation.syncClaudeMcp = providerSettings.mkSync {
    name = "claude-mcp";
    target = "$HOME/.claude.json";
    source = "${mcpSourceFile}";
  };

  home.activation.syncClaudeSettings = providerSettings.mkSettingsSync {
    provider = "claude";
    format = "json";
    fileName = "claude-settings.json";
    syncName = "claude-settings";
    target = "$HOME/.claude/settings.json";
    baseHooks = baseSettings.hooks or {};
    render = {hooks, ...}: baseSettings // {inherit hooks;};
  };
}
