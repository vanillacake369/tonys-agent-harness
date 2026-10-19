{
  # 이 파일은 provider 지원 목표를 선언하는 계약 계층이다.
  # 실제로 어느 provider를 활성화할지는 runtime/provider module에서 결정한다.
  # 따라서 여기에 provider를 추가해도 사용자 설정 파일이 바로 생성되지는 않는다.
  codex = {
    display_name = "Codex";
    targets.cli = {
      tier = 4;
      surfaces = {
        context = "generated";
        skills = "generated";
        roles = "generated";
        permissions = "generated";
        hooks = "provider_owned";
        mcp = "generated";
        engineering_rules = "generated";
        test_strategy = "generated";
      };
    };
  };

  claude = {
    display_name = "Claude Code";
    targets.cli = {
      tier = 4;
      surfaces = {
        context = "supported";
        commands = "supported";
        skills = "generated";
        roles = "generated";
        permissions = "provider_owned";
        hooks = "provider_owned";
        mcp = "generated";
        engineering_rules = "generated";
        test_strategy = "generated";
      };
    };
  };

  gemini = {
    display_name = "Gemini CLI";
    targets.cli = {
      tier = 2;
      surfaces = {
        context = "supported";
        commands = "generated";
        skills = "degraded";
        roles = "unsupported";
        permissions = "unsupported";
        hooks = "provider_owned";
        mcp = "generated";
        engineering_rules = "degraded";
        test_strategy = "degraded";
      };
    };
  };

  kiro = {
    display_name = "Kiro";
    targets = {
      cli = {
        tier = 4;
        surfaces = {
          steering = "supported";
          skills = "supported";
          agents = "generated";
          workflows = "generated";
          specs = "unsupported";
          hooks = "generated";
          mcp = "generated";
          permissions = "generated";
          engineering_rules = "generated";
          test_strategy = "generated";
        };
      };
      ide = {
        tier = 4;
        surfaces = {
          steering = "supported";
          skills = "supported";
          agents = "generated";
          workflows = "generated";
          specs = "unsupported";
          hooks = "degraded";
          mcp = "generated";
          permissions = "generated";
          engineering_rules = "generated";
          test_strategy = "generated";
        };
      };
    };
  };

  cursor = {
    display_name = "Cursor";
    targets.ide = {
      tier = 1;
      surfaces = {
        context = "supported";
        rules = "generated";
        commands = "degraded";
        skills = "unsupported";
        roles = "unsupported";
        permissions = "unsupported";
        hooks = "unsupported";
        mcp = "provider_owned";
        engineering_rules = "degraded";
        test_strategy = "degraded";
      };
    };
  };

  continue = {
    display_name = "Continue";
    targets.ide = {
      tier = 1;
      surfaces = {
        context = "generated";
        rules = "generated";
        commands = "degraded";
        skills = "unsupported";
        roles = "unsupported";
        permissions = "unsupported";
        hooks = "unsupported";
        mcp = "provider_owned";
        engineering_rules = "degraded";
        test_strategy = "degraded";
      };
    };
  };

  opencode = {
    display_name = "OpenCode";
    targets.cli = {
      tier = 2;
      surfaces = {
        context = "supported";
        rules = "generated";
        commands = "degraded";
        skills = "degraded";
        roles = "unsupported";
        permissions = "unsupported";
        hooks = "unsupported";
        mcp = "provider_owned";
        engineering_rules = "degraded";
        test_strategy = "degraded";
      };
    };
  };

  cline-roo = {
    display_name = "Cline/Roo";
    targets.ide = {
      tier = 1;
      surfaces = {
        context = "supported";
        rules = "generated";
        commands = "degraded";
        skills = "unsupported";
        roles = "unsupported";
        permissions = "unsupported";
        hooks = "unsupported";
        mcp = "provider_owned";
        engineering_rules = "degraded";
        test_strategy = "degraded";
      };
    };
  };
}
