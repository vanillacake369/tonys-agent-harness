{
  "skl-pre-prd-ljh" = {
    description = "Requirements clarification, domain language, acceptance criteria, and PRD synthesis.";
    source = "skl-pre-prd-ljh/SKILL.md";
    owner = "requirement-designer";
    members = ["clarify-requirements" "grill-with-docs" "to-prd" "test-design" "infra-design" "code-design"];
  };

  "skl-pre-research-ljh" = {
    description = "Repository archaeology, technology research, and project bootstrap using local and official evidence.";
    source = "skl-pre-research-ljh/SKILL.md";
    owner = "research-engineer";
    members = ["repository-archaeology" "technology-research" "project-bootstrap"];
  };

  "skl-pre-adr-ljh" = {
    description = "Independent strategy comparison, conflict classification, validation planning, and ADR synthesis.";
    source = "skl-pre-adr-ljh/SKILL.md";
    owner = "decision-synthesizer";
    members = ["strategy-review" "architectural-planning" "grill-with-docs"];
  };

  "skl-mid-impl-ljh" = {
    description = "TDD implementation, code and infrastructure changes, refactoring, and evidence-producing verification.";
    source = "skl-mid-impl-ljh/SKILL.md";
    owner = "implementer";
    members = ["code-implementation" "test-development" "tdd-implementation" "infrastructure-implementation" "refactoring" "debug-system" "code-safety-guardrail"];
  };

  "skl-mid-review-ljh" = {
    description = "Read-only security, code, scope, traceability, and independent review of implementation evidence.";
    source = "skl-mid-review-ljh/SKILL.md";
    owner = "independent-reviewer";
    members = ["independent-review" "security-review" "code-review" "code-safety-guardrail" "evidence-debug"];
  };

  "skl-mid-perf-ljh" = {
    description = "Measurement-first performance diagnosis, optimization, and before/after comparison.";
    source = "skl-mid-perf-ljh/SKILL.md";
    owner = "performance-engineer";
    members = ["performance-optimization"];
  };

  "skl-post-ship-ljh" = {
    description = "Release preparation, approval scope, rollback planning, and post-change observation.";
    source = "skl-post-ship-ljh/SKILL.md";
    owner = "orchestrator";
    members = ["phase-execution-plan" "commit" "create-pull-request"];
  };

  "skl-post-docs-ljh" = {
    description = "Documentation, handoff, issue, runbook, and change-summary artifacts without policy duplication.";
    source = "skl-post-docs-ljh/SKILL.md";
    owner = "documentation-engineer";
    members = ["documentation-handoff" "handoff" "to-issues" "code-comments"];
  };

  "skl-phase-route-ljh" = {
    description = "Risk, uncertainty, blast-radius, and reversibility based route selection and workflow composition.";
    source = "skl-phase-route-ljh/SKILL.md";
    owner = "orchestrator";
    members = ["engineering-orchestrator" "complexity-analysis"];
  };

  "skl-phase-gate-ljh" = {
    description = "Deterministic policy, human approval, fail-closed execution, and single-writer enforcement.";
    source = "skl-phase-gate-ljh/SKILL.md";
    owner = "orchestrator";
    members = ["phase-execution-plan" "code-safety-guardrail"];
  };

  "skl-phase-trace-ljh" = {
    description = "Requirement traceability, evidence, telemetry, retry budget, and Git lifecycle completion checks.";
    source = "skl-phase-trace-ljh/SKILL.md";
    owner = "independent-reviewer";
    members = ["evidence-debug" "phase-execution-plan" "documentation-handoff"];
  };
}
