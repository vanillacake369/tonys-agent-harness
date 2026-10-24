{lib}: let
  contracts = import ../../contract-validated.nix {inherit lib;};
  workflowIndex = import ../../contract-workflow-index.nix {inherit lib;};
  capabilities = import ./capabilities.nix;
  attrTools = import ../../runtime-attrs.nix {inherit lib;};
  inherit (attrTools) clean removeNulls yamlString;
  join = lib.concatStringsSep;

  codexModel = "gpt-6.1-sol";
  codexTui = {
    vim_mode_default = true;
    status_line = [
      "model-with-reasoning"
      "current-dir"
      "git-branch"
      "permissions"
      "five-hour-limit"
      "weekly-limit"
      "task-progress"
    ];
    status_line_use_colors = true;
  };

  # Codex hook은 provider runtime 이벤트를 공통 알림 hook으로 연결하는 얇은 adapter다.
  # hook 자체의 행위 정책은 providers/claude/hooks 쪽 shell test가 검증한다.
  mkProviderHooks = {}: {
    SessionStart = [
      {
        hooks = [
          {
            type = "command";
            command = "~/.nix-profile/bin/python3 ~/.config/agents/governance/policy-preflight.py --provider codex --managed-fragment harness-policy-preflight-v1 && ~/.nix-profile/bin/python3 ~/.config/agents/governance/task-lifecycle.py start";
            timeout = 10;
          }
        ];
      }
    ];
    PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "bash ~/.config/agents/governance/pre-tool-gate.sh --provider codex --profile default-allow-operations-v1 --managed-fragment harness-operation-policy-v1";
            timeout = 5;
          }
        ];
      }
    ];
    PostToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "bash ~/.config/agents/governance/retry-hook.sh post";
            timeout = 5;
          }
        ];
      }
    ];
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "python3 ~/.config/agents/governance/task-lifecycle.py stop >/dev/null";
            timeout = 5;
          }
          {
            type = "command";
            command = "~/.config/agents/hooks/agent-notify.sh codex";
            timeout = 5;
          }
        ];
      }
    ];
  };
  providerHooks = mkProviderHooks {};

  # Codex MCP schema는 remote server에서 stdio 필드를 제거하고 header 이름을 바꾼다.
  # disabled 기본값은 Codex의 enabled 필드로 명시해서 출력한다.
  renderMcpServer = srv: let
    hasUrl = srv ? url && srv.url != null;
    attrsToRemove =
      [
        "bearerTokenEnvVar"
        "disabled"
        "enabled"
        "headers"
        "envHttpHeaders"
        "transport"
      ]
      ++ lib.optionals hasUrl [
        "args"
        "command"
        "cwd"
        "env"
      ];
    base =
      removeNulls (lib.removeAttrs srv attrsToRemove)
      // (lib.optionalAttrs (srv ? headers && srv.headers != {} && !(srv ? http_headers)) {
        http_headers = removeNulls srv.headers;
      })
      // (lib.optionalAttrs (srv ? bearerTokenEnvVar) {
        bearer_token_env_var = srv.bearerTokenEnvVar;
      })
      // (lib.optionalAttrs (srv ? envHttpHeaders && srv.envHttpHeaders != {}) {
        env_http_headers = removeNulls srv.envHttpHeaders;
      })
      // {enabled = !(srv.disabled or false);};
  in
    clean base;

  # 워크플로 요구 능력을 Codex skill 본문에 표시할 짧은 문장으로 만든다.
  # 빈 문자열은 호출부에서 명시적인 "추가 권한 없음" 문구로 바꾼다.
  renderNeeds = workflow:
    join ", " (
      (lib.optional workflow.mutatesFiles "workspace-write")
      ++ (lib.optional workflow.needsNetwork "network")
      ++ (map (name: "mcp:${name}") workflow.needsMcp)
    );

  # provider-neutral workflow index를 Codex skill 문서로 투영한다.
  # provider 고유 정보는 별칭과 사용면(surface) 설명에만 한정한다.
  renderCodexSkill = workflow: let
    needsText = renderNeeds workflow;
    hasExtraNeeds = needsText != "";
  in ''
    ---
    name: ${workflow.skillName}
    description: ${yamlString workflow.description}
    ---

    # ${workflow.skillName}

    Use this Codex skill when the user asks for the provider-neutral workflow
    `${workflow.name}` or the Claude slash command `${workflow.claudeCommand}`.

    Claude command alias: `${workflow.claudeCommand}`
    Recommended role: `${workflow.role}`
    Argument hint: ${workflow.argumentHint}
    Spec inputs: ${join ", " workflow.specInputs}
    Validation gates: ${join ", " workflow.validationGates}
    Required rules: ${join ", " workflow.requiredRules}
    Required capabilities: ${
      if hasExtraNeeds
      then needsText
      else "none beyond the active session permissions"
    }

    If the source prompt refers to `$ARGUMENTS`, treat the current user request
    and any explicit context as that argument value. Claude-only command syntax
    is provenance, not a requirement to call Claude-specific tools.

    ## Source Prompt

    ${workflow.body}
  '';

  # command workflow를 Codex skill로 투영한다.
  # 실제 prompt 원문은 contract-workflow-index가 읽은 shared workflow body를 따른다.
  codexSkills =
    lib.mapAttrs' (_: workflow: {
      name = workflow.skillName;
      value = renderCodexSkill workflow;
    })
    workflowIndex.commandWorkflows;

  skillBundleSkills =
    lib.mapAttrs' (_: skill: {
      name = skill.name;
      value = ''
        ---
        name: ${skill.name}
        description: ${yamlString skill.description}
        ---

        # ${skill.name}

        This is an internal lifecycle capability selected by the public
        `cmd-*` command facade. It is not an independent approval or
        external-mutation authority.

        Owner: `${skill.owner}`
        Composed canonical workflows: ${join ", " skill.members}

        ${skill.body}
      '';
    })
    workflowIndex.skillBundles;
in {
  inherit contracts capabilities codexModel codexTui providerHooks mkProviderHooks renderMcpServer;
  inherit (workflowIndex) commandWorkflows legacyWorkflows skillBundles sharedGuide;
  inherit codexSkills skillBundleSkills;
}
