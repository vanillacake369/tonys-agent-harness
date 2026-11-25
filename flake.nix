{
  description = "Tony's Agent Harness: public dependencies and Go reconciler";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
      "x86_64-darwin"
    ];
    each = nixpkgs.lib.genAttrs systems;
    runtimeTools = pkgs:
      with pkgs; [
        sops
        age
        git
        gh
        bash
        (python3.withPackages (ps: [ps.pyyaml]))
        jq
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        fzf
      ];
    developmentTools = pkgs:
      (runtimeTools pkgs)
      ++ (with pkgs; [
        bats
        gitleaks
        go
        go-task
        hyperfine
        just
      ])
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.bpftrace
        pkgs.linuxPackages.perf
      ];
    package = pkgs:
      pkgs.buildGoModule {
        pname = "tonys-agent-harness";
        version = nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./cli/version.txt);
        # Defense in depth only: the flake input must already be a public snapshot.
        src = builtins.path {
          path = ./.;
          name = "harness-public-code";
          filter = path: type: let
            rel = nixpkgs.lib.removePrefix (toString ./. + "/") (toString path);
            files = nixpkgs.lib.splitString "\n" (builtins.readFile ./core/environment-public.txt);
          in
            if type == "directory"
            then toString path == toString ./. || builtins.any (name: nixpkgs.lib.hasPrefix (rel + "/") name) files
            else type == "regular" && builtins.elem rel files;
        };
        vendorHash = nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./dev/vendor-hash.txt);
        # Full regression suite runs once via just check, with real crypto tools.
        doCheck = false;
        subPackages = ["."];
        nativeBuildInputs = [pkgs.makeWrapper];
        postInstall = ''
          mv $out/bin/tonys-agent-harness $out/bin/harness
          wrapProgram $out/bin/harness --prefix PATH : ${pkgs.lib.makeBinPath (runtimeTools pkgs)}
        '';
      };
    coreScenario = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.runCommand "harness-core-scenario" {
        nativeBuildInputs = [pkgs.bash pkgs.gnugrep];
      } ''
        fixture="$TMPDIR/fixture"
        bash ${./dev/core-scenario.sh} setup "$fixture" ${./provider/provider-catalog.json}
        bash ${./dev/core-scenario.sh} run ${self.packages.${system}.default}/bin/harness "$fixture" >status
        grep -F 'provider=codex status=DISABLED' status
        grep -F 'Next: harness config init PATH or empty' status
        test ! -e "$fixture/state"
        test ! -e "$fixture/vault"
        test ! -e "$fixture/config"
        touch "$out"
      '';
    adapters = import ./provider/adapter-config.nix;
  in {
    packages = each (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        fragmentPackages =
          nixpkgs.lib.mapAttrs' (
            name: fragment:
              nixpkgs.lib.nameValuePair "${name}-config-fragment" (
                pkgs.writeText fragment.fileName (
                  if builtins.isString fragment.value
                  then fragment.value
                  else builtins.toJSON fragment.value
                )
              )
          )
          adapters.fragments;
      in
        {
          default = package pkgs;
          plugin-plan = pkgs.writeText "plugin-plan.json" (builtins.toJSON adapters.plugins);
        }
        // fragmentPackages
    );
    devShells = each (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = developmentTools pkgs;
        };
      }
    );
    checks = each (system: {
      application = self.packages.${system}.default;
      core-scenario = coreScenario system;
    });
    homeManagerModules.default = import ./provider/module-home-manager.nix;
  };
}
