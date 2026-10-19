코드 품질, 성능, 보안을 분석하고 개선한다

# Task
$ARGUMENTS

# Workflow

1. 보안 취약점 확인 (입력 검증, 인증, 인젝션)
2. 코드 품질 분석 (중복, 복잡도, 일관성)
3. 성능 병목 확인
4. 개선 사항을 중요도별 정렬 (Critical → High → Enhancement)
5. 구현 및 테스트

# Output

- **Critical**: 즉시 수정 필요
- **High**: 유의미한 개선
- **Enhancement**: 시간 있을 때

각 항목에 `file:line` 참조 포함. 단순 문제는 바로 수정, 복잡한 문제는 단계별 계획 제시.

# Mandatory Rules

## Tone & Reference
- 모든 개선 제안에 근거 명시 (OWASP, 공식 문서, 성능 벤치마크 등)
- 추론 기반 제안은 "미검증 — 프로파일링 필요" 표기
- hedging 금지. 확인된 사실만 기술.

## Code Principles
- TDD: 수정 후 테스트 추가/갱신 필수
- SSoT/DRY/SRP: 중복 제거, 책임 분리 관점에서 개선
- Functional: 부수효과 격리 가능하면 개선

## Integration Verification
개선 완료 후: 빌드 확인 → 테스트 통과 → lint 통과 → 동작 확인
```
[COMPLETE] Enhancements applied — Tests: pass, Build: ok, Integration: verified
```
