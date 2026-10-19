{
  # permission 계약은 provider가 공통으로 이해해야 할 최소 권한 모델이다.
  # 세부 allow/deny 문법은 provider adapter가 자기 schema에 맞춰 투영한다.
  default = {
    workspace = "write";
    network = false;
    mcp = ["context7" "playwright"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-architect = {
    workspace = "read";
    network = false;
    mcp = ["context7"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-cross-validator = {
    workspace = "read";
    network = true;
    mcp = ["context7" "playwright"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-implementer = {
    workspace = "write";
    network = false;
    mcp = ["playwright"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-refactorer = {
    workspace = "write";
    network = false;
    mcp = ["playwright"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-researcher = {
    workspace = "read";
    network = true;
    mcp = ["context7"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-reviewer = {
    workspace = "read";
    network = false;
    mcp = [];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };

  agent-tester = {
    workspace = "write";
    network = false;
    mcp = ["playwright"];
    destructive = false;
    secret_access = "deny";
    approval = "provider";
  };
}
