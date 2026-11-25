{
  config,
  lib,
  ...
}: let
  catalog = builtins.fromJSON (builtins.readFile ./provider-catalog.json);
  providerNames = map (provider: provider.name) catalog.providers;
  configurableProviders = builtins.filter (provider: provider ? config_path) catalog.providers;
  providerPaths = builtins.listToAttrs (
    map (provider: {
      name = provider.name;
      value = provider.skills_path;
    })
    catalog.providers
  );
  configSourceOptions = builtins.listToAttrs (
    map (provider: {
      name = provider.name;
      value.configSource = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Absolute reviewed editable config path outside the Nix store.";
      };
    })
    configurableProviders
  );
  configSourceLinks =
    map (
      provider: let
        source = config.tonysAgentHarness.${provider.name}.configSource;
      in
        lib.mkIf (source != null) {
          assertions = [
            {
              assertion = lib.hasPrefix "/" source && !(lib.hasPrefix "/nix/store/" source);
              message = "${provider.name} configSource must be an absolute editable path outside the Nix store";
            }
          ];
          home.file.${provider.config_path}.source = config.lib.file.mkOutOfStoreSymlink source;
        }
    )
    configurableProviders;
in {
  options.tonysAgentHarness =
    {
      providers = lib.mkOption {
        type = lib.types.listOf (lib.types.enum providerNames);
        default = [];
        description = "Explicitly approved native providers whose entire unified skills directory is managed.";
      };
      allowPrivateSkills = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Acknowledge that selected providers can read the entire private capability tree.";
      };
      skillsSource = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Absolute managed runtime skills link";
      };
    }
    // configSourceOptions;

  config = lib.mkMerge (
    configSourceLinks
    ++ [
      (lib.mkIf (config.tonysAgentHarness.skillsSource != null) {
        assertions = [
          {
            assertion =
              config.tonysAgentHarness.providers == [] || config.tonysAgentHarness.allowPrivateSkills;
            message = "Unified skills include private data; explicitly approve providers and allowPrivateSkills";
          }
          {
            assertion =
              lib.hasPrefix "/" config.tonysAgentHarness.skillsSource
              && !(lib.hasPrefix "/nix/store/" config.tonysAgentHarness.skillsSource);
            message = "skillsSource must be an absolute editable path";
          }
        ];
        home.file = let
          target = config.lib.file.mkOutOfStoreSymlink config.tonysAgentHarness.skillsSource;
        in
          builtins.listToAttrs (
            map (name: {
              name = providerPaths.${name};
              value.source = target;
            })
            config.tonysAgentHarness.providers
          );
      })
    ]
  );
}
