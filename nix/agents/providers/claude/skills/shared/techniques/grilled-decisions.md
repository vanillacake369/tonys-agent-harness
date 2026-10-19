# Technique: Grilled Decisions (adversarial design interrogation)

## When to Use
- Phase 2 (STRATEGY), irreversible/wide-blast work only
- `strategy-lint`가 `grilled-decisions` 섹션을 필수로 검증함 — irreversible 세션에서만 EXECUTION 차단

## Protocol
설계안의 각 비자명한 결정을 코딩 전에 캐묻는다. 적대적 인터뷰어처럼,
"왜 더 단순하지 않은가"를 끝까지 추궁한다. grill-with-docs 패턴:
기존 도메인 문서/ADR와의 충돌까지 확인한다.

핵심 질문(최소 답해야 하는 것):
1. **필요성**: 이 추상화/의존성/레이어가 *정말* 필요한가? 없으면 무엇이 깨지나?
2. **더 단순한 대안**: 한 단계 더 단순한 해법은? 왜 그걸 안 쓰나?
3. **오답 비용**: 이 결정이 틀렸다고 판명되면 되돌리는 비용은? (reversible/irreversible)
4. **문서 충돌**: 기존 CLAUDE.md / AGENTS.md / ADR / 도메인 모델과 모순되지 않나?

## Iterative Loop (draft → grill → revise → re-grill, max ~3 rounds)

grill은 일회성 정당화가 아니라 반복 루프다. 각 라운드에서 발견된 문제는
다음 라운드의 draft 개정을 촉발해야 한다. review/grill-with-docs로 구동한다.

```
Round 1: 초기 설계안 → grill → 발견 → 수정
Round 2: 수정안 → re-grill → 발견 → 수정 (or 유지)
Round 3: 최종안 확인 → 잔류 리스크 문서화
```

## Output Template (Revision-Delta Table)

**기본 기대값: grilling은 최소 하나의 결정을 수정한다.**
아무것도 바뀌지 않았다면 반드시 "N개 grill, 0개 수정 — 이유: ..." 를 명시하라.

```
### Grilled Decisions
| 초기안 | grill 질문 | 발견 | 조치 (수정/유지) |
|--------|------------|------|-----------------|
| ...    | ...        | ...  | 수정: 새 안 / 유지: 이유 |
```

## Exit Criteria
- 모든 비자명한 결정이 위 4개 질문을 통과
- 기본값은 수정(revision); 변경 없이 유지(retain)했다면 그 이유를 명시
- 통과 못한 결정 → 단순한 대안으로 회귀하거나 Decision Gate에서 사용자에게 보고
