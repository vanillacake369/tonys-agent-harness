{
  surfaces = {
    steering = {
      intent = "supported";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = ["~/.kiro/tonys-nix/steering/AGENTS.md" "~/.kiro/tonys-nix/steering/agent-contract.md"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests" "home-activation-build"];
    };
    specs = {
      intent = "unsupported";
      implementation = "unsupported";
      enforcement = "none";
      lossiness = ["ephemeral design/spec/requirements documents are not exported"];
      artifacts = [];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests" "home-activation-build"];
    };
    skills = {
      intent = "supported";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = ["~/.kiro/skills/**/SKILL.md"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests" "home-activation-build"];
    };
    agents = {
      intent = "generated";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = ["~/.kiro/agents/*.json"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests" "home-activation-build"];
    };
    workflows = {
      intent = "generated";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = ["~/.kiro/workflows/*.workflow.json"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests" "home-activation-build"];
    };
    mcp = {
      intent = "generated";
      implementation = "seeded";
      enforcement = "initial_seed";
      lossiness = ["existing user-level MCP config is preserved after first seed"];
      artifacts = ["~/.kiro/settings/mcp.json"];
      diagnostics = [];
      handled_permission_fields = ["mcp"];
      validation = ["guard-tests" "home-activation-build"];
    };
    permissions = {
      intent = "generated";
      implementation = "generated";
      enforcement = "enforced";
      lossiness = ["interactive approvals remain provider-owned"];
      artifacts = ["~/.kiro/agents/*.json permissions.rules"];
      diagnostics = [];
      handled_permission_fields = [
        "workspace"
        "network"
        "secret_access"
      ];
      validation = ["guard-tests" "home-activation-build"];
    };
  };
}
