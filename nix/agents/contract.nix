# provider-neutral 계약 조각을 한 곳에서 합친다.
# 검증이나 provider 변환은 이 raw 계약을 import한 다음 별도 경계에서 수행한다.
{
  providers = import ./contract-providers.nix;
  roles = import ./contract-roles.nix;
  workflows = import ./contract-workflows.nix;
  skillBundles = import ./contract-skill-bundles.nix;
  permissions = import ./contract-permissions.nix;
  engineeringRules = import ./contract-engineering-rules.nix;
  testStrategies = import ./contract-test-strategy.nix;
  governance = import ./contract-governance.nix;
}
