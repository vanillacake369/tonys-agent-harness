{lib}: manifest: let
  presets = {
    minimal = {providers = ["codex"]; roles = ["implementer" "reviewer"];};
    application = {providers = ["codex" "claude"]; roles = ["requirement-designer" "researcher" "implementer" "reviewer"];};
    infra-devops = {providers = ["codex" "claude" "kiro"]; roles = ["requirement-designer" "researcher" "architect" "implementer" "reviewer"];};
    regulated = {providers = ["codex" "claude" "gemini" "kiro"]; roles = ["requirement-designer" "researcher" "architect" "implementer" "reviewer"];};
  };
  providerOrder = ["codex" "claude" "gemini" "kiro"];
  preset = presets.${manifest.preset};
  configured = manifest.providers or {};
  project = manifest.project or {};
  guides = project.guides or {};
  approval = manifest.approval or {};
in {
  schema_version = 1;
  inherit (manifest) preset;
  project = {
    instruction = project.instruction or "AGENTS.md";
    spec_root = project.spec_root or ".codex";
    guides = {
      enabled = guides.enabled or false;
      source = guides.source or "";
      link = guides.link or ".agent-context/team-guides";
    };
  };
  providers = lib.filter (name: configured.${name} or (builtins.elem name preset.providers)) providerOrder;
  workflow = manifest.workflow or {};
  permissions = {
    secret_access = "deny";
    reviewer_write = false;
    researcher_write = false;
    single_writer = true;
  };
  approval = {
    production = true;
    destructive = true;
    migration = true;
    external_mutation = true;
    public_key_path = approval.public_key_path or "";
    expected_fingerprint = approval.expected_fingerprint or "";
  };
  verification = manifest.verification or {retry_max = 3;};
}
