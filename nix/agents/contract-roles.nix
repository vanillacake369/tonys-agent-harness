{
  # 역할 계약은 provider-neutral 행위 단위다.
  # provider별 agent/skill 이름은 adapter에서 바꾸되 책임과 권한 이름은 여기 값을 따른다.
  architect = {
    description = "Architecture planning and implementation roadmap role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Plan architecture, tradeoffs, affected boundaries, and implementation roadmap.";
    handoff_expectation = "Architecture artifact with decision, risks, and affected boundaries.";
    spec_responsibility = "design";
    rule_scope = ["flexible-solid" "minimize-abstraction" "max-two-directory-depth"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  cross-validator = {
    description = "Independent validation and second-opinion role.";
    default_permission = "agent-cross-validator";
    writes_workspace = false;
    needs_network = true;
    responsibility = "Validate assumptions, external compatibility, and design conclusions.";
    handoff_expectation = "Validation artifact with confirmed facts, risks, and unresolved unknowns.";
    spec_responsibility = "verification";
    rule_scope = ["single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  implementer = {
    public = true;
    description = "Code implementation role.";
    default_permission = "agent-implementer";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Implement the approved task with focused edits and local patterns.";
    handoff_expectation = "Change summary, verification, deviations, and residual risks.";
    spec_responsibility = "implementation";
    rule_scope = [
      "domain-value-object-owns-invariants"
      "early-return-success-fail"
      "max-two-control-depth"
      "explicit-error-handling"
      "line-width-120"
      "korean-core-comments"
      "minimize-abstraction"
      "dto-over-five-args"
      "meaningful-boolean-temps"
    ];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  refactorer = {
    description = "Behavior-preserving refactoring role.";
    default_permission = "agent-refactorer";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Improve structure while preserving behavior and test evidence.";
    handoff_expectation = "Refactor summary with behavior-preservation evidence.";
    spec_responsibility = "implementation";
    rule_scope = ["max-two-control-depth" "flexible-solid" "minimize-abstraction"];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  researcher = {
    description = "Research, documentation, and large-context analysis role.";
    default_permission = "agent-researcher";
    writes_workspace = false;
    needs_network = true;
    responsibility = "Gather local and official external evidence without repository writes.";
    handoff_expectation = "Research artifact separating facts, assumptions, constraints, and unknowns.";
    spec_responsibility = "requirements";
    rule_scope = [];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  reviewer = {
    description = "Code review role.";
    default_permission = "agent-reviewer";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Review correctness, maintainability, tests, risks, and rule adherence.";
    handoff_expectation = "Findings ordered by severity with evidence and recommended fixes.";
    spec_responsibility = "review";
    rule_scope = [
      "domain-value-object-owns-invariants"
      "early-return-success-fail"
      "max-two-control-depth"
      "explicit-error-handling"
      "minimize-abstraction"
      "single-writer-no-thread-conflict"
      "dto-over-five-args"
      "meaningful-boolean-temps"
    ];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  tester = {
    description = "Test design and implementation role.";
    default_permission = "agent-tester";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Design and implement tests that prove the requirement with suitable dependency handling.";
    handoff_expectation = "Test strategy, cases, commands, passed/failed checks, and untested areas.";
    spec_responsibility = "testing";
    rule_scope = [
      "domain-value-object-owns-invariants"
      "explicit-error-handling"
      "single-writer-no-thread-conflict"
    ];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  # 기획·설계·검증 역할은 기존 provider permission profile을 재사용한다.
  # 역할을 늘려도 provider별 권한 모델이 분기되지 않도록 책임과 권한을 분리한다.
  requirement-designer = {
    public = true;
    description = "Interactive PRD and acceptance-criteria design role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Turn ambiguous requests into a traceable PRD, domain terms, acceptance criteria, and open questions.";
    handoff_expectation = "PRD artifact with requirements, non-functional requirements, assumptions, and unresolved questions.";
    spec_responsibility = "requirements";
    rule_scope = ["minimize-abstraction" "single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  repository-archaeologist = {
    description = "Repository archaeology and hidden-contract discovery role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Map existing modules, callers, dependencies, conventions, generated outputs, and implicit contracts before design.";
    handoff_expectation = "Repository map with evidence, affected boundaries, compatibility constraints, and unknowns.";
    spec_responsibility = "requirements";
    rule_scope = ["single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  research-engineer = {
    public = true;
    description = "Technology, repository, tool, and official-source research role.";
    default_permission = "agent-researcher";
    writes_workspace = false;
    needs_network = true;
    responsibility = "Compare implementation candidates using local evidence, official documentation, compatibility, license, maintenance, and operational cost.";
    handoff_expectation = "Research artifact separating facts, sources, constraints, unknowns, and recommendation.";
    spec_responsibility = "requirements";
    rule_scope = [];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  strategist-a = {
    description = "Pragmatic independent strategy role focused on compatibility, cost, and operational stability.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Produce an independent strategy optimized for current-system fit, delivery cost, rollback, and operational simplicity.";
    handoff_expectation = "Independent strategy with assumptions, trade-offs, scoring, and recommendation.";
    spec_responsibility = "design";
    rule_scope = ["flexible-solid" "minimize-abstraction"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  strategist-b = {
    description = "Challenger independent strategy role focused on alternatives, scalability, and hidden failure modes.";
    default_permission = "agent-cross-validator";
    writes_workspace = false;
    needs_network = true;
    responsibility = "Challenge premises, explore alternative architectures, identify long-term costs, and test failure scenarios independently.";
    handoff_expectation = "Contrarian strategy with counterexamples, risks, evidence needs, and recommendation.";
    spec_responsibility = "verification";
    rule_scope = ["flexible-solid" "single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  decision-synthesizer = {
    public = true;
    description = "Strategy comparison and ADR synthesis role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Reconcile independent strategies, report agreement and conflict explicitly, and produce a reversible decision record.";
    handoff_expectation = "ADR with decision matrix, consensus, conflicts, unresolved evidence, and rollback implications.";
    spec_responsibility = "design";
    rule_scope = ["flexible-solid" "minimize-abstraction"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  complexity-analyst = {
    description = "Complexity, dependency, risk, and work-breakdown analysis role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Estimate uncertainty, coupling, blast radius, sequencing, parallel safety, and route selection.";
    handoff_expectation = "Complexity classification with dependency graph, risks, execution route, and escalation conditions.";
    spec_responsibility = "design";
    rule_scope = ["single-writer-no-thread-conflict" "minimize-abstraction"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  code-designer = {
    description = "Code structure, interfaces, error handling, and comment-style design role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Define code boundaries, abstractions, language level, interfaces, invariants, errors, and documentation conventions from the PRD.";
    handoff_expectation = "Code design specification mapped to requirements and test seams.";
    spec_responsibility = "design";
    rule_scope = ["flexible-solid" "minimize-abstraction" "explicit-error-handling" "max-two-directory-depth"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  infra-designer = {
    description = "Infrastructure, SLA/SLO, security, resilience, and operations design role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Specify deployment topology, SLI/SLO, capacity, observability, backup, disaster recovery, security, and cost constraints.";
    handoff_expectation = "Infrastructure design with operational objectives, failure budget, rollback, and runbook requirements.";
    spec_responsibility = "design";
    rule_scope = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  test-designer = {
    description = "PRD-to-test-case and verification strategy design role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Derive test cases, boundaries, failures, concurrency scenarios, fixtures, and evidence gates from requirements and component responsibilities.";
    handoff_expectation = "Test specification mapped to requirement IDs, risks, levels, and verification commands.";
    spec_responsibility = "testing";
    rule_scope = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };

  infra-engineer = {
    description = "Infrastructure implementation and operational verification role.";
    default_permission = "agent-implementer";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Implement approved infrastructure design, secure configuration, observability, deployment, rollback, and evidence.";
    handoff_expectation = "Infrastructure change summary with plan/apply or dry-run evidence and rollback status.";
    spec_responsibility = "implementation";
    rule_scope = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  security-reviewer = {
    description = "Security and supply-chain review role.";
    default_permission = "agent-cross-validator";
    writes_workspace = false;
    needs_network = true;
    responsibility = "Review authentication, authorization, secrets, data exposure, dependencies, supply chain, and abuse cases with evidence.";
    handoff_expectation = "Security findings ordered by severity with evidence, exploitability, mitigation, and residual risk.";
    spec_responsibility = "review";
    rule_scope = ["explicit-error-handling" "single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  independent-reviewer = {
    public = true;
    description = "Independent PRD, implementation, test, and evidence review role.";
    default_permission = "agent-reviewer";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Audit the result independently against requirements, design, tests, scope, and residual risks without sharing implementation assumptions.";
    handoff_expectation = "Blocking, important, and minor findings with evidence and recommended fixes.";
    spec_responsibility = "review";
    rule_scope = ["single-writer-no-thread-conflict" "explicit-error-handling" "minimize-abstraction"];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  performance-engineer = {
    description = "Measurement-first performance analysis and improvement role.";
    default_permission = "agent-refactorer";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Measure bottlenecks, form falsifiable hypotheses, apply the smallest improvement, and compare before/after evidence.";
    handoff_expectation = "Performance report with baseline, bottleneck evidence, change, benchmark, and remaining trade-offs.";
    spec_responsibility = "implementation";
    rule_scope = ["minimize-abstraction" "explicit-error-handling" "single-writer-no-thread-conflict"];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  documentation-engineer = {
    description = "Documentation, ADR, runbook, and handoff automation role.";
    default_permission = "agent-implementer";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Create durable project documentation in the requested style without duplicating source-of-truth contracts.";
    handoff_expectation = "Documentation or handoff artifact with links to PRD, ADR, changes, verification, and remaining risks.";
    spec_responsibility = "documentation";
    rule_scope = ["single-writer-no-thread-conflict"];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  skill-creator = {
    description = "Project-specific skill and AX automation design role.";
    default_permission = "agent-implementer";
    writes_workspace = true;
    needs_network = false;
    responsibility = "Identify repeated work, create narrowly triggered skills, and include references, scripts, validation, and rollback-safe defaults.";
    handoff_expectation = "Skill proposal or implementation with trigger, procedure, resources, validation, and adoption guidance.";
    spec_responsibility = "implementation";
    rule_scope = ["minimize-abstraction" "single-writer-no-thread-conflict"];
    may_write = true;
    may_delegate_readonly = true;
    conflict_policy = "single-writer";
  };

  skill-evaluator = {
    description = "Independent skill quality and ROI evaluation role.";
    default_permission = "agent-reviewer";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Evaluate skill trigger precision, context cost, completion quality, failure modes, adoption, and measurable benefit.";
    handoff_expectation = "Skill evaluation with pass/fail criteria, observed defects, ROI signals, and recommendation.";
    spec_responsibility = "review";
    rule_scope = ["minimize-abstraction" "single-writer-no-thread-conflict"];
    may_write = false;
    may_delegate_readonly = false;
    conflict_policy = "readonly";
  };

  orchestrator = {
    public = true;
    description = "Engineering workflow routing, gate, and responsibility coordination role.";
    default_permission = "agent-architect";
    writes_workspace = false;
    needs_network = false;
    responsibility = "Classify work, select the smallest safe route, assign roles, enforce gates, and preserve single-writer ownership.";
    handoff_expectation = "Classification, selected route, gate results, delegation plan, and compact handoff.";
    spec_responsibility = "workflow";
    rule_scope = ["single-writer-no-thread-conflict" "minimize-abstraction"];
    may_write = false;
    may_delegate_readonly = true;
    conflict_policy = "readonly";
  };
}
