self: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.tonys-agent-harness;
  normalize = import ./normalize-config.nix {inherit lib;};
  manifest =
    if cfg.manifest == null
    then null
    else builtins.fromTOML (builtins.readFile cfg.manifest);
  normalized =
    if manifest == null
    then null
    else normalize manifest;
  normalizedFile =
    if normalized == null
    then null
    else pkgs.writeText "agent-harness-normalized.json" (builtins.toJSON normalized);
  projectSource =
    if cfg.manifest == null || cfg.instruction == null || normalized == null
    then null
    else
      pkgs.runCommand "agent-harness-project-source" {} ''
        mkdir -p "$out/$(dirname ${lib.escapeShellArg normalized.project.instruction})"
        cp ${cfg.manifest} "$out/agent-harness.toml"
        cp ${cfg.instruction} "$out/${normalized.project.instruction}"
      '';
  runtimeRoot = ../runtime;
  runtimeFiles = lib.filter (path: lib.hasSuffix ".sh" (toString path) || lib.hasSuffix ".py" (toString path)) (lib.filesystem.listFilesRecursive runtimeRoot);
  runtimeHomeFiles = lib.listToAttrs (map (source: {
      name = ".config/agents/${lib.removePrefix "${toString runtimeRoot}/" (toString source)}";
      value = {
        inherit source;
        executable = true;
      };
    })
    runtimeFiles);
  notificationHomeFiles = {
    ".config/agents/hooks/agent-notify.sh" = {
      source = ./agents/providers/claude/hooks/agent-notify.sh;
      executable = true;
    };
    ".config/agents/hooks/agent-notify-open.sh" = {
      source = ./agents/providers/claude/hooks/agent-notify-open.sh;
      executable = true;
    };
  };
in {
  options.programs.tonys-agent-harness = {
    enable = lib.mkEnableOption "provider-neutral agent harness";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      description = "Harness CLI package.";
    };
    projectRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Deprecated evaluation-time project source; retained for compatibility.";
    };
    manifest = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Project-owned agent-harness.toml consumed by every adapter.";
    };
    instruction = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Provider-neutral instruction source copied into the immutable input bundle.";
    };
    workspaceRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Editable checkout used only for workspace reconciliation.";
    };
    outputDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/agent-harness/generated";
      description = "Activation-time generated provider bundle.";
    };
    normalizedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      readOnly = true;
      default = normalized;
      description = "Normalized manifest projected by the Home Manager adapter.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.manifest != null && cfg.instruction != null && cfg.workspaceRoot != null;
        message = "tonys-agent-harness requires manifest, instruction, and workspaceRoot when enabled";
      }
    ];
    home.packages = [cfg.package];
    home.file = runtimeHomeFiles // notificationHomeFiles;
    xdg.configFile."agent-harness/normalized.json".source = normalizedFile;
    home.activation.reconcileAgentHarness = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${cfg.package}/bin/harness export \
        --project ${projectSource} \
        --output ${lib.escapeShellArg cfg.outputDirectory}
      run ${cfg.package}/bin/harness reconcile-guides \
        --project ${projectSource} \
        --workspace ${lib.escapeShellArg cfg.workspaceRoot}
    '';
  };
}
