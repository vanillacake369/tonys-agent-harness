# Kiro 설정을 provider 계약 기반 산출물로 구성한다.
# global 실행 표면과 tonys-nix 전용 SSoT 표면을 분리해 symlink 충돌을 줄인다.
{
  config,
  lib,
  pkgs,
  ...
}: let
  json = pkgs.formats.json {};
  providerSettings = import ../../runtime-provider-settings.nix {inherit config lib pkgs;};
  kiroRender = import ./render.nix {inherit lib;};

  mcpSourceFile = providerSettings.mkFile {
    format = "json";
    name = "kiro-mcp.json";
    value = {
      mcpServers = providerSettings.mcp.kiro;
    };
  };

  workflowRecipeFiles =
    lib.mapAttrs' (name: recipe: {
      name = ".kiro/workflows/${name}.workflow.json";
      value.source = json.generate "kiro-workflow-${name}.json" recipe;
    })
    kiroRender.workflowRecipes;

  agentFiles =
    lib.mapAttrs' (name: agent: {
      name = ".kiro/agents/${name}.json";
      value.source = json.generate "kiro-agent-${name}.json" agent;
    })
    kiroRender.agents;

  workflowSkillFiles =
    lib.mapAttrs' (name: body: {
      name = ".kiro/skills/${name}/SKILL.md";
      value.text = body;
    })
    kiroRender.workflowSkills;

  skillBundleFiles =
    lib.mapAttrs' (skillName: body: {
      name = ".kiro/skills/${skillName}/SKILL.md";
      value.text = body;
    })
    kiroRender.skillBundleSkills;
  governanceHooks = {
    version = "v1";
    hooks = [
      {
        name = "harness-policy-preflight-v1";
        trigger = "AgentSpawn";
        action = {
          type = "command";
          command = "~/.config/agents/governance/python3 ~/.config/agents/governance/policy-runtime.py startup --provider kiro --surface cli --managed-fragment harness-policy-preflight-v1; ~/.config/agents/governance/python3 ~/.config/agents/governance/task-lifecycle.py start";
        };
      }
      {
        name = "harness-operation-policy-v1";
        trigger = "PreToolUse";
        matcher = "^(execute_bash|execute_pwsh)$";
        action = {
          type = "command";
          command = "~/.config/agents/governance/python3 ~/.config/agents/governance/policy-runtime.py pretool --provider kiro --surface cli --profile default-allow-operations-v1 --managed-fragment harness-operation-policy-v1";
        };
      }
      {
        name = "harness-path-invariants-v1";
        trigger = "PreToolUse";
        matcher = "^(fs_read|fs_write|fs_append|str_replace|delete_file)$";
        action = {
          type = "command";
          command = "~/.config/agents/governance/python3 ~/.config/agents/governance/policy-runtime.py pretool --provider kiro --surface cli --profile default-allow-operations-v1 --managed-fragment harness-path-invariants-v1";
        };
      }
      {
        name = "engineering-post-tool";
        trigger = "PostToolUse";
        matcher = "^(execute_bash|execute_pwsh|fs_write|fs_append|str_replace|delete_file)$";
        action = {
          type = "command";
          command = "bash ~/.config/agents/governance/retry-hook.sh post";
        };
      }
      {
        name = "engineering-completion";
        trigger = "Stop";
        action = {
          type = "command";
          command = "bash ~/.config/agents/governance/kiro-stop.sh";
        };
      }
    ];
  };
  governanceHooksFile = json.generate "kiro-engineering-governance.json" governanceHooks;
in {
  home.file =
    {
      ".kiro/tonys-nix/steering/AGENTS.md".source = ../../../../AGENTS.md;
      ".kiro/tonys-nix/steering/agent-contract.md".text = kiroRender.steering;
      ".kiro/skills/a2a-workflow".source = ../../skills/a2a-workflow;
    }
    // agentFiles
    // workflowSkillFiles
    // skillBundleFiles
    // workflowRecipeFiles;

  # Kiro는 MCP 설정을 IDE/CLI가 직접 수정하는 흐름을 권장한다.
  # 따라서 Nix는 기본 파일이 없을 때만 seed하고, 이후 같은 server key도 덮어쓰지 않는다.
  home.activation.seedKiroMcp = providerSettings.mkSeedFileCopy {
    target = "$HOME/.kiro/settings/mcp.json";
    source = "${mcpSourceFile}";
  };

  home.activation.syncKiroHooks = providerSettings.mkSync {
    name = "kiro-hooks";
    target = "$HOME/.kiro/hooks/engineering-governance.json";
    source = "${governanceHooksFile}";
  };
}
