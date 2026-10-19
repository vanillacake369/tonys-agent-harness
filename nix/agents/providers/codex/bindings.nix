# 공유 agent guide와 계약을 Codex provider 표면으로 변환한다.
# 순수 데이터/함수로 유지해서 Home Manager 전체 평가 없이 테스트할 수 있게 한다.
{lib}: let
  join = lib.concatStringsSep;
  codexRender = import ./render.nix {inherit lib;};
  attrTools = import ../../runtime-attrs.nix {inherit lib;};
  inherit (attrTools) yamlString;
  inherit (codexRender) contracts;
  a2aWorkflowDir = ../../skills/a2a-workflow;
  a2aWorkflowSkill = builtins.readFile (a2aWorkflowDir + "/SKILL.md");
  a2aWorkflowReferences = {
    routing = builtins.readFile (a2aWorkflowDir + "/references/routing.md");
    agent-contracts = builtins.readFile (a2aWorkflowDir + "/references/agent-contracts.md");
    guardrails = builtins.readFile (a2aWorkflowDir + "/references/guardrails.md");
    artifact-schemas = builtins.readFile (a2aWorkflowDir + "/references/artifact-schemas.md");
  };
  secretDenyGlobs = [
    "**/.env*"
    "**/*credentials*"
    "**/secrets/**"
    "**/*private*key*"
    "**/.ssh/**"
    "**/.gnupg/**"
  ];
  secretDenyAttrs =
    builtins.listToAttrs
    (map (glob: {
        name = glob;
        value = "deny";
      })
      secretDenyGlobs);

  # Codex permission profile은 domain object처럼 자기 불변식을 포함한다.
  # write/network를 명시 입력으로 받고 secret deny는 호출자가 빠뜨릴 수 없게 내부에서 합성한다.
  mkReadProfile = {
    network ? false,
    write ? false,
  }: {
    filesystem = {
      ":minimal" = "read";
      ":workspace_roots" =
        {
          "." =
            if write
            then "write"
            else "read";
        }
        // secretDenyAttrs;
      glob_scan_max_depth = 8;
    };
    network = {
      enabled = network;
      mode = "limited";
      domains = lib.optionalAttrs network {
        "*" = "allow";
      };
    };
  };

  roles =
    lib.mapAttrs
    (_: role:
      role
      // {
        # 기존 Codex 출력 호환성을 위해 camelCase alias를 유지한다.
        permissionProfile = role.default_permission;
      })
    contracts.roles;

  publicRoles = lib.filterAttrs (_: role: role.public or false) roles;

  workflows =
    lib.mapAttrs
    (_: workflow: {
      inherit (workflow) role description;
      # 기존 Codex 출력 호환성을 위해 camelCase alias를 유지한다.
      requiredRules = workflow.required_rules or [];
      validationGates = workflow.validation_gates or [];
      specInputs = workflow.spec_inputs or [];
    })
    (lib.filterAttrs (_: workflow: workflow.source == null) contracts.workflows);

  permissionProfiles =
    lib.mapAttrs
    (_: permission:
      mkReadProfile {
        write = permission.workspace == "write";
        network = permission.network or false;
      })
    contracts.permissions;

  # Codex custom agent가 공유 역할 계약을 따르도록 developer instruction을 생성한다.
  # provider 전용 TOML에는 역할 설명과 운영 경계만 담는다.
  mkDeveloperInstructions = name: role: ''
    You are the Codex ${name} subagent.

    ${role.description}

    Follow the shared AGENTS.md contract for orchestration, escalation, and
    reporting. Keep work scoped to this role. Do not revert edits made by
    other agents or the user.
  '';

  roleSkills =
    lib.mapAttrs' (name: role: {
      name = "agent-${name}";
      value = ''
        ---
        name: agent-${name}
        description: ${yamlString role.description}
        ---

        # agent-${name}

        Use this Codex skill when the shared agent guide routes work to `${name}`.
        The shared guide is the canonical provider-neutral instruction source
        for the executable `modules/agents` contract; this file only binds that
        provider-neutral role to Codex's skill surface. Runtime subagent
        behavior is bound through `~/.codex/agents/${name}.toml`, which selects
        the `${role.permissionProfile}` permission profile.

        Rule scope: ${join ", " (role.rule_scope or [])}
        Spec responsibility: ${role.spec_responsibility or "unspecified"}
      '';
    })
    roles;

  publicRoleSkills = lib.filterAttrs (name: _: contracts.roles.${builtins.substring 6 1000 name}.public or false) roleSkills;

  workflowSkills =
    lib.mapAttrs (name: workflow: ''
      ---
      name: ${name}
      description: ${yamlString workflow.description}
      ---

      # ${name}

      Use this Codex skill for the `${workflow.role}` workflow described by the
      shared agent guide. The shared guide is the canonical provider-neutral
      instruction source for the executable `modules/agents` contract; this file
      only binds that provider-neutral workflow to Codex's skill surface.

      Spec inputs: ${join ", " (workflow.specInputs or [])}
      Validation gates: ${join ", " (workflow.validationGates or [])}
      Required rules: ${join ", " (workflow.requiredRules or [])}
    '')
    workflows;

  # 참조 파일을 skill bundle에 inline해서 provider runtime이 repo 외부에서도 같은 지시를 읽게 한다.
  # 원본은 nix/agents/skills 아래이며, 이 값은 Codex 출력용 projection이다.
  generatedSkillAssets = {
    a2a-workflow = ''
      ${a2aWorkflowSkill}

      ## Generated Reference Bundle

      This Codex skill is generated from `nix/agents/skills/a2a-workflow/`.
      The source directory is the repository-owned SSoT; this generated bundle
      inlines the referenced workflow material so the skill is reproducible
      anywhere this Nix configuration is evaluated.

      ### references/routing.md

      ${a2aWorkflowReferences.routing}

      ### references/agent-contracts.md

      ${a2aWorkflowReferences.agent-contracts}

      ### references/guardrails.md

      ${a2aWorkflowReferences.guardrails}

      ### references/artifact-schemas.md

      ${a2aWorkflowReferences.artifact-schemas}
    '';
  };

  # Codex 기본 컨텍스트에 Claude 지향 역할명을 Codex skill/profile로 매핑한다.
  # 원본 AGENTS.md 본문은 provider-neutral 계약으로 그대로 포함한다.
  mkContext = sharedContext: ''
    # Codex Provider Bridge

    The shared agent guide below is the canonical provider-neutral instruction
    source for the executable `modules/agents` contract. In Codex, map
    Claude-oriented sub-agent references to Codex skills:

    ${join "\n" (
      lib.mapAttrsToList (
        name: role: "- `${name}` -> `agent-${name}` / permission profile `${role.permissionProfile}`"
      )
      publicRoles
    )}

    Claude-only tool metadata, model names, colors, and `Agent(...)` calls are
    provider-specific details and do not change the shared behavioral contract.

    ${sharedContext}
  '';

  # custom agent 파일은 역할 이름, 권한 profile, developer instruction만 가진다.
  # 세부 정책은 AGENTS.md와 contract-*가 소유한다.
  customAgents =
    lib.mapAttrs (name: role: {
      inherit name;
      inherit (role) description;
      developer_instructions = mkDeveloperInstructions name role;
      model = codexRender.codexModel;
      default_permissions = role.permissionProfile;
    })
    publicRoles;

  publicSkills = publicRoleSkills // codexRender.codexSkills // codexRender.skillBundleSkills // generatedSkillAssets;
in {
  inherit roles publicRoles workflows permissionProfiles roleSkills publicRoleSkills publicSkills workflowSkills customAgents mkContext;
  inherit contracts;
  inherit (codexRender) commandWorkflows legacyWorkflows skillBundles capabilities;

  skills = publicSkills;

  # Codex config.toml에 들어갈 설정 shape를 만든다.
  # model/tui 같은 provider UI 값은 module render 단계에서만 합성한다.
  mkSettings = {
    hooks ? {},
    mcp ? {},
  }: {
    default_permissions = "default";
    permissions = permissionProfiles;
    inherit hooks;
    mcp_servers = mcp;
  };
}
