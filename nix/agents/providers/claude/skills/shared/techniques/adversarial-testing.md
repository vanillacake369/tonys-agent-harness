# Technique: Adversarial Testing

## When to Use
- 테스트 설계 시 (Phase 4)
- 핵심 비즈니스 로직, 보안 경계, 외부 입력 처리 코드

## Protocol

1. **Requirement-Test Mapping**: 요구사항 → 테스트 케이스 매핑 테이블 작성
2. **Self-Challenge**: "이 테스트를 통과하면서도 버그가 있는 코드를 짤 수 있는가?" 질문
3. **5대 엣지 케이스 강제 점검**:

| Category | Check |
|----------|-------|
| Null/Empty | 빈 값, null, undefined, 빈 배열/맵 |
| Boundary | 최대/최소값, 0, -1, MAX_INT, 루프 시작/끝 |
| Type/Format | 잘못된 타입, 유니코드, 특수문자, 초과 길이 |
| State | 재진입, 동시 호출, 초기화 전 접근, 상태 전이 중 |
| Failure Path | 네트워크 실패, 타임아웃, 권한 없음, 디스크 풀 |

4. 각 카테고리에서 최소 1개 테스트 케이스 도출

## Exit Criteria
- Mapping 테이블 존재
- 5개 카테고리 각각 최소 1개 커버
- Self-Challenge에서 발견된 gap이 0
