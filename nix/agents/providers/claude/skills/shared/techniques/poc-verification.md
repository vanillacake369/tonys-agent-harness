# Technique: One-shot PoC Verification

## When to Use
- 처음 사용하는 API/라이브러리
- 파괴적 설정 변경 (DB 마이그레이션, 인프라 변경)
- 동작이 문서와 다를 가능성이 있는 경우
- 성능 특성을 확인해야 하는 경우

## Protocol

1. **Scope 제한**: 10줄 내외의 독립 스크립트. 프로덕션 코드에 영향 없음.
2. **단일 검증 포인트**: PoC 하나당 하나의 가설만 검증
3. **Review Points 제시**: 사용자에게 "이 동작이 의도와 일치하는지" 확인 요청
4. **Decision Gate**: PoC 결과 공유 후 승인 대기

## Output Template

```
### PoC: [검증 대상]
- Hypothesis: [검증하려는 가설]
- Script: [10줄 내외 코드]
- Expected: [예상 결과]
- Actual: [실행 결과]
- Review Point: [사용자에게 확인할 사항]
```

## Exit Criteria
- 실행 가능한 독립 스크립트
- 실행 결과 포함
- 사용자 승인 획��
