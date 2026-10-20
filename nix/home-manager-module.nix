self: {config, lib, pkgs, ...}: let
  cfg = config.programs.tonys-agent-harness;
  normalize = import ./normalize-config.nix {inherit lib;};
  manifest = if cfg.manifest == null then null else builtins.fromTOML (builtins.readFile cfg.manifest);
  normalized = if manifest == null then null else normalize manifest;
  normalizedFile = if normalized == null then null else pkgs.writeText "agent-harness-normalized.json" (builtins.toJSON normalized);
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
      description = "Project root containing AGENTS.md and the harness manifest.";
    };
    manifest = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Project-owned agent-harness.toml consumed by every adapter.";
    };
    outputDirectory = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.config/agent-harness/generated";
      description = "Activation-time generated provider bundle.";
    };
    normalizedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      readOnly = true;
      default = null;
      description = "Normalized manifest projected by the Home Manager adapter.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.projectRoot != null && cfg.manifest != null;
      message = "tonys-agent-harness requires projectRoot and manifest when enabled";
    }];
    programs.tonys-agent-harness.normalizedConfig = normalized;
    home.packages = [cfg.package];
    xdg.configFile."agent-harness/normalized.json".source = normalizedFile;
    home.activation.reconcileAgentHarness = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${cfg.package}/bin/harness export \
        --project ${lib.escapeShellArg (toString cfg.projectRoot)} \
        --output ${lib.escapeShellArg cfg.outputDirectory}
      run ${cfg.package}/bin/harness reconcile-guides \
        --project ${lib.escapeShellArg (toString cfg.projectRoot)}
    '';
  };
}
