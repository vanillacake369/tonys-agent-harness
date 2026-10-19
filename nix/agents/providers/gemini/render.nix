{lib}: let
  attrTools = import ../../runtime-attrs.nix {inherit lib;};
  inherit (attrTools) clean;

  # Gemini MCP schema는 stdio와 HTTP remote server 모양이 서로 다르다.
  # 지원하지 않는 서버 모양은 빈 attrs로 돌려 provider가 무시하게 한다.
  renderMcpServer = srv:
    if srv ? command && srv.command != null
    then
      clean {
        inherit (srv) command;
        args = srv.args or [];
        env = srv.env or null;
        cwd = srv.cwd or null;
        timeout = srv.timeout or null;
        trust = srv.trust or null;
        description = srv.description or null;
        includeTools = srv.includeTools or null;
      }
    else if srv ? url && srv.url != null
    then
      clean {
        httpUrl = srv.url;
        headers = srv.headers or null;
        timeout = srv.timeout or null;
        trust = srv.trust or null;
        description = srv.description or null;
        includeTools = srv.includeTools or null;
      }
    else {};
in {
  providerHooks = {
    BeforeAgent = [
      {
        hooks = [
          {
            type = "command";
            command = "python3 ~/.config/agents/governance/task-lifecycle.py start";
            timeout = 10000;
          }
        ];
      }
    ];
    BeforeTool = [
      {
        matcher = "run_shell_command";
        hooks = [
          {
            type = "command";
            command = "bash ~/.config/agents/governance/retry-hook.sh pre";
            timeout = 5000;
          }
        ];
      }
    ];
    AfterTool = [
      {
        matcher = "run_shell_command";
        hooks = [
          {
            type = "command";
            command = "bash ~/.config/agents/governance/retry-hook.sh post";
            timeout = 5000;
          }
        ];
      }
    ];
    AfterAgent = [
      {
        hooks = [
          {
            type = "command";
            command = "python3 ~/.config/agents/governance/task-lifecycle.py stop";
            timeout = 5000;
          }
          {
            type = "command";
            command = "~/.claude/hooks/agent-notify.sh gemini";
            timeout = 5000;
          }
        ];
      }
    ];
  };

  inherit renderMcpServer;
}
