# MCP 서버 정의의 단일 출처다.
# 활성 provider는 이 공통 정의를 자기 설정 모양으로 변환해서 사용한다.
_: {
  programs.mcp = {
    enable = true;
    servers = {
      context7 = {
        command = "npx";
        args = ["-y" "@upstash/context7-mcp@latest"];
      };
      playwright = {
        command = "npx";
        args = ["-y" "@playwright/mcp@latest"];
      };
      ticktick = {
        url = "https://mcp.ticktick.com";
        transport = "streamable-http";
        bearerTokenEnvVar = "TICKTICK_MCP_TOKEN";
      };
      atlassian = {
        # Atlassian Remote MCP v2는 OAuth 로그인을 기본 경로로 둔다.
        # 비대화형 실행에서는 launcher가 이 env var로 Authorization header를 주입한다.
        url = "https://mcp.atlassian.com/v2/mcp";
        transport = "streamable-http";
        envHttpHeaders.Authorization = "ATLASSIAN_MCP_AUTHORIZATION";
      };
    };
  };
}
