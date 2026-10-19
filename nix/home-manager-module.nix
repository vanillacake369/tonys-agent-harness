self: {config, lib, pkgs, ...}: let
  cfg = config.programs.tonys-agent-harness;
in {
  imports = [
    ./agents/runtime-module.hm.nix
    ./agents/runtime-packages.hm.nix
  ];

  options.programs.tonys-agent-harness = {
    enable = lib.mkEnableOption "provider-neutral agent harness";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      description = "Harness CLI package.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];
  };
}
