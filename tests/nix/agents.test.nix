{lib}: let
  mcpRender = import ../../nix/agents/runtime-mcp-render.nix {inherit lib;};
  agentContracts = import ../../nix/agents/contract-validated.nix {inherit lib;};
  governance = agentContracts.governance;
  workflowIndex = import ../../nix/agents/contract-workflow-index.nix {inherit lib;};
  capabilityReport = import ../../nix/agents/contract-capability-report.nix {inherit lib;};
  agentMcp = (import ../../nix/agents/config-mcp.nix {}).programs.mcp.servers;
  codexBindings = import ../../nix/agents/providers/codex/bindings.nix {inherit lib;};
  codexRender = import ../../nix/agents/providers/codex/render.nix {inherit lib;};
  geminiRender = import ../../nix/agents/providers/gemini/render.nix {inherit lib;};
  kiroRender = import ../../nix/agents/providers/kiro/render.nix {inherit lib;};
  claudeBaseSettings = builtins.fromJSON (builtins.readFile ../../nix/agents/providers/claude/settings.json);
  normalizeConfig = import ../../nix/normalize-config.nix {inherit lib;};
  normalizedHarness = normalizeConfig {
    schema_version = 1;
    preset = "infra-devops";
    project = {
      instruction = "AGENTS.md";
      spec_root = ".codex";
      guides = {
        enabled = true;
        source = "/tmp/team-guidelines";
        link = ".agent-context/team-guides";
      };
    };
    providers = {
      codex = true;
      claude = false;
      gemini = true;
      kiro = true;
    };
    workflow = {
      public_commands = ["cmd-mid-work-ljh"];
      roles = ["implementer" "reviewer"];
    };
    permissions = {
      secret_access = "deny";
      reviewer_write = false;
      researcher_write = false;
      single_writer = true;
    };
    approval = {
      production = true;
      destructive = true;
      migration = true;
      external_mutation = true;
      public_key_path = "/tmp/public.pem";
      expected_fingerprint = "";
    };
    verification = {
      retry_max = 3;
      require_clean_git_for_done = true;
    };
  };
  normalizedFixture = normalizeConfig (builtins.fromTOML (builtins.readFile ../fixtures/agent-harness.toml));
  expectedNormalizedFixture = builtins.fromJSON (builtins.readFile ../fixtures/normalized-config.json);

  assert' = name: cond:
    if cond
    then {
      inherit name;
      pass = true;
    }
    else throw "FAIL: ${name}";

  mockServers = {
    test-server = {
      command = "npx";
      args = ["-y" "test-mcp"];
      url = null;
      headers = {"X-Key" = "val";};
    };
    remote-server = {
      url = "https://mcp.example.test";
      transport = "streamable-http";
      args = [];
      headers = {"X-Key" = "val";};
      bearerTokenEnvVar = "EXAMPLE_MCP_TOKEN";
      envHttpHeaders.Authorization = "EXAMPLE_MCP_AUTHORIZATION";
    };
  };
  rendered = mcpRender mockServers;
  guideText = builtins.readFile ../../AGENTS.md;
  moduleText = builtins.readFile ../../nix/agents/runtime-module.hm.nix;
  homeManagerModuleText = builtins.readFile ../../nix/home-manager-module.nix;
  secretsModuleText = builtins.readFile ../../nix/agents/runtime-secrets.hm.nix;
  roleNames = builtins.attrNames codexBindings.roles;
  publicRoleNames = builtins.attrNames codexBindings.publicRoles;
  commandWorkflowNames = builtins.attrNames workflowIndex.commandWorkflows;
  legacyWorkflowNames = builtins.attrNames workflowIndex.legacyWorkflows;
  skillBundleNames = builtins.attrNames workflowIndex.skillBundles;
  sampleSettings = codexBindings.mkSettings {
    hooks = codexRender.providerHooks;
    mcp = {test-server = {enabled = true;};};
  };
  codexHeadersRemoved = !(rendered.codex.test-server ? headers);
  sampleSettingsHasNoTui = !(sampleSettings ? tui);
  profileNames = builtins.attrNames codexBindings.permissionProfiles;
  kiroAgentNames = builtins.attrNames kiroRender.agents;
  kiroWorkflowNames = builtins.attrNames kiroRender.workflowRecipes;
in {
  # 이 guard는 provider 출력이 contract에서 벗어나는 순간 Nix 평가 단계에서 실패하게 한다.
  # GWT 문장을 test name으로 써서 어떤 계약 경계가 깨졌는지 바로 읽히게 유지한다.
  results = [
    (assert' "GIVEN one manifest WHEN Nix normalizes it THEN provider and project selections are preserved" (
      normalizedHarness.providers
      == ["codex" "gemini" "kiro"]
      && normalizedHarness.project.spec_root == ".codex"
      && normalizedHarness.project.guides.enabled
      && normalizedHarness.approval.public_key_path == "/tmp/public.pem"
    ))
    (assert' "GIVEN the shared fixture WHEN Python and Nix normalize THEN Nix matches the canonical JSON" (
      normalizedFixture == expectedNormalizedFixture
    ))
    (assert' "GIVEN the Home Manager adapter WHEN disabled THEN runtime modules are not imported unconditionally" (
      !(lib.hasInfix "runtime-module.hm.nix" homeManagerModuleText)
      && lib.hasInfix "lib.mkIf cfg.enable" homeManagerModuleText
      && lib.hasInfix "harness export" homeManagerModuleText
      && lib.hasInfix "reconcile-guides" homeManagerModuleText
    ))
    (assert' "GIVEN the Home Manager adapter WHEN enabled THEN immutable input and editable workspace stay separate" (
      lib.hasInfix "workspaceRoot" homeManagerModuleText
      && lib.hasInfix "projectSource" homeManagerModuleText
      && lib.hasInfix "--workspace" homeManagerModuleText
    ))
    (assert' "GIVEN provider hooks WHEN Home Manager activates THEN every shared runtime hook is installed" (
      lib.hasInfix ".config/agents" homeManagerModuleText
      && lib.hasInfix "runtimeFiles" homeManagerModuleText
      && lib.hasInfix "agent-notify.sh" homeManagerModuleText
    ))
    (assert' "GIVEN MCP source WHEN rendering Codex stdio server THEN enabled flag is present" (
      rendered.codex.test-server.enabled == true
    ))
    (assert' "GIVEN MCP source WHEN rendering Codex stdio server THEN command args are preserved" (
      rendered.codex.test-server.command
      == "npx"
      && rendered.codex.test-server.args == ["-y" "test-mcp"]
      && !(rendered.codex.test-server ? url)
    ))
    (assert' "GIVEN MCP source WHEN rendering Codex server THEN headers are renamed to http_headers" (
      rendered.codex.test-server ? http_headers
    ))
    (assert' "GIVEN MCP source WHEN rendering Codex server THEN original headers are removed" codexHeadersRemoved)
    (assert' "GIVEN MCP source WHEN rendering Codex remote server THEN bearer token uses env var" (
      rendered.codex.remote-server.url
      == "https://mcp.example.test"
      && rendered.codex.remote-server.http_headers.X-Key == "val"
      && rendered.codex.remote-server.bearer_token_env_var == "EXAMPLE_MCP_TOKEN"
      && rendered.codex.remote-server.env_http_headers.Authorization == "EXAMPLE_MCP_AUTHORIZATION"
      && !(rendered.codex.remote-server ? args)
      && !(rendered.codex.remote-server ? bearerTokenEnvVar)
    ))
    (assert' "GIVEN MCP source WHEN rendering Gemini stdio server THEN only command and args remain" (
      rendered.gemini.test-server
      == {
        command = "npx";
        args = ["-y" "test-mcp"];
      }
    ))
    (assert' "GIVEN MCP source WHEN rendering Gemini remote server THEN streamable HTTP uses httpUrl" (
      rendered.gemini.remote-server
      == {
        httpUrl = "https://mcp.example.test";
        headers = {"X-Key" = "val";};
      }
    ))
    (assert' "GIVEN MCP source WHEN rendering Claude stdio server THEN type is stdio" (
      rendered.claude.test-server.type
      == "stdio"
      && rendered.claude.test-server.command == "npx"
    ))
    (assert' "GIVEN MCP source WHEN rendering Claude remote server THEN type is http" (
      rendered.claude.remote-server
      == {
        headers = {"X-Key" = "val";};
        type = "http";
        url = "https://mcp.example.test";
      }
      && !(rendered.claude.remote-server ? args)
    ))
    (assert' "GIVEN MCP source WHEN rendering Kiro stdio server THEN command args are preserved" (
      rendered.kiro.test-server
      == {
        command = "npx";
        args = ["-y" "test-mcp"];
        disabled = false;
      }
    ))
    (assert' "GIVEN MCP source WHEN rendering Kiro remote server THEN headers use runtime env expansion" (
      rendered.kiro.remote-server.url
      == "https://mcp.example.test"
      && rendered.kiro.remote-server.headers.X-Key == "val"
      && rendered.kiro.remote-server.headers.Authorization == "Bearer \${EXAMPLE_MCP_TOKEN}"
      && !(rendered.kiro.remote-server ? args)
      && !(rendered.kiro.remote-server ? bearerTokenEnvVar)
    ))
    (assert' "GIVEN agent guide WHEN guide text is read THEN operating guide is present" (
      lib.hasInfix "Agent Operating Guide" guideText
    ))
    (assert' "GIVEN agent MCP WHEN Atlassian is configured THEN official v2 endpoint and runtime auth are used" (
      agentMcp.atlassian.url
      == "https://mcp.atlassian.com/v2/mcp"
      && agentMcp.atlassian.envHttpHeaders.Authorization == "ATLASSIAN_MCP_AUTHORIZATION"
    ))
    (assert' "GIVEN agent secrets WHEN activation runs THEN platform SOPS identity and runtime auth are used" (
      lib.hasInfix "AGENT_SOPS_AGE_KEY_FILE" secretsModuleText
      && lib.hasInfix "export SOPS_AGE_KEY_FILE" secretsModuleText
      && lib.hasInfix "Library/Application Support/sops/age/keys.txt" secretsModuleText
      && lib.hasInfix ''ATLASSIAN_MCP_AUTHORIZATION="Basic $encoded"'' secretsModuleText
    ))
    (assert' "GIVEN Codex renderer WHEN Codex model is read THEN model is explicit" (
      codexRender.codexModel == "gpt-6.1-sol"
    ))
    (assert' "GIVEN provider hooks WHEN Codex stop hook is read THEN timeout uses seconds" (
      (builtins.head (builtins.head codexRender.providerHooks.Stop).hooks).timeout == 5
    ))
    (assert' "GIVEN provider hooks WHEN Gemini after-agent hook is read THEN timeout uses milliseconds" (
      (builtins.head (builtins.head geminiRender.providerHooks.AfterAgent).hooks).timeout == 5000
    ))
    (assert' "GIVEN agent module WHEN provider exporters are wired THEN Codex and Kiro are activated" (
      lib.hasInfix "./providers/codex/module.nix" moduleText
      && lib.hasInfix "./providers/kiro/module.nix" moduleText
      && !(lib.hasInfix "./providers/claude/module.nix" moduleText)
      && !(lib.hasInfix "./providers/gemini/module.nix" moduleText)
      && !(lib.hasInfix "./runtime-proxy.nix" moduleText)
    ))
    (assert' "GIVEN workflow index WHEN index text is checked THEN workflow data stays focused" (
      builtins.hasAttr "commandWorkflows" workflowIndex
      && builtins.hasAttr "sharedGuide" workflowIndex
    ))
    (assert' "GIVEN agent contracts WHEN loading flat contract THEN standard and engineering roles are present" (
      builtins.length (builtins.attrNames agentContracts.roles)
      == 25
      && agentContracts.roles.implementer.default_permission == "agent-implementer"
      && agentContracts.roles.requirement-designer.default_permission == "agent-architect"
      && agentContracts.roles.security-reviewer.default_permission == "agent-cross-validator"
      && agentContracts.roles.orchestrator.default_permission == "agent-architect"
      && codexRender.contracts.roles.reviewer.description == agentContracts.roles.reviewer.description
    ))
    (assert' "GIVEN agent contracts WHEN loading test strategy THEN TDD gates are available" (
      builtins.hasAttr "default-tdd" agentContracts.testStrategies
      && builtins.elem "test_case_scope_selected" agentContracts.testGates
      && builtins.elem "focused_verification" agentContracts.testGates
      && builtins.elem "prd_traceability_complete" agentContracts.testGates
      && builtins.elem "independent_review_complete" agentContracts.testGates
      && builtins.elem "evidence_recorded" agentContracts.testGates
    ))
    (assert' "GIVEN governance contracts WHEN layers are loaded THEN precedence and non-weakening policy are explicit" (
      builtins.length (builtins.attrNames governance.layers)
      == 7
      && governance.layers.global-policy.priority == 100
      && governance.layers.project-policy.can_weaken == false
      && builtins.elem "deny-secret-access" governance.immutablePolicies
    ))
    (assert' "GIVEN governance contracts WHEN authority is resolved THEN policy and execution gates own permissions" (
      governance.authority.policy_engine
      == "deterministic"
      && governance.authority.execution_gate == "deterministic"
      && governance.authority.llm_judge == "advisory"
      && governance.authority.review_gate == "advisory"
    ))
    (assert' "GIVEN governance contracts WHEN project artifacts are resolved THEN specs use provider-neutral root" (
      governance.projectSpecRoot
      == "docs/agent"
      && governance.artifactPaths.prd == "docs/agent/prd"
      && governance.artifactPaths.traceability == "docs/agent/traceability/requirements.tsv"
      && governance.artifactPaths.telemetry == "docs/agent/telemetry/decisions.jsonl"
    ))
    (assert' "GIVEN agent contracts WHEN loading workflow rules THEN implementation workflow references coding policy" (
      builtins.hasAttr "code-implementation" agentContracts.workflows
      && builtins.elem "explicit-error-handling" agentContracts.workflows.code-implementation.required_rules
      && builtins.elem "failing_test_written_or_exemption_recorded"
      agentContracts.workflows.code-implementation.validation_gates
    ))
    (assert' "GIVEN agent contracts WHEN provider capabilities are loaded THEN Kiro surfaces are explicit" (
      agentContracts.providers.kiro.targets.cli.surfaces.skills
      == "supported"
      && agentContracts.providers.kiro.targets.ide.surfaces.specs == "unsupported"
      && capabilityReport.providers.kiro.surfaces.specs.implementation == "unsupported"
    ))
    (assert' "GIVEN capability report WHEN Codex permissions are reported THEN handled fields are explicit" (
      builtins.elem "workspace" capabilityReport.providers.codex.surfaces.permissions.handled_permission_fields
      && builtins.elem "secret_access" capabilityReport.providers.codex.surfaces.permissions.handled_permission_fields
      && capabilityReport.providers.codex.surfaces.permissions.enforcement == "enforced"
    ))
    (assert' "GIVEN capability report WHEN Kiro is active THEN generated surfaces are reported" (
      capabilityReport.providers.kiro.surfaces.skills.implementation
      == "generated"
      && capabilityReport.providers.kiro.surfaces.agents.implementation == "generated"
      && capabilityReport.providers.kiro.surfaces.mcp.implementation == "seeded"
      && capabilityReport.providers.kiro.surfaces.mcp.enforcement == "initial_seed"
    ))
    (assert' "GIVEN Codex bindings WHEN roles are exported THEN only public orchestration roles are exposed" (
      publicRoleNames
      == ["decision-synthesizer" "implementer" "independent-reviewer" "orchestrator" "requirement-designer" "research-engineer"]
      && builtins.length roleNames == 25
      && builtins.hasAttr "agent-requirement-designer" codexBindings.skills
      && builtins.hasAttr "agent-independent-reviewer" codexBindings.skills
    ))
    (assert' "GIVEN Codex bindings WHEN roles are projected THEN only public roles have matching skills" (
      builtins.all (name: builtins.hasAttr "agent-${name}" codexBindings.publicSkills) publicRoleNames
      && !(builtins.hasAttr "agent-architect" codexBindings.publicSkills)
    ))
    (assert' "GIVEN workflow bindings WHEN public commands are promoted THEN six canonical command facades exist" (
      commandWorkflowNames
      == ["cmd-mid-comment-ljh" "cmd-mid-work-ljh" "cmd-post-blog-ljh" "cmd-post-commit-ljh" "cmd-post-handoff-ljh" "cmd-post-ship-ljh"]
      && builtins.length legacyWorkflowNames == 37
      && builtins.elem "commit" legacyWorkflowNames
      && builtins.elem "clarify-requirements" legacyWorkflowNames
      && builtins.elem "strategy-review" legacyWorkflowNames
      && builtins.elem "tdd-implementation" legacyWorkflowNames
      && builtins.elem "independent-review" legacyWorkflowNames
      && builtins.elem "engineering-orchestrator" legacyWorkflowNames
      && workflowIndex.legacyWorkflows.commit.claudeCommand == "/commit"
    ))
    (assert' "GIVEN skill bundles WHEN lifecycle capabilities are loaded THEN VPP responsibilities are composed" (
      skillBundleNames
      == ["skl-mid-impl-ljh" "skl-mid-perf-ljh" "skl-mid-review-ljh" "skl-post-blog-ljh" "skl-post-docs-ljh" "skl-post-ship-ljh" "skl-pre-adr-ljh" "skl-pre-prd-ljh" "skl-pre-research-ljh"]
      && builtins.elem "strategy-review" workflowIndex.skillBundles."skl-pre-adr-ljh".members
      && builtins.elem "code-safety-guardrail" workflowIndex.skillBundles."skl-mid-impl-ljh".members
      && builtins.elem "documentation-handoff" workflowIndex.skillBundles."skl-post-blog-ljh".members
      && builtins.elem "ship" workflowIndex.skillBundles."skl-post-ship-ljh".members == false
    ))
    (assert' "GIVEN strategy review WHEN cross validation is requested THEN agreement and conflict protocol is explicit" (
      workflowIndex.legacyWorkflows.strategy-review.expectedOutputs
      == ["Decision Matrix" "Consensus" "Conflicts" "Unverified Assumptions" "Validation Plan" "ADR"]
      && lib.hasInfix "## Consensus" workflowIndex.legacyWorkflows.strategy-review.body
      && lib.hasInfix "## Conflicts" workflowIndex.legacyWorkflows.strategy-review.body
      && lib.hasInfix "## Unverified Assumptions" workflowIndex.legacyWorkflows.strategy-review.body
      && lib.hasInfix "## Validation Plan" workflowIndex.legacyWorkflows.strategy-review.body
      && lib.hasInfix "합의가 정답이라는 가정을 금지한다" workflowIndex.legacyWorkflows.strategy-review.body
    ))
    (assert' "GIVEN command and skill bindings WHEN Codex skills are rendered THEN facades and bundles are separated" (
      builtins.hasAttr "workflow-cmd-mid-work-ljh" codexBindings.skills
      && builtins.hasAttr "skl-pre-adr-ljh" codexBindings.skills
      && !(builtins.hasAttr "workflow-commit" codexBindings.skills)
      && !(builtins.hasAttr "workflow-evidence-debug" codexBindings.skills)
      && !(builtins.hasAttr "skl-phase-gate-ljh" codexBindings.skills)
    ))
    (assert' "GIVEN multiline workflow description WHEN Codex and Kiro skills are rendered THEN YAML frontmatter is quoted" (
      lib.hasInfix "description: \"Route VPP engineering work through risk, phase, skill, and approval policy\"" codexBindings.skills.workflow-cmd-mid-work-ljh
      && lib.hasInfix "description: \"Route VPP engineering work through risk, phase, skill, and approval policy\"" kiroRender.workflowSkills.workflow-cmd-mid-work-ljh
    ))
    (assert' "GIVEN Codex bindings WHEN A2A skill is exported THEN shared workflow is bundled" (
      builtins.hasAttr "a2a-workflow" codexBindings.skills
      && builtins.pathExists ../../nix/agents/skills/a2a-workflow/SKILL.md
      && lib.hasInfix "name: a2a-workflow" (builtins.readFile ../../nix/agents/skills/a2a-workflow/SKILL.md)
      && lib.hasInfix "Generated Reference Bundle" codexBindings.skills.a2a-workflow
    ))
    (assert' "GIVEN workflow bindings WHEN shared guide is rendered THEN provider usage hints are present" (
      lib.hasInfix "## workflow-cmd-mid-work-ljh" workflowIndex.sharedGuide
      && lib.hasInfix "Use from Claude: `/cmd-mid-work-ljh" workflowIndex.sharedGuide
      && lib.hasInfix "Use from Codex: invoke the `workflow-cmd-mid-work-ljh` skill" workflowIndex.sharedGuide
    ))
    (assert' "GIVEN Kiro bindings WHEN agents are rendered THEN role agents load shared resources" (
      builtins.length kiroAgentNames
      == 6
      && kiroRender.agents.independent-reviewer.includeMcpJson == false
      && builtins.elem "file://~/.kiro/tonys-nix/steering/**/*.md" kiroRender.agents.independent-reviewer.resources
      && builtins.elem "skill://~/.kiro/skills/**/SKILL.md" kiroRender.agents.independent-reviewer.resources
    ))
    (assert' "GIVEN Kiro bindings WHEN read-only agent is rendered THEN secret and write deny rules exist" (
      builtins.any (
        rule:
          rule.capability
          == "fs_read"
          && builtins.elem "**/secrets/**" rule.match
          && rule.effect == "deny"
      )
      kiroRender.agents.independent-reviewer.permissions.rules
      && builtins.any (
        rule:
          rule.capability
          == "fs_write"
          && builtins.elem "**" rule.match
          && rule.effect == "deny"
      )
      kiroRender.agents.independent-reviewer.permissions.rules
    ))
    (assert' "GIVEN Kiro bindings WHEN workflow skills and recipes are rendered THEN command workflows are discoverable" (
      builtins.elem "cmd-mid-work-ljh" kiroWorkflowNames
      && builtins.hasAttr "workflow-cmd-mid-work-ljh" kiroRender.workflowSkills
      && builtins.hasAttr "skl-pre-adr-ljh" kiroRender.skillBundleSkills
      && kiroRender.workflowRecipes.cmd-mid-work-ljh.inputs.task == "engineering request and repository context"
      && (builtins.head kiroRender.workflowRecipes.cmd-mid-work-ljh.steps).type == "step"
      && (builtins.head kiroRender.workflowRecipes.cmd-mid-work-ljh.steps).agent == "orchestrator"
      && lib.hasInfix "{{task}}" (builtins.head kiroRender.workflowRecipes.cmd-mid-work-ljh.steps).prompt
    ))
    (assert' "GIVEN Codex bindings WHEN roles are exported THEN each role points to a permission profile" (
      builtins.all (
        name: builtins.elem codexBindings.roles.${name}.permissionProfile profileNames
      )
      roleNames
    ))
    (assert' "GIVEN Codex bindings WHEN custom agents are rendered THEN standalone schema is used" (
      builtins.all (
        name:
          codexBindings.customAgents.${name}.name
          == name
          && codexBindings.customAgents.${name}.description == codexBindings.roles.${name}.description
          && builtins.isString codexBindings.customAgents.${name}.developer_instructions
          && codexBindings.customAgents.${name}.model == "gpt-6.1-sol"
          && !(codexBindings.customAgents.${name} ? config_file)
      )
      publicRoleNames
    ))
    (assert' "GIVEN Codex permission profiles WHEN reviewer is exported THEN reviewer is read-only" (
      codexBindings.permissionProfiles.agent-reviewer.filesystem.":workspace_roots"."."
      == "read"
      && codexBindings.permissionProfiles.agent-reviewer.filesystem.":minimal" == "read"
    ))
    (assert' "GIVEN Codex permission profiles WHEN implementer is exported THEN implementer can write workspace" (
      codexBindings.permissionProfiles.agent-implementer.filesystem.":workspace_roots"."." == "write"
    ))
    (assert' "GIVEN Codex permission profiles WHEN researcher is exported THEN limited network is enabled" (
      codexBindings.permissionProfiles.agent-researcher.network.enabled
      == true
      && codexBindings.permissionProfiles.agent-researcher.network.mode == "limited"
    ))
    (assert' "GIVEN Codex permission profiles WHEN secret access is denied THEN secret globs are denied" (
      codexBindings.permissionProfiles.agent-reviewer.filesystem.":workspace_roots"."**/secrets/**"
      == "deny"
      && codexBindings.permissionProfiles.agent-reviewer.filesystem.":workspace_roots"."**/.ssh/**"
      == "deny"
      && codexBindings.permissionProfiles.agent-reviewer.filesystem.":workspace_roots"."**/.gnupg/**"
      == "deny"
      && codexBindings.permissionProfiles.agent-reviewer.filesystem.":workspace_roots"."**/*private*key*"
      == "deny"
    ))
    (assert' "GIVEN Codex context WHEN reviewer mapping is rendered THEN skill and permission profile are shown" (
      lib.hasInfix
      "`independent-reviewer` -> `agent-independent-reviewer` / permission profile `agent-reviewer`"
      (codexBindings.mkContext "shared guide")
    ))
    (assert' "GIVEN Codex settings WHEN hooks and MCP are rendered THEN TOML shape data is exported" (
      sampleSettings.hooks
      == codexRender.providerHooks
      && sampleSettings.mcp_servers.test-server.enabled == true
      && sampleSettings.default_permissions == "default"
      && !(sampleSettings ? agents)
    ))
    (assert' "GIVEN Codex settings WHEN rendered THEN provider bridge data stays focused" sampleSettingsHasNoTui)
    (assert' "GIVEN Claude settings WHEN static hooks are loaded THEN native hook groups remain present" (
      claudeBaseSettings.hooks ? UserPromptSubmit
      && claudeBaseSettings.hooks ? PreToolUse
      && claudeBaseSettings.hooks ? PostToolUse
      && claudeBaseSettings.hooks ? Stop
    ))
    (assert' "GIVEN Claude settings WHEN AskUserQuestion waits for input THEN notification hook is configured" (
      builtins.any (
        entry:
          (entry.matcher or "")
          == "AskUserQuestion"
          && builtins.any (
            hook:
              hook.type
              == "command"
              && hook.command == "~/.claude/hooks/agent-notify.sh claude"
              && hook.timeout == 5
          )
          (entry.hooks or [])
      )
      (claudeBaseSettings.hooks.PreToolUse or [])
    ))
  ];
}
