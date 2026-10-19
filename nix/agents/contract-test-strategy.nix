{
  default-tdd = {
    case_scope = [
      "happy_path"
      "boundary"
      "invalid_input"
      "dependency_failure"
      "regression"
    ];
    levels = [
      "unit"
      "integration_when_adapter_boundary_changes"
      "contract_when_provider_output_changes"
      "e2e_when_user_visible_flow_requires_it"
    ];
    dependency_policy = {
      pure_domain = "no_mock";
      external_io = "fake_or_adapter_mock";
      time_random_uuid = "injectable";
      network_filesystem_process = "adapter_boundary";
    };
    fixture_policy = "small_explicit_fixtures";
    format = {
      style = "gwt";
      naming = "GIVEN ... WHEN ... THEN ...";
      source = "tonys-nvim";
    };
    gates = [
      "test_case_scope_selected"
      "dependency_strategy_selected"
      "failing_test_written_or_exemption_recorded"
      "minimal_implementation"
      "refactor_after_green"
      "focused_verification"
      "prd_traceability_complete"
      "independent_review_complete"
      "evidence_recorded"
    ];
    exemptions = [
      "docs_only"
      "mechanical_generated_output"
      "existing_behavior_characterization_first"
    ];
  };
}
