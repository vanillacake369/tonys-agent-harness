# Technique: Systems Thinking & Ripple Effect Analysis

## When to Use
- 모듈 경계를 넘는 변경
- 공유 의존성(라이브러리, 설정, 스키마) 수정
- 성능/보안에 영향을 줄 수 있는 변경

## Protocol

1. **Impact Mapping**: 변경 대상 → 직접 의존자 → 간접 의존자 나열
2. **3축 Trade-off 평가**:

| 축 | 현재 | 변경 후 | 판정 |
|----|------|---------|------|
| 성능 | ... | ... | +/=/- |
| 가독성 | ... | ... | +/=/- |
| 유지보수성 | ... | ... | +/=/- |

3. **Ripple Effect 체크리스트**:
   - [ ] 빌드 영향 범위 확인
   - [ ] 테스트 영향 범위 확인
   - [ ] 설정/환경변수 변경 필요 여부
   - [ ] 하위 호환성 깨짐 여부
   - [ ] 다른 팀/서비스 영향 여부

4. 2개 이상 축에서 `-` 판정 → Decision Gate 보고

## Memory Integration
변경 후 결과를 Memory에 기록하여 향후 유사 결정 시 참조:
```
memory_write("decision:{module}:{date}", {context, decision, outcome})
```

## Exit Criteria
- Impact Mapping 완료
- 3축 평가 테이블 존재
- Ripple Effect 체크리스트 전체 확인
