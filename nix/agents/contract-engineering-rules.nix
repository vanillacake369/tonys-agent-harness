{
  domain-value-object-owns-invariants = {
    intent = "Domain and value objects own construction, validation, invariants, and meaningful behavior.";
    applies_to = ["domain" "value-object" "dto-boundary" "review" "test"];
    severity = "important";
    enforcement = "review";
    exceptions = ["generated-code" "framework-owned-model"];
    workflow_gates = ["design_invariant_owner_selected" "test_case_scope_selected"];
  };

  early-return-success-fail = {
    intent = "Prefer early success and early fail paths so the happy path stays visible.";
    applies_to = ["implementation" "review"];
    severity = "important";
    enforcement = "review";
    exceptions = ["transaction-cleanup" "language-idiom"];
    workflow_gates = ["minimal_implementation"];
  };

  max-two-control-depth = {
    intent = "Avoid more than two nested control-flow levels in authored code.";
    applies_to = ["implementation" "review"];
    severity = "important";
    enforcement = "review";
    exceptions = ["generated-code" "parser" "state-machine" "framework-callback"];
    workflow_gates = ["refactor_after_green"];
  };

  max-two-directory-depth = {
    intent = "Default new feature/domain modules to at most two directory levels inside their bounded context.";
    applies_to = ["architecture" "scaffold" "review"];
    severity = "advisory";
    enforcement = "guidance";
    exceptions = ["provider-native-layout" "framework-required-layout" "generated-artifact" "existing-convention"];
    workflow_gates = ["design_boundary_selected"];
  };

  flexible-solid = {
    intent = "Use SOLID as a smell detector, not as an abstraction quota.";
    applies_to = ["architecture" "implementation" "review"];
    severity = "advisory";
    enforcement = "guidance";
    exceptions = ["small-local-script" "framework-required-shape"];
    workflow_gates = ["design_tradeoff_recorded"];
  };

  explicit-error-handling = {
    intent = "Make failure paths visible through return values, typed/domain errors, or explicit exceptions.";
    applies_to = ["design" "implementation" "review" "test"];
    severity = "important";
    enforcement = "review";
    exceptions = ["fire-and-forget-best-effort-log"];
    workflow_gates = ["dependency_strategy_selected" "test_case_scope_selected"];
  };

  line-width-120 = {
    intent = "Keep authored source near 120 columns unless local formatter conventions override it.";
    applies_to = ["implementation" "review"];
    severity = "advisory";
    enforcement = "deterministic";
    exceptions = ["formatter-output" "long-url" "generated-code"];
    workflow_gates = ["focused_verification"];
  };

  korean-core-comments = {
    intent = "Use Korean multiline comments above core methods or features to explain intent and invariants.";
    applies_to = ["implementation" "review"];
    severity = "advisory";
    enforcement = "guidance";
    exceptions = ["obvious-helper" "generated-code" "external-template"];
    workflow_gates = ["refactor_after_green"];
  };

  minimize-abstraction = {
    intent = "Add abstraction only for real complexity, volatility, duplication, or established local patterns.";
    applies_to = ["architecture" "implementation" "review"];
    severity = "important";
    enforcement = "review";
    exceptions = ["provider-required-interface" "framework-required-interface"];
    workflow_gates = ["design_tradeoff_recorded" "refactor_after_green"];
  };

  single-writer-no-thread-conflict = {
    intent = "Keep repository mutation single-writer and runtime shared-state ownership explicit.";
    applies_to = ["workflow" "architecture" "implementation" "review" "test"];
    severity = "critical";
    enforcement = "review";
    exceptions = ["readonly-parallel-agent"];
    workflow_gates = ["write_owner_selected" "parallel_safety_checked"];
  };

  dto-over-five-args = {
    intent = ''
      Use a DTO, request object, command object, or cohesive value object when
      more than five arguments are needed.
    '';
    applies_to = ["implementation" "review"];
    severity = "important";
    enforcement = "review";
    exceptions = ["language-idiom" "generated-code" "test-table-row"];
    workflow_gates = ["refactor_after_green"];
  };

  meaningful-boolean-temps = {
    intent = "Extract non-trivial boolean branch conditions into meaningful temporary variables.";
    applies_to = ["implementation" "review" "test"];
    severity = "advisory";
    enforcement = "review";
    exceptions = ["single-obvious-check" "generated-code"];
    workflow_gates = ["minimal_implementation"];
  };
}
