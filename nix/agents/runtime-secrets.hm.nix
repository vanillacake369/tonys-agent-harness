# agent launcher가 실행 시점에 필요한 secret 환경을 구성한다.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.tonys-agent-harness;
  agentSecretEnv = pkgs.writeShellApplication {
    name = "agent-secret-env";
    runtimeInputs = [pkgs.sops];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: agent-secret-env <command> [args...]" >&2
        exit 64
      fi

      default_secrets_file=${lib.escapeShellArg cfg.secretLauncher.secretsFile}
      secrets_file="''${AGENT_SECRETS_FILE:-$default_secrets_file}"
      if [ "$(uname -s)" = "Darwin" ]; then
        default_age_key_file="$HOME/Library/Application Support/sops/age/keys.txt"
      else
        default_age_key_file="''${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt"
      fi
      age_key_file="''${AGENT_SOPS_AGE_KEY_FILE:-$default_age_key_file}"

      if [ -z "''${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$age_key_file" ]; then
        export SOPS_AGE_KEY_FILE="$age_key_file"
      fi

      read_secret() {
        sops --decrypt --extract "$1" "$secrets_file" 2>/dev/null || true
      }

      if [ -z "''${TICKTICK_MCP_TOKEN:-}" ] && [ -f "$secrets_file" ]; then
        token="$(read_secret '["ticktick"]["mcp_token"]')"
        if [ -n "$token" ] && [ "$token" != "null" ]; then
          export TICKTICK_MCP_TOKEN="$token"
        fi
      fi

      if [ -z "''${ATLASSIAN_MCP_AUTHORIZATION:-}" ] && [ -f "$secrets_file" ]; then
        email="$(read_secret '["atlassian"]["user_email"]')"
        token="$(read_secret '["atlassian"]["api_token"]')"
        if [ -n "$email" ] && [ "$email" != "null" ] && [ -n "$token" ] && [ "$token" != "null" ]; then
          encoded="$(printf '%s' "$email:$token" | base64 | tr -d '\n')"
          export ATLASSIAN_MCP_AUTHORIZATION="Basic $encoded"
        fi
      fi

      exec "$@"
    '';
  };
in {
  options.programs.tonys-agent-harness.secretLauncher = {
    enable = lib.mkEnableOption "runtime credential launcher for agent commands";
    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/agents/secrets.yaml";
      description = "SOPS document read by agent-secret-env at process launch.";
    };
  };

  config = lib.mkIf cfg.secretLauncher.enable {
    home.packages = [agentSecretEnv];
  };
}
