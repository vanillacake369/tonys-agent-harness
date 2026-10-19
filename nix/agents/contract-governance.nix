{
  # 우선순위가 낮은 계층은 높은 계층의 보안·승인 정책을 완화할 수 없다.
  layers = {
    global-policy = {
      priority = 100;
      can_weaken = false;
      owner = "platform";
    };
    project-policy = {
      priority = 90;
      can_weaken = false;
      owner = "repository";
    };
    agent-role-permissions = {
      priority = 80;
      can_weaken = false;
      owner = "role";
    };
    skill-workflow-registry = {
      priority = 70;
      can_weaken = false;
      owner = "workflow";
    };
    mcp-registry = {
      priority = 60;
      can_weaken = false;
      owner = "integration";
    };
    runtime-sandbox-approval = {
      priority = 50;
      can_weaken = false;
      owner = "runtime";
    };
    verification-evidence-policy = {
      priority = 40;
      can_weaken = false;
      owner = "verification";
    };
  };

  immutablePolicies = [
    "deny-secret-access"
    "require-approval-for-destructive-actions"
    "require-approval-for-production-changes"
    "read-only-review-and-research"
    "single-writer-for-repository-mutations"
  ];

  # Review과 Judge는 근거를 제공하지만 권한을 발급하지 않는다.
  # 실제 허용 여부는 결정적 Policy Engine과 Execution Gate만 결정한다.
  authority = {
    policy_engine = "deterministic";
    execution_gate = "deterministic";
    llm_judge = "advisory";
    review_gate = "advisory";
  };

  sandboxApproval = {
    sandbox = "workspace-limited";
    approval = "fail-closed";
    unsupportedProvider = "block";
    secretAccess = "deny";
    reviewerWrite = false;
    productionChange = "human-approval";
  };

  instructionSource = "AGENTS.md";
  projectSpecRoot = "docs/agent";
  artifactPaths = {
    prd = "docs/agent/prd";
    adr = "docs/agent/adr";
    architecture = "docs/agent/architecture";
    testing = "docs/agent/testing";
    traceability = "docs/agent/traceability/requirements.tsv";
    telemetry = "docs/agent/telemetry/decisions.jsonl";
    memory = "docs/agent/memory";
    runbooks = "docs/agent/runbooks";
  };
  providerAdapters = ["claude" "codex" "gemini" "kiro"];
  evidenceRequired = [
    "commands"
    "exit_codes"
    "durations"
    "changed_files"
    "diff_summary"
    "requirement_results"
  ];
}
