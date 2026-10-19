# agent provider export를 Home Manager module로 묶는다.
# 현재 apply 대상 provider만 import해서 계약상 desired provider와 실제 출력 경계를 분리한다.
{
  imports = [
    ./config-mcp.nix
    ./runtime-secrets.hm.nix
    ./runtime-hooks.nix
    ./providers/codex/module.nix
    ./providers/kiro/module.nix
  ];
}
