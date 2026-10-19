{lib}: let
  contracts = import ../../contract-validated.nix {inherit lib;};
  workflowIndex = import ../../contract-workflow-index.nix {inherit lib;};
  attrTools = import ../../runtime-attrs.nix {inherit lib;};
  inherit (attrTools) clean yamlString;
  inherit (workflowIndex) commandWorkflows;
  join = lib.concatStringsSep;

  secretGlobs = [
    "**/.env*"
    "**/*credentials*"
    "**/secrets/**"
    "**/*private*key*"
    "**/.ssh/**"
    "**/.gnupg/**"
  ];

  # Kiro MCP schema는 stdio와 HTTP server 모두 JSON mcpServers 아래에 둔다.
  # envHttpHeaders는 런타임 환경변수 확장 문자열로 바꿔 secret 값을 파일에 쓰지 않는다.
  renderMcpServer = srv: let
    envHeaders =
      lib.mapAttrs (_: envName: "\${${envName}}")
      (srv.envHttpHeaders or {});
    headerAttrs =
      (srv.headers or {})
      // envHeaders
      // (lib.optionalAttrs (srv ? bearerTokenEnvVar) {
        Authorization = "Bearer \${${srv.bearerTokenEnvVar}}";
      });
    base = {
      disabled = srv.disabled or false;
      autoApprove = srv.autoApprove or null;
      disabledTools = srv.disabledTools or null;
    };
  in
    if srv ? command && srv.command != null
    then
      clean (base
        // {
          inherit (srv) command;
          args = srv.args or [];
          env = srv.env or null;
          timeout = srv.timeout or null;
          requestTimeout = srv.requestTimeout or null;
        })
    else if srv ? url && srv.url != null
    then
      clean (base
        // {
          inherit (srv) url;
          headers = headerAttrs;
          env = srv.env or null;
          timeout = srv.timeout or null;
          requestTimeout = srv.requestTimeout or null;
          oauth = srv.oauth or null;
          oauthScopes = srv.oauthScopes or null;
        })
    else {};

  # provider-neutral permission을 Kiro rules 배열로 낮춘다.
  # secret deny는 읽기/쓰기 권한과 무관하게 항상 먼저 선언한다.
  mkPermissionRules = permission: let
    canWrite = permission.workspace == "write";
    hasNetwork = permission.network or false;
    denySecret = capability: {
      inherit capability;
      match = secretGlobs;
      effect = "deny";
    };
  in
    [
      (denySecret "fs_read")
      (denySecret "fs_write")
      {
        capability = "shell";
        match = [
          "rm -rf *"
          "sudo *"
          "git reset --hard*"
          "git push --force*"
        ];
        effect = "deny";
      }
    ]
    ++ lib.optional (!canWrite) {
      capability = "fs_write";
      match = ["**"];
      effect = "deny";
    }
    ++ lib.optional hasNetwork {
      capability = "sandbox_network";
      match = ["*"];
      effect = "allow";
    };

  # Kiro tool 목록은 coarse-grained capability만 표현한다.
  # 더 세밀한 차단은 permissions.rules가 담당한다.
  mkTools = permission:
    ["read"]
    ++ lib.optionals (permission.workspace == "write") [
      "write"
      "shell"
    ]
    ++ lib.optional (permission.network or false) "web";

  # Kiro custom agent는 tonys-nix 전용 steering과 skills/MCP를 명시 resource로 연결한다.
  # custom agent에서는 project/global steering 자동 포함에 의존하지 않고 resources가 SSoT 연결점이다.
  mkAgent = name: role: let
    permission = contracts.permissions.${role.default_permission};
  in
    clean {
      inherit name;
      inherit (role) description;
      prompt = ''
        You are the Kiro ${name} agent.

        ${role.description}

        Follow the shared steering and skill resources. Keep work scoped to this
        role, preserve user changes, and report findings with local evidence.
      '';
      tools = mkTools permission;
      includeMcpJson = false;
      resources = [
        "file://~/.kiro/tonys-nix/steering/**/*.md"
        "skill://~/.kiro/skills/**/SKILL.md"
      ];
      permissions.rules = mkPermissionRules permission;
      welcomeMessage = "Ready as ${name}.";
    };

  publicRoles = lib.filterAttrs (_: role: role.public or false) contracts.roles;
  agents = lib.mapAttrs mkAgent publicRoles;

  renderWorkflowSkill = workflow: ''
    ---
    name: ${workflow.skillName}
    description: ${yamlString workflow.description}
    ---

    # ${workflow.skillName}

    Use this Kiro skill when the user asks for `${workflow.name}` or the
    equivalent shared agent workflow.

    Recommended role: `${workflow.role}`
    Argument hint: ${workflow.argumentHint}
    Spec inputs: ${join ", " workflow.specInputs}
    Validation gates: ${join ", " workflow.validationGates}
    Required rules: ${join ", " workflow.requiredRules}

    If this skill is invoked with extra text, treat that text as `$ARGUMENTS`.

    ## Source Prompt

    ${workflow.body}
  '';

  workflowSkills =
    lib.mapAttrs' (_: workflow: {
      name = workflow.skillName;
      value = renderWorkflowSkill workflow;
    })
    commandWorkflows;

  skillBundleSkills =
    lib.mapAttrs' (_: skill: {
      name = skill.name;
      value = ''
        ---
        name: ${skill.name}
        description: ${yamlString skill.description}
        ---

        # ${skill.name}

        Internal capability selected by the public `cmd-*` command facade.
        Owner: `${skill.owner}`
        Composed canonical workflows: ${join ", " skill.members}

        ${skill.body}
      '';
    })
    workflowIndex.skillBundles;

  # Kiro workflow recipe는 provider-native 실행 단위다.
  # prompt body는 shared workflow에서 가져오고, role만 Kiro agent 이름으로 연결한다.
  renderWorkflowRecipe = workflow: let
    step = {
      type = "step";
      id = "run-${workflow.name}";
      agent = workflow.role;
      prompt = ''
        Follow the shared `${workflow.name}` workflow for this task.

        ${builtins.replaceStrings ["$ARGUMENTS"] ["{{task}}"] workflow.body}

        Task:
        {{task}}
      '';
    };
  in {
    name = workflow.name;
    description = workflow.description;
    inputs.task = workflow.argumentHint;
    steps = [step];
  };
in {
  inherit agents;
  inherit workflowSkills;
  inherit skillBundleSkills;
  inherit renderMcpServer;
  inherit contracts;
  workflowRecipes = lib.mapAttrs (_: renderWorkflowRecipe) commandWorkflows;
  steering = ''
    # Tonys Nix Agent Contract

    This Kiro configuration is projected from `modules/agents`.

    - Shared behavior: `AGENTS.md`
    - Provider-neutral contract: `contract-*.nix`
    - Provider-neutral config: `config-*.nix`
    - Local integration: `runtime-*.nix`
    - Provider adapters: `providers/<provider>/`

    Kiro custom agents load tonys-nix steering and skills through their
    `resources` field so provider-local files stay adapter-only.
  '';
}
