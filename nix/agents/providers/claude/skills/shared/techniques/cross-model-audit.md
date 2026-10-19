# Technique: Cross-Model Audit

## When to Use
- 핵심 기능(결제, 인증, 데이터 무결성) 검증
- 보안 리뷰가 필요한 코드
- 아키텍처 결정의 second opinion

## Protocol

1. **Auditor 선택**:
   - 보안/아키텍처 → `gpt-5.4` (via cli-proxy-api)
   - 일반 검증 → `gemini-2.5-flash-lite` (via cli-proxy-api)

2. **Prompt 구성**:
   ```
   다음 [코드/설계/분석]을 검토하라.
   설계자가 놓쳤을 법한:
   1. 엣지 케이스 3가지
   2. 보안 취약점 2가지
   3. 대안적 접근법 1가지
   를 제시하라.
   ```

3. **Synthesis**: 원본 분석 + 감사 결과를 종합하여 최종 판단

## Proxy Unavailable 시
- 프록시 미응답 → cross-validation 불가 명시
- 원본 분석만으로 진행하되 `[UNAUDITED]` 태그 부착

## Output Template

```
### Cross-Model Audit: [대상]
- Auditor: [model]
- Agreement: [일치 사항]
- Gaps Found: [발견된 gap]
- Synthesis: [최종 권고]
```

## Exit Criteria
- 감사 요청 전송 완료 (또는 불가 사유 명시)
- Synthesis 작성 완료
