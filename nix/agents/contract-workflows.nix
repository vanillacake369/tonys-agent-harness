{
  architectural-planning = {
    description = "Plan substantial changes through architecture discovery and tradeoff analysis.";
    source = null;
    role = "architect";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "architecture context";
    expected_outputs = ["Architecture"];
    spec_inputs = ["requirements" "current_architecture"];
    required_rules = ["flexible-solid" "minimize-abstraction" "max-two-directory-depth"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = [];
    handoff_artifacts = ["architecture"];
  };

  code-implementation = {
    description = "Implement focused code changes after learning local patterns.";
    source = null;
    role = "implementer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "implementation target";
    expected_outputs = ["Changes" "Verification"];
    spec_inputs = ["requirements" "design" "tasks"];
    required_rules = [
      "early-return-success-fail"
      "max-two-control-depth"
      "explicit-error-handling"
      "minimize-abstraction"
      "dto-over-five-args"
    ];
    validation_gates = [
      "test_case_scope_selected"
      "dependency_strategy_selected"
      "failing_test_written_or_exemption_recorded"
      "minimal_implementation"
      "refactor_after_green"
    ];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["change_summary" "verification"];
  };

  test-development = {
    description = "Create tests that match existing project conventions.";
    source = null;
    role = "tester";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "test target and acceptance criteria";
    expected_outputs = ["Test Strategy" "Tests" "Verification"];
    spec_inputs = ["requirements" "acceptance_criteria"];
    required_rules = ["domain-value-object-owns-invariants" "explicit-error-handling"];
    validation_gates = [
      "test_case_scope_selected"
      "dependency_strategy_selected"
      "failing_test_written_or_exemption_recorded"
      "focused_verification"
    ];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["test_strategy" "verification"];
  };

  commit = {
    description = "PR 리뷰가 쉽도록 변경사항을 파일 변화 단위로 분석하고 커밋한다";
    source = "commit.md";
    role = "implementer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "commit scope or constraints";
    expected_outputs = ["Commit"];
    spec_inputs = ["change_summary" "verification"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["commit_hash"];
  };

  create-pull-request = {
    description = "현재 브랜치의 변경사항을 분석하여 PR을 생성한다";
    source = "create-pull-request.md";
    role = "implementer";
    mutates_files = true;
    needs_network = true;
    needs_mcp = [];
    argument_hint = "PR context, reviewers, or discussion points";
    expected_outputs = ["Pull Request"];
    spec_inputs = ["change_summary" "verification" "discussion"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["pull_request_url"];
  };

  code-enhance = {
    description = "코드 품질, 성능, 보안을 분석하고 개선한다";
    source = "code-enhance.md";
    role = "implementer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "target files, modules, or quality concern";
    expected_outputs = ["Quality Analysis" "Changes" "Verification"];
    spec_inputs = ["target_scope" "quality_concern"];
    required_rules = ["minimize-abstraction" "explicit-error-handling" "max-two-control-depth"];
    validation_gates = [
      "test_case_scope_selected"
      "dependency_strategy_selected"
      "focused_verification"
    ];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["change_summary" "verification"];
  };

  debug-system = {
    description = "Orchestrate skills to systematically debug issues with root cause analysis";
    source = "debug-system.md";
    role = "tester";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "bug report, failure log, or reproduction steps";
    expected_outputs = ["Root Cause" "Fix" "Verification"];
    spec_inputs = ["bug_report" "reproduction"];
    required_rules = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    validation_gates = ["test_case_scope_selected" "focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["root_cause" "verification"];
  };

  evidence-debug = {
    description = ''
      Evidence-first debugging workflow for repeated hook/runtime failures,
      policy or guardrail regressions, stale state/config problems, and
      explicit preferred review loops
    '';
    source = "evidence-debug.md";
    role = "tester";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "hook failure, stale state, guardrail regression, or repeated debug failure";
    expected_outputs = ["Evidence" "Root Cause" "Fix" "Verification"];
    spec_inputs = ["failure_log" "reproduction"];
    required_rules = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    validation_gates = ["test_case_scope_selected" "focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["evidence" "root_cause" "verification"];
  };

  scaffold = {
    description = "Scaffold a new project or feature from a concise implementation target";
    source = "scaffold.md";
    role = "implementer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "project or feature to scaffold";
    expected_outputs = ["Scaffold" "Verification"];
    spec_inputs = ["target_shape"];
    required_rules = ["max-two-directory-depth" "minimize-abstraction"];
    validation_gates = ["test_case_scope_selected" "focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["scaffold_summary" "verification"];
  };

  blog-korean = {
    description = "한국어 기술 블로그 초안을 작성한다";
    source = "blog-korean.md";
    role = "implementer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = ["context7"];
    argument_hint = "topic, source material, and target audience";
    expected_outputs = ["Draft"];
    spec_inputs = ["topic" "source_material"];
    required_rules = [];
    validation_gates = [];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["draft_path"];
  };

  blog-refine = {
    description = "한국어 기술 블로그 초안을 다듬는다";
    source = "blog-refine.md";
    role = "implementer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = ["context7"];
    argument_hint = "draft path or refinement goal";
    expected_outputs = ["Refined Draft"];
    spec_inputs = ["draft_path" "refinement_goal"];
    required_rules = [];
    validation_gates = [];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["draft_path"];
  };

  test-doc-korean = {
    description = "테스트 문서를 한국어로 작성한다";
    source = "test-doc-korean.md";
    role = "tester";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "test target, source files, or documentation scope";
    expected_outputs = ["Test Documentation"];
    spec_inputs = ["test_target" "acceptance_criteria"];
    required_rules = ["domain-value-object-owns-invariants" "explicit-error-handling"];
    validation_gates = ["test_case_scope_selected" "dependency_strategy_selected"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["test_doc_path"];
  };

  todo-task-management = {
    description = "외부 todo MCP 서버를 통해 task를 조회하고 안전하게 관리한다";
    source = "todo-task-management.md";
    role = "implementer";
    mutates_files = false;
    needs_network = true;
    needs_mcp = ["ticktick"];
    argument_hint = "todo query, task change request, or planning context";
    expected_outputs = ["Todo Update"];
    spec_inputs = ["todo_request"];
    required_rules = ["explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["todo_summary"];
  };

  clarify-requirements = {
    description = "대화형 요구사항 인터뷰로 PRD와 수용 기준을 구체화한다";
    source = "clarify-requirements.md";
    role = "requirement-designer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "ambiguous request or product idea";
    expected_outputs = ["PRD" "Acceptance Criteria" "Open Questions"];
    spec_inputs = ["user_request" "current_context"];
    required_rules = ["minimize-abstraction"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["prd" "open_questions"];
  };

  repository-archaeology = {
    description = "기존 저장소의 구조, 의존성, 호출자와 암묵적 계약을 조사한다";
    source = "repository-archaeology.md";
    role = "repository-archaeologist";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "target feature, module, or failure";
    expected_outputs = ["Repository Map" "Constraints" "Unknowns"];
    spec_inputs = ["target_scope" "prd"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = [];
    handoff_artifacts = ["repository_map" "constraints"];
  };

  technology-research = {
    public = false;
    description = "공식 문서와 로컬 증거를 기반으로 기술·repo·tool 후보를 비교한다";
    source = "technology-research.md";
    role = "research-engineer";
    delegated_roles = ["repository-archaeologist" "researcher"];
    mutates_files = false;
    needs_network = true;
    needs_mcp = [];
    argument_hint = "PRD and candidate technology question";
    expected_outputs = ["Research" "Comparison" "Recommendation"];
    spec_inputs = ["prd" "repository_map"];
    required_rules = [];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["clarify-requirements" "repository-archaeology"];
    handoff_artifacts = ["research"];
  };

  strategy-review = {
    public = false;
    description = "독립 전략 A/B를 교차검증하고 합의·충돌·미검증 전제를 ADR로 정리한다";
    source = "strategy-review.md";
    role = "decision-synthesizer";
    delegated_roles = ["strategist-a" "strategist-b" "cross-validator" "architect"];
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD, research, and competing strategies";
    expected_outputs = ["Decision Matrix" "Consensus" "Conflicts" "Unverified Assumptions" "Validation Plan" "ADR"];
    spec_inputs = ["prd" "research" "strategy_a" "strategy_b"];
    required_rules = ["flexible-solid" "minimize-abstraction"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = false;
    depends_on = ["technology-research"];
    handoff_artifacts = ["adr" "decision"];
  };

  complexity-analysis = {
    description = "작업 복잡도, 의존성, 위험, 병렬성 및 실행 경로를 분류한다";
    source = "complexity-analysis.md";
    role = "complexity-analyst";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD, repository map, and proposed design";
    expected_outputs = ["Classification" "Dependency Graph" "Route"];
    spec_inputs = ["prd" "repository_map" "design"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = [];
    handoff_artifacts = ["classification" "risk_register"];
  };

  code-design = {
    description = "PRD를 코드 구조, 인터페이스, 오류 처리와 주석 규칙으로 구체화한다";
    source = "code-design.md";
    role = "code-designer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD and selected strategy";
    expected_outputs = ["Code Design" "Interfaces" "Traceability"];
    spec_inputs = ["prd" "decision" "repository_map"];
    required_rules = ["flexible-solid" "minimize-abstraction" "explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["strategy-review"];
    handoff_artifacts = ["code_design"];
  };

  infra-design = {
    description = "SLA/SLO, 보안, 관측성, 용량, 복구를 포함한 인프라 설계를 만든다";
    source = "infra-design.md";
    role = "infra-designer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD and deployment context";
    expected_outputs = ["Infrastructure Design" "SLO" "Runbook Requirements"];
    spec_inputs = ["prd" "decision" "repository_map"];
    required_rules = ["explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["strategy-review"];
    handoff_artifacts = ["infra_design"];
  };

  test-design = {
    description = "요구사항과 컴포넌트 책임에서 테스트 케이스와 증거 게이트를 도출한다";
    source = "test-design.md";
    role = "test-designer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD, acceptance criteria, and design";
    expected_outputs = ["Test Specification" "Cases" "Evidence Gates"];
    spec_inputs = ["prd" "acceptance_criteria" "design"];
    required_rules = ["explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["code-design" "infra-design"];
    handoff_artifacts = ["test_spec"];
  };

  tdd-implementation = {
    public = false;
    description = "설계 스펙에 따라 테스트 우선으로 제품을 구현하고 검증한다";
    source = "tdd-implementation.md";
    role = "implementer";
    delegated_roles = ["tester" "refactorer"];
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "approved design, test specification, and task";
    expected_outputs = ["Changes" "Tests" "Verification"];
    spec_inputs = ["prd" "design" "test_spec"];
    required_rules = ["early-return-success-fail" "explicit-error-handling" "single-writer-no-thread-conflict"];
    validation_gates = ["test_case_scope_selected" "dependency_strategy_selected" "failing_test_written_or_exemption_recorded" "minimal_implementation" "refactor_after_green" "focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = ["test-design"];
    handoff_artifacts = ["change_summary" "verification"];
  };

  infrastructure-implementation = {
    description = "승인된 인프라 설계를 IaC와 운영 검증으로 구현한다";
    source = "infrastructure-implementation.md";
    role = "infra-engineer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "infrastructure design and target environment";
    expected_outputs = ["Infrastructure Changes" "Dry Run" "Rollback"];
    spec_inputs = ["infra_design" "prd"];
    required_rules = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = ["infra-design"];
    handoff_artifacts = ["infra_change_summary" "verification"];
  };

  refactoring = {
    description = "동작을 보존하면서 구조를 개선하고 회귀 증거를 남긴다";
    source = "refactoring.md";
    role = "refactorer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "target code and behavior-preservation constraints";
    expected_outputs = ["Refactor" "Regression Evidence"];
    spec_inputs = ["existing_behavior" "test_evidence"];
    required_rules = ["max-two-control-depth" "minimize-abstraction" "single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification" "refactor_after_green"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["refactor_summary" "verification"];
  };

  performance-optimization = {
    description = "측정으로 병목을 증명하고 전후 성능을 비교해 개선한다";
    source = "performance-optimization.md";
    role = "performance-engineer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "performance concern, baseline, or benchmark target";
    expected_outputs = ["Baseline" "Optimization" "Comparison"];
    spec_inputs = ["target_scope" "performance_goal"];
    required_rules = ["minimize-abstraction" "single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["performance_report" "verification"];
  };

  security-review = {
    description = "인증·인가, 시크릿, 공급망과 데이터 노출을 독립 검토한다";
    source = "security-review.md";
    role = "security-reviewer";
    mutates_files = false;
    needs_network = true;
    needs_mcp = [];
    argument_hint = "change scope or security-sensitive design";
    expected_outputs = ["Security Findings" "Risk Decision"];
    spec_inputs = ["prd" "design" "changes"];
    required_rules = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["tdd-implementation"];
    handoff_artifacts = ["security_review"];
  };

  independent-review = {
    public = false;
    description = "PRD·설계·구현·테스트 증거를 독립적으로 대조 검토한다";
    source = "independent-review.md";
    role = "independent-reviewer";
    delegated_roles = ["reviewer" "security-reviewer" "cross-validator" "documentation-engineer"];
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD, diff, test evidence, and review scope";
    expected_outputs = ["Review Findings" "Verdict"];
    spec_inputs = ["prd" "changes" "verification"];
    required_rules = ["single-writer-no-thread-conflict" "explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["tdd-implementation"];
    handoff_artifacts = ["review"];
  };

  documentation-handoff = {
    description = "ADR, 인수인계, 변경 요약과 운영 문서를 요청 형식으로 작성한다";
    source = "documentation-handoff.md";
    role = "documentation-engineer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "completed work and requested documentation format";
    expected_outputs = ["Documentation" "Handoff"];
    spec_inputs = ["changes" "verification" "remaining_risks"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = [];
    write_owner = true;
    parallel_safe = false;
    depends_on = ["independent-review"];
    handoff_artifacts = ["documentation_path" "handoff"];
  };

  skill-creation = {
    description = "반복 작업을 프로젝트 맞춤 Codex skill로 설계하고 구현한다";
    source = "skill-creation.md";
    role = "skill-creator";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "repeated task and desired skill behavior";
    expected_outputs = ["Skill" "Validation"];
    spec_inputs = ["repeated_task" "project_context" "failure_history"];
    required_rules = ["minimize-abstraction" "single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["skill_path" "validation"];
  };

  skill-evaluation = {
    description = "Skill의 트리거 정확도, 컨텍스트 비용과 실제 ROI를 평가한다";
    source = "skill-evaluation.md";
    role = "skill-evaluator";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "skill path and observed usage or failure examples";
    expected_outputs = ["Evaluation" "Recommendation"];
    spec_inputs = ["skill" "failure_history" "verification"];
    required_rules = ["minimize-abstraction"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["skill-creation"];
    handoff_artifacts = ["skill_evaluation"];
  };

  grill-with-docs = {
    description = "도메인 용어와 설계 결정을 한 번에 하나씩 인터뷰하고 문서화한다";
    source = "grill-with-docs.md";
    role = "requirement-designer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "plan, domain terms, or design uncertainty";
    expected_outputs = ["Glossary" "Decisions" "Open Questions"];
    spec_inputs = ["conversation" "repository_context"];
    required_rules = ["minimize-abstraction"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["glossary" "decisions"];
  };

  to-prd = {
    public = false;
    description = "확정된 대화와 저장소 맥락을 추적 가능한 PRD로 합성한다";
    source = "to-prd.md";
    role = "requirement-designer";
    delegated_roles = ["repository-archaeologist" "test-designer" "infra-designer" "code-designer"];
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "feature context or source conversation";
    expected_outputs = ["PRD"];
    spec_inputs = ["conversation" "repository_context" "decisions"];
    required_rules = ["minimize-abstraction" "single-writer-no-thread-conflict"];
    validation_gates = [];
    write_owner = true;
    parallel_safe = false;
    depends_on = ["clarify-requirements"];
    handoff_artifacts = ["prd_path"];
  };

  to-issues = {
    description = "PRD를 독립적으로 검증 가능한 vertical-slice 이슈로 분해한다";
    source = "to-issues.md";
    role = "complexity-analyst";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "PRD path and desired issue granularity";
    expected_outputs = ["Issue Breakdown" "Dependencies"];
    spec_inputs = ["prd" "acceptance_criteria" "architecture"];
    required_rules = ["single-writer-no-thread-conflict" "minimize-abstraction"];
    validation_gates = [];
    write_owner = true;
    parallel_safe = false;
    depends_on = ["to-prd"];
    handoff_artifacts = ["issue_paths"];
  };

  code-safety-guardrail = {
    description = "코드 변경 전후 영향 범위와 안전 가드레일을 점검한다";
    source = "code-safety-guardrail.md";
    role = "independent-reviewer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "change request and target scope";
    expected_outputs = ["Impact Analysis" "Guardrail Gate"];
    spec_inputs = ["request" "target_scope" "existing_tests"];
    required_rules = ["single-writer-no-thread-conflict" "explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["repository-archaeology"];
    handoff_artifacts = ["safety_review"];
  };

  code-review = {
    description = "완료된 변경을 adversarial 관점에서 독립 리뷰한다";
    source = "code-review.md";
    role = "independent-reviewer";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "diff and verification evidence";
    expected_outputs = ["Verdict" "Findings" "Scenarios"];
    spec_inputs = ["changes" "tests" "requirements"];
    required_rules = ["single-writer-no-thread-conflict" "explicit-error-handling"];
    validation_gates = [];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["tdd-implementation"];
    handoff_artifacts = ["review"];
  };

  handoff = {
    description = "다음 세션이 재현 가능하도록 현재 작업을 압축해 인수인계한다";
    source = "handoff.md";
    role = "documentation-engineer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "current work and next-session purpose";
    expected_outputs = ["Handoff"];
    spec_inputs = ["changes" "verification" "remaining_risks"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = [];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["handoff_path"];
  };

  code-comments = {
    description = "변경 코드의 의도와 불변식을 프로젝트 주석 스타일로 정리한다";
    source = "code-comments.md";
    role = "documentation-engineer";
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "changed files and requested comment style";
    expected_outputs = ["Comment Changes" "Verification"];
    spec_inputs = ["changes" "code_design" "comment_style"];
    required_rules = ["korean-core-comments" "single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["comment_summary" "verification"];
  };

  engineering-orchestrator = {
    public = false;
    description = "작업 위험도와 복잡도에 따라 최소 안전 실행 경로와 역할을 선택한다";
    source = "engineering-orchestrator.md";
    role = "orchestrator";
    delegated_roles = ["complexity-analyst" "decision-synthesizer" "independent-reviewer"];
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "user request and repository context";
    expected_outputs = ["Classification" "Selected Route" "Delegation Plan" "Gates"];
    spec_inputs = ["user_request" "repository_context" "existing_evidence"];
    required_rules = ["single-writer-no-thread-conflict" "minimize-abstraction"];
    validation_gates = ["prd_traceability_complete" "evidence_recorded"];
    write_owner = false;
    parallel_safe = false;
    depends_on = ["complexity-analysis"];
    handoff_artifacts = ["classification" "route" "gate_results"];
  };

  project-bootstrap = {
    description = "프로젝트 특성을 조사해 맞춤형 정책, provider 설정, Skill, MCP 권한을 제안한다";
    source = "project-bootstrap.md";
    role = "repository-archaeologist";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "repository path and bootstrap goal";
    expected_outputs = ["Project Profile" "Config Proposal" "Impact Analysis"];
    spec_inputs = ["repository" "existing_configuration" "security_requirements"];
    required_rules = ["single-writer-no-thread-conflict" "minimize-abstraction"];
    validation_gates = ["evidence_recorded"];
    write_owner = false;
    parallel_safe = true;
    depends_on = ["repository-archaeology"];
    handoff_artifacts = ["project_profile" "configuration_proposal" "impact_analysis"];
  };

  phase-execution-plan = {
    description = "Decision Engine 결과를 승인·단일 writer·검증 gate가 포함된 Phase 실행 계획으로 변환한다";
    source = "phase-execution-plan.md";
    role = "orchestrator";
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "phase, decision evidence, request digest, and approval";
    expected_outputs = ["Execution Plan" "Human Gate Result" "Next Action"];
    spec_inputs = ["decision" "approval" "traceability" "evidence_policy"];
    required_rules = ["single-writer-no-thread-conflict" "explicit-error-handling"];
    validation_gates = ["prd_traceability_complete" "evidence_recorded"];
    write_owner = false;
    parallel_safe = false;
    depends_on = ["engineering-orchestrator"];
    handoff_artifacts = ["execution_plan" "human_gate_result"];
  };

  cmd-vpp-work-ljh = {
    public = true;
    description = "Route VPP engineering work through risk, phase, skill, and approval policy";
    source = "cmd-vpp-work-ljh.md";
    role = "orchestrator";
    delegated_roles = ["complexity-analyst" "requirement-designer" "research-engineer" "decision-synthesizer" "implementer" "independent-reviewer"];
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "engineering request and repository context";
    expected_outputs = ["Classification" "Selected Skills" "Gates" "Evidence"];
    spec_inputs = ["user_request" "repository_context" "existing_evidence"];
    required_rules = ["single-writer-no-thread-conflict" "minimize-abstraction"];
    validation_gates = ["prd_traceability_complete" "evidence_recorded"];
    write_owner = false;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["classification" "skill_plan" "gate_results"];
  };

  cmd-vpp-comment-ljh = {
    public = true;
    description = "Generate scoped code comments and change explanations using the project comment style";
    source = "cmd-vpp-comment-ljh.md";
    role = "documentation-engineer";
    delegated_roles = ["independent-reviewer"];
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "changed files and comment style";
    expected_outputs = ["Comment Changes" "Verification" "Evidence"];
    spec_inputs = ["changes" "code_design" "comment_style"];
    required_rules = ["korean-core-comments" "single-writer-no-thread-conflict"];
    validation_gates = ["focused_verification" "evidence_recorded"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["comment_summary" "verification"];
  };

  cmd-vpp-handoff-ljh = {
    public = true;
    description = "Create a durable project handoff linked to requirements, changes, verification, and risks";
    source = "cmd-vpp-handoff-ljh.md";
    role = "documentation-engineer";
    delegated_roles = ["independent-reviewer"];
    mutates_files = true;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "current work and next-session purpose";
    expected_outputs = ["Handoff" "Evidence" "Next Actions"];
    spec_inputs = ["changes" "verification" "remaining_risks"];
    required_rules = ["single-writer-no-thread-conflict"];
    validation_gates = ["evidence_recorded"];
    write_owner = true;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["handoff_path"];
  };

  cmd-vpp-ship-ljh = {
    public = true;
    description = "Prepare an explicitly approved release or external operation without executing it";
    source = "cmd-vpp-ship-ljh.md";
    role = "orchestrator";
    delegated_roles = ["complexity-analyst" "independent-reviewer" "documentation-engineer"];
    mutates_files = false;
    needs_network = false;
    needs_mcp = [];
    argument_hint = "release, deployment, migration, or external operation";
    expected_outputs = ["Operation Plan" "Approval Scope" "Rollback" "Evidence"];
    spec_inputs = ["changes" "environment" "approval" "rollback"];
    required_rules = ["single-writer-no-thread-conflict" "explicit-error-handling"];
    validation_gates = ["prd_traceability_complete" "evidence_recorded"];
    write_owner = false;
    parallel_safe = false;
    depends_on = [];
    handoff_artifacts = ["operation_plan" "approval_request" "rollback_plan"];
  };
}
