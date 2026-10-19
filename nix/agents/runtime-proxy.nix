# cli-proxy-api를 로컬 통합 AI provider proxy로 실행한다.
# OpenAI/Claude/Gemini 호환 endpoint를 localhost:4001에 제공한다.
{
  config,
  lib,
  pkgs,
  isDarwin,
  ...
}: let
  configPath = "${config.home.homeDirectory}/.cli-proxy-api/config.yaml";
in {
  home.packages = [
    pkgs.llm-agents.cli-proxy-api
  ];

  home.file.".cli-proxy-api/config.yaml".text = ''
    host: "127.0.0.1"
    port: 4001
    auth-dir: "${config.home.homeDirectory}/.cli-proxy-api"
    debug: false
    request-retry: 3
    routing:
      strategy: "round-robin"
    quota-exceeded:
      switch-project: true
      switch-preview-model: true
  '';

  launchd.agents.cli-proxy-api = lib.mkIf isDarwin {
    enable = true;
    config = {
      Label = "com.cli-proxy-api";
      ProgramArguments = ["${pkgs.llm-agents.cli-proxy-api}/bin/cli-proxy-api" "-config" configPath];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/cli-proxy-api.log";
      StandardErrorPath = "/tmp/cli-proxy-api.err";
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
      };
    };
  };
}
