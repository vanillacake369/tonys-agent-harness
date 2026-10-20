{
  description = "Provider-neutral engineering agent harness";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {self, nixpkgs, llm-agents}: let
    systems = ["aarch64-darwin" "x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      contractKernel = pkgs.rustPlatform.buildRustPackage {
        pname = "harness-contract-kernel";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        cargoBuildFlags = ["-p" "harness-contract-kernel"];
        cargoTestFlags = ["-p" "harness-contract-kernel"];
      };
    in {
      default = pkgs.writeShellApplication {
        name = "harness";
        runtimeInputs = [pkgs.python3 pkgs.openssl contractKernel];
        text = ''exec ${pkgs.python3}/bin/python3 ${self}/harness.py "$@"'';
        meta = {
          description = "Provider-neutral engineering agent harness";
          homepage = "https://github.com/vanillacake369/tonys-agent-harness";
          license = pkgs.lib.licenses.mit;
          mainProgram = "harness";
        };
      };
      contract-kernel = contractKernel;
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/harness";
        meta.description = "Initialize, export, and verify provider agent harness configuration";
      };
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      tests = pkgs.runCommand "tonys-agent-harness-tests" {nativeBuildInputs = [pkgs.python3 pkgs.jq pkgs.git pkgs.openssl];} ''
        cp -R ${self} source
        chmod -R u+w source
        cd source
        python3 -m unittest discover -s tests -v
        touch $out
      '';

      contracts = let
        result = import ./tests/nix/agents.test.nix {lib = pkgs.lib;};
        passed = builtins.all (entry: entry.pass) result.results;
      in
        pkgs.runCommand "tonys-agent-harness-contracts" {} ''
          test ${if passed then "1" else "0"} -eq 1
          touch $out
        '';

      hooks = pkgs.runCommand "tonys-agent-harness-hooks" {
        nativeBuildInputs = [
          pkgs.bats
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          pkgs.openssl
          pkgs.perl
          pkgs.python3
          pkgs.ripgrep
        ];
      } ''
        cp -R ${self} source
        chmod -R u+w source
        cd source
        bats tests/hooks
        touch $out
      '';

      contract-kernel = self.packages.${system}.contract-kernel;
    });

    lib = {
      schemaVersion = 1;
      consumerContractVersion = 1;
      supportedProviders = ["codex" "claude" "gemini" "kiro"];
      validationCommands = ["validate" "doctor" "plan" "export" "verify"];
      publicCommands = ["cmd-mid-work-ljh" "cmd-mid-comment-ljh" "cmd-post-blog-ljh" "cmd-post-handoff-ljh" "cmd-post-ship-ljh" "cmd-post-commit-ljh"];
    };

    overlays.default = llm-agents.overlays.shared-nixpkgs;
    homeManagerModules.default = import ./nix/home-manager-module.nix self;
  };
}
