{
  surfaces = {
    context = {
      intent = "generated";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = ["programs.codex.context"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests"];
    };
    skills = {
      intent = "generated";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = ["programs.codex.skills"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests"];
    };
    roles = {
      intent = "generated";
      implementation = "generated";
      enforcement = "advisory";
      lossiness = [];
      artifacts = [".codex/agents/*.toml" "agent role skills"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests"];
    };
    permissions = {
      intent = "generated";
      implementation = "generated";
      enforcement = "enforced";
      lossiness = ["mcp approval/destructive semantics are reported through settings and policy text"];
      artifacts = ["settings.permissions" ".codex/agents/*.toml"];
      diagnostics = [];
      handled_permission_fields = [
        "workspace"
        "network"
        "secret_access"
      ];
      validation = ["guard-tests"];
    };
    hooks = {
      intent = "provider_owned";
      implementation = "provider-owned";
      enforcement = "enforced";
      lossiness = [];
      artifacts = ["settings.hooks"];
      diagnostics = [];
      handled_permission_fields = [];
      validation = ["guard-tests"];
    };
    mcp = {
      intent = "generated";
      implementation = "generated";
      enforcement = "enforced";
      lossiness = [];
      artifacts = ["settings.mcp_servers"];
      diagnostics = [];
      handled_permission_fields = ["mcp"];
      validation = ["guard-tests"];
    };
  };
}
