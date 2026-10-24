# OpenAI Codex CLI 설정을 provider 계약 기반 산출물로 구성한다.
# model, TUI, hook, MCP merge는 Codex provider 경계에서만 합성한다.
{
  config,
  lib,
  pkgs,
  ...
}: let
  toml = pkgs.formats.toml {};
  providerSettings = import ../../runtime-provider-settings.nix {inherit config lib pkgs;};
  codexBindings = import ./bindings.nix {inherit lib;};
  codexRender = import ./render.nix {inherit lib;};
  sharedGuide = builtins.readFile ../../../../AGENTS.md;
in {
  programs.codex = {
    enable = true;
    enableMcpIntegration = false;
    context = codexBindings.mkContext sharedGuide;
    inherit (codexBindings) skills;
    rules.default = ''
      prefix_rule(pattern=["nix", "fmt"], decision="allow")
      prefix_rule(pattern=["nix", "flake", "check"], decision="allow")
      prefix_rule(pattern=["nix", "eval"], decision="allow")
    '';
    settings = lib.mkForce {};
  };

  home.file =
    lib.mapAttrs' (name: agent: {
      name = ".codex/agents/${name}.toml";
      value.source = toml.generate "codex-agent-${name}.toml" agent;
    })
    codexBindings.customAgents;

  home.activation.syncCodexConfig = providerSettings.mkSettingsSync {
    provider = "codex";
    format = "toml";
    fileName = "codex-config.toml";
    syncName = "codex-config";
    target = "$HOME/.codex/config.toml";
    type = "toml";
    baseHooks = codexRender.mkProviderHooks {};
    preserveTomlKeys = [
      "hooks.state"
      "projects"
    ];
    obsoleteFiles = [
      "hooks.json"
    ];
    render = {
      hooks,
      mcp,
    }:
      codexBindings.mkSettings {inherit hooks mcp;}
      // {
        model = codexRender.codexModel;
        tui = codexRender.codexTui;
      };
  };
}
