# Phase Execution Plan

Decision Engine 결과를 Phase 3~5 실행 계획으로 변환한다.

## Human Gate

- `HUMAN_APPROVAL`은 승인 요청 상태일 뿐 실행 승인으로 간주하지 않는다.
- 승인 scope digest가 현재 request digest와 일치해야 한다.
- Phase 5는 항상 명시적 승인 없이는 `READY_TO_EXECUTE`가 될 수 없다.
- `BLOCKED`, 불명확한 승인, 정책 오류는 즉시 중단한다.

## 산출물

`execution-plan.sh`를 통해 phase, decision_id, 상태, 역할 순서, single-writer,
traceability/evidence gate, 다음 행동을 구조화한다. 이 workflow는 계획만
생성하며 배포·마이그레이션·외부 리소스 변경을 실행하지 않는다.
