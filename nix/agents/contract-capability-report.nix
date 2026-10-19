{lib}: let
  contracts = import ./contract-validated.nix {inherit lib;};
  codex = import ./providers/codex/capabilities.nix;
  kiro = import ./providers/kiro/capabilities.nix;
in {
  # 현재 실제 export가 연결된 provider capability만 보고한다.
  # desired에는 전체 목표 provider 계약을 남겨 gap 분석에 사용한다.
  # 이 분리 덕분에 미래 provider를 계약에 먼저 적어도 활성 export와 섞이지 않는다.
  providers.codex = codex;
  providers.kiro = kiro;
  desired = contracts.providers;
}
