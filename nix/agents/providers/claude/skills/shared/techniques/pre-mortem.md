# Technique: Pre-mortem Analysis

## When to Use
- 전략/설계 확정 전 (Phase 2)
- 파괴적 변경, 새로운 기술 도입, 아키텍처 결정 시

## Protocol

1. 설계안 작성 후 즉시 수행
2. "이 설계가 6개월 뒤 실패했다고 가정하라. 원인 3가지를 나열하라."
3. 각 실패 원인에 대해 **완화책(mitigation)** 또는 **감지 방법(detection)** 명시
4. 완화 불가능한 리스크 → Decision Gate에서 사용자에게 보고

## Output Template

```
### Pre-mortem: [설계명]
| # | 실패 시나리오 | 확률 | 완화책 |
|---|-------------|------|--------|
| 1 | ... | H/M/L | ... |
| 2 | ... | H/M/L | ... |
| 3 | ... | H/M/L | ... |
```

## Exit Criteria
- 3개 이상의 시나리오 도출
- 각 시나리오에 완화책 존재
- High 확률 항목이 있으면 반드시 Decision Gate 통과
