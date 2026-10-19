{lib}: let
  commandDir = ./workflows/commands;
  skillDir = ./skills;
  contracts = import ./contract-validated.nix {inherit lib;};
  join = lib.concatStringsSep;

  # workflow 계약과 markdown prompt를 묶어 provider가 읽을 수 있는 인덱스로 만든다.
  # prompt 본문은 한 곳에 두고, provider surface에는 이름/권한/검증 gate만 투영한다.
  mkWorkflow = name: workflow: let
    file = workflow.source;
  in {
    inherit name file;
    inherit (workflow) description role;
    public = workflow.public or false;
    delegatedRoles = workflow.delegated_roles or [];
    body = builtins.readFile (commandDir + "/${file}");
    skillName = "workflow-${name}";
    mutatesFiles = workflow.mutates_files or false;
    needsNetwork = workflow.needs_network or false;
    needsMcp = workflow.needs_mcp or [];
    argumentHint = workflow.argument_hint or "task context";
    expectedOutputs = workflow.expected_outputs or [];
    specInputs = workflow.spec_inputs or [];
    requiredRules = workflow.required_rules or [];
    validationGates = workflow.validation_gates or [];
    writeOwner = workflow.write_owner or false;
    parallelSafe = workflow.parallel_safe or false;
    dependsOn = workflow.depends_on or [];
    handoffArtifacts = workflow.handoff_artifacts or [];
    claudeCommand = "/${lib.removeSuffix ".md" file}";
  };

  mkSkillBundle = name: skill:
    skill
    // {
      inherit name;
      body = builtins.readFile (skillDir + "/${skill.source}");
    };

  # source가 있고 public=true인 workflow만 기본 provider surface로 export한다.
  # 나머지 source workflow는 단계적 축소를 위한 legacy registry에 남긴다.
  allCommandWorkflows =
    lib.mapAttrs mkWorkflow
    (lib.filterAttrs (_: workflow: workflow.source != null) contracts.workflows);

  commandWorkflows = lib.filterAttrs (_: workflow: workflow.public or false) allCommandWorkflows;
  legacyWorkflows = lib.filterAttrs (_: workflow: !(workflow.public or false)) allCommandWorkflows;

  skillBundles = lib.mapAttrs mkSkillBundle contracts.skillBundles;

  # provider별 사용 문구는 안내용 산출물이다.
  # 실행 정책은 이 텍스트가 아니라 contract/workflow metadata와 테스트가 지킨다.
  sharedGuide = ''
    # Shared Agent Workflows

    These workflows are provider-neutral bindings for curated prompts that are
    exported to provider-native command surfaces.

    ${join "\n\n" (lib.mapAttrsToList (_: workflow: ''
        ## ${workflow.skillName}

        ${workflow.description}

        - Role: `${workflow.role}`
        - Use from Claude: `${workflow.claudeCommand} ${workflow.argumentHint}`
        - Use from Codex: invoke the `${workflow.skillName}` skill
        - Use from Gemini: ask for `${workflow.name}` and follow this workflow guide
      '')
      commandWorkflows)}
  '';
in {
  inherit commandWorkflows legacyWorkflows allCommandWorkflows skillBundles sharedGuide;
}
