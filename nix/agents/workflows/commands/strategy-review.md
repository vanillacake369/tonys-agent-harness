독립 전략 A/B를 교차검증하고, 합의·충돌·미검증 전제를 결정 가능한 ADR로 만든다.

# Task
$ARGUMENTS

# Cross Validation Protocol

1. Strategist A와 B는 서로의 초안을 보지 않고 같은 PRD, Repository Context,
   Research Evidence를 기준으로 독립 판단한다.
2. A는 현재 시스템 적합성·비용·운영 안정성을 우선하고, B는 대안·확장성·
   숨은 실패 조건을 우선한다. 역할 차이는 결론을 미리 정하지 않는다.
3. Decision Synthesizer는 두 결과를 주장 단위로 정규화하고, 같은 판단은
   `AGREEMENT`, 다른 판단은 `CONFLICT`, 근거가 부족한 판단은 `UNVERIFIED`,
   서로 다른 축을 보완하는 판단은 `COMPLEMENTARY`로 분류한다.
4. 합의가 정답이라는 가정을 금지한다. 합의된 주장도 영향도가 높거나 핵심
   전제라면 Independent Validator의 검증 대상으로 남긴다.
5. 충돌을 임의로 평균내지 않는다. 충돌마다 영향도, 근거, 결정에 미치는
   의존성, 추가 검증 방법, 보류 시 안전한 기본값을 기록한다.
6. 구현·외부 변경을 수행하지 않는다. 이 Workflow의 산출물은 결정 기록과
   검증 계획이며, 실행은 별도 Human Gate와 Phase Execution Plan을 따른다.

# Output
다음 구조를 정확히 사용한다.

## Decision Matrix
| Dimension | Strategist A | Strategist B | Status | Evidence | Impact |
|---|---|---|---|---|---|
| ... | ... | ... | AGREEMENT/CONFLICT/UNVERIFIED/COMPLEMENTARY | ... | ... |

## Consensus
- `claim`: 두 전략이 일치하는 내용
- `evidence`: 공통으로 지지하는 근거
- `confidence`: high/medium/low
- `caveat`: 합의가 깨질 수 있는 조건

## Conflicts
- `claim`: 충돌하는 주장
- `strategy_a`: A의 입장과 근거
- `strategy_b`: B의 입장과 근거
- `decision_impact`: 결정에 미치는 영향
- `resolution`: resolve/defer/accept-risk
- `safe_default`: 미해결 시 적용할 안전한 기본값

## Unverified Assumptions
- `assumption`: 검증되지 않은 전제
- `owner`: 검증 책임 역할
- `evidence_needed`: 필요한 증거
- `blocking`: yes/no

## Validation Plan
각 핵심 합의·충돌·전제에 대해 검증 명령, 공식 문서, PoC, benchmark 또는
독립 리뷰 중 하나를 지정한다. 검증하지 못한 항목은 추천안의 확정 근거로
표현하지 않는다.

## Decision
- chosen strategy:
- rejected alternatives and reasons:
- rollback:
- Human Gate required: yes/no and why

## ADR
최종 ADR에는 결정, 근거, 합의, 충돌, 미검증 전제, 검증 결과, 재평가 조건을
연결한다.
