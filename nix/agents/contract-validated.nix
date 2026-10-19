{lib}: let
  contracts = import ./contract.nix;

  names = builtins.attrNames;
  values = builtins.attrValues;
  has = builtins.hasAttr;
  join = lib.concatStringsSep;

  allowedSurfaceStatuses = [
    "supported"
    "generated"
    "provider_owned"
    "degraded"
    "unsupported"
    "standalone_only"
    "planned"
  ];
  allowedRuleSeverities = ["advisory" "important" "critical"];
  allowedRuleEnforcements = ["guidance" "review" "deterministic"];
  allowedTestCaseScopes = ["happy_path" "boundary" "invalid_input" "dependency_failure" "regression"];
  allowedTestLevels = [
    "unit"
    "integration_when_adapter_boundary_changes"
    "contract_when_provider_output_changes"
    "e2e_when_user_visible_flow_requires_it"
  ];

  roleNames = names contracts.roles;
  workflowNames = names contracts.workflows;
  skillBundleNames = names contracts.skillBundles;
  testStrategyValues = values contracts.testStrategies;
  testGates = lib.unique (lib.flatten (map (strategy: strategy.gates or []) testStrategyValues));
  governanceLayers = contracts.governance.layers;
  governanceLayerNames = names governanceLayers;
  governancePriorities = map (name: governanceLayers.${name}.priority) governanceLayerNames;
  invalidGovernanceLayers =
    lib.filter (name: !(governanceLayers.${name} ? priority) || !(governanceLayers.${name} ? can_weaken)) governanceLayerNames;
  governancePriorityValid =
    builtins.length (lib.unique governancePriorities)
    == builtins.length governancePriorities
    && governanceLayers.global-policy.priority == 100
    && governanceLayers.project-policy.priority < governanceLayers.global-policy.priority
    && lib.all (name: governanceLayers.${name}.can_weaken == false) governanceLayerNames;

  # owner가 참조하는 이름들이 target set에 실제 존재하는지 검사한다.
  # role/workflow/test strategy 검증이 같은 모양이라 여기서만 실패 label 형태를 맞춘다.
  invalidRefs = ownerNames: refsFor: targetSet:
    lib.flatten (
      map (
        ownerName:
          map (ref: "${ownerName}:${ref}") (
            lib.filter (ref: !(has ref targetSet)) (refsFor ownerName)
          )
      )
      ownerNames
    );

  # vocabulary 검증은 값 목록을 받아 allowed set 밖의 항목만 owner:value 형태로 돌려준다.
  # 새 enum이 필요하면 allowed 목록을 먼저 고치게 만들어 provider drift를 줄인다.
  invalidVocabulary = itemSet: valuesFor: allowed:
    lib.flatten (
      lib.mapAttrsToList
      (
        itemName: item:
          map (value: "${itemName}:${value}") (
            lib.filter (value: !(builtins.elem value allowed)) (valuesFor item)
          )
      )
      itemSet
    );

  # 역할 계약이 선언된 permission/rule만 참조하는지 확인한다.
  # provider export 전에 끊어진 role dependency를 조기에 실패시킨다.
  missingRolePermissions =
    lib.filter
    (name: !(has contracts.roles.${name}.default_permission contracts.permissions))
    roleNames;

  missingRoleRules =
    invalidRefs
    roleNames
    (name: contracts.roles.${name}.rule_scope or [])
    contracts.engineeringRules;

  # workflow 계약이 선언된 role/rule/test gate만 참조하는지 확인한다.
  # 스펙과 실행 workflow의 drift를 provider render 전에 막는다.
  missingWorkflowRoles =
    lib.filter
    (name: !(has contracts.workflows.${name}.role contracts.roles))
    workflowNames;

  missingWorkflowDelegatedRoles =
    invalidRefs
    workflowNames
    (name: contracts.workflows.${name}.delegated_roles or [])
    contracts.roles;

  missingSkillBundleMembers =
    invalidRefs
    skillBundleNames
    (name: contracts.skillBundles.${name}.members or [])
    contracts.workflows;

  missingWorkflowRules =
    invalidRefs
    workflowNames
    (name: contracts.workflows.${name}.required_rules or [])
    contracts.engineeringRules;

  missingWorkflowGates =
    invalidVocabulary
    contracts.workflows
    (workflow: workflow.validation_gates or [])
    testGates;

  # provider surface status는 공통 vocabulary 안에서만 허용한다.
  # 신규 provider가 임의 상태명을 추가하면 capability report가 흐려지기 때문이다.
  invalidProviderSurfaceStatuses = lib.flatten (
    lib.mapAttrsToList
    (
      providerName: provider:
        lib.flatten (
          lib.mapAttrsToList
          (
            targetName: target:
              map
              (surfaceName: "${providerName}.${targetName}.${surfaceName}=${target.surfaces.${surfaceName}}")
              (lib.filter
                (surfaceName: !(builtins.elem target.surfaces.${surfaceName} allowedSurfaceStatuses))
                (names (target.surfaces or {})))
          )
          (provider.targets or {})
        )
    )
    contracts.providers
  );

  # engineering rule은 severity/enforcement vocabulary를 검증한다.
  # 사람이 읽는 정책이라도 workflow gate와 연결되므로 값이 흔들리면 실패시킨다.
  invalidRuleSeverities =
    lib.mapAttrsToList
    (name: rule: "${name}:${rule.severity or "missing"}")
    (lib.filterAttrs (_: rule: !(builtins.elem (rule.severity or null) allowedRuleSeverities))
      contracts.engineeringRules);

  invalidRuleEnforcements =
    lib.mapAttrsToList
    (name: rule: "${name}:${rule.enforcement or "missing"}")
    (lib.filterAttrs (_: rule: !(builtins.elem (rule.enforcement or null) allowedRuleEnforcements))
      contracts.engineeringRules);

  # test strategy는 GWT 형식과 case/level vocabulary를 강제한다.
  # provider가 테스트 계획을 출력할 때 같은 기준을 공유하게 한다.
  invalidTestCaseScopes =
    invalidVocabulary
    contracts.testStrategies
    (strategy: strategy.case_scope or [])
    allowedTestCaseScopes;

  invalidTestLevels =
    invalidVocabulary
    contracts.testStrategies
    (strategy: strategy.levels or [])
    allowedTestLevels;

  invalidTestFormats =
    lib.mapAttrsToList
    (name: strategy: "${name}:${strategy.format.style or "missing"}")
    (lib.filterAttrs (_: strategy: (strategy.format.style or null) != "gwt") contracts.testStrategies);

  # 빈 목록은 성공, 하나라도 있으면 구체적인 label과 함께 즉시 실패한다.
  # Nix 평가 단계에서 깨뜨려 provider별 산출물이 조용히 생성되지 않게 한다.
  failIf = label: xs:
    if xs == []
    then true
    else builtins.throw "Invalid agent contract ${label}: ${join ", " xs}";

  assertions = {
    rolePermissions = failIf "role default_permission references" missingRolePermissions;
    roleRules = failIf "role rule_scope references" missingRoleRules;
    workflowRoles = failIf "workflow role references" missingWorkflowRoles;
    workflowDelegatedRoles = failIf "workflow delegated role references" missingWorkflowDelegatedRoles;
    skillBundleMembers = failIf "skill bundle workflow references" missingSkillBundleMembers;
    workflowRules = failIf "workflow required_rules references" missingWorkflowRules;
    workflowGates = failIf "workflow validation_gates references" missingWorkflowGates;
    providerSurfaceStatuses = failIf "provider surface statuses" invalidProviderSurfaceStatuses;
    ruleSeverities = failIf "engineering rule severity values" invalidRuleSeverities;
    ruleEnforcements = failIf "engineering rule enforcement values" invalidRuleEnforcements;
    testCaseScopes = failIf "test strategy case_scope values" invalidTestCaseScopes;
    testLevels = failIf "test strategy level values" invalidTestLevels;
    testFormats = failIf "test strategy format style values" invalidTestFormats;
    governanceLayers = failIf "governance layer fields" invalidGovernanceLayers;
    governancePrecedence =
      if governancePriorityValid
      then true
      else builtins.throw "Invalid agent contract governance precedence";
  };
  validatedContracts = builtins.deepSeq assertions contracts;
in
  # assertions를 deepSeq로 먼저 평가한 뒤 원본 계약과 검증 결과 메타데이터를 함께 반환한다.
  # 호출자는 validated 계약만 import해도 동일한 실패 조건을 공유한다.
  validatedContracts
  // {
    inherit allowedSurfaceStatuses assertions testGates;
  }
