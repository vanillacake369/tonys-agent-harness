작업을 분류하고 필요한 역할과 검증 게이트만 선택한다.

# Task
$ARGUMENTS

# Workflow
1. 요청과 저장소 증거를 읽고 trivial/standard/complex를 분류한다.
2. 되돌릴 수 없음, 보안·데이터 손실, 외부 시스템, 불확실성, 변경 범위를 평가한다.
3. 가장 작은 안전 경로를 선택한다. 모든 작업에 모든 역할을 투입하지 않는다.
4. 읽기 전용 역할은 병렬화할 수 있지만 repository writer는 한 명으로 고정한다.
5. PRD가 있으면 requirement ID가 design, code, test, verification까지 이어지는지 확인한다.
6. 통과하지 못한 gate를 완료로 보고하지 않고, blocker·결정 필요사항·다음 실행을 기록한다.

## Authority Boundary

- LLM Judge는 위험·불확실성·질문 후보를 제안할 뿐 권한을 발급하지 않는다.
- Review Gate는 finding과 권고를 기록할 뿐 실행을 승인하지 않는다.
- `policy_engine`과 `execution_gate`의 결정적 결과만 실행 권한을 통제한다.
- 승인 정보가 없거나 정책 평가에 실패하면 fail-closed로 중단한다.

# Output
Classification, selected route, omitted phases, delegated roles, single-writer owner, required gates, evidence, escalation conditions, and compact handoff.
