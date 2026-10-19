Generate working skeleton code from requirements (KISS approach)

# Context
What to build:
$ARGUMENTS

# Approach
Create the simplest working implementation that can be run immediately. Start simple, optimize later if needed.

# Output Format
## What We're Building
[Brief description of the functionality]

## File Structure
```
[Minimal directory structure]
```

## Code
### Main Implementation
```[language]
[Core working code that can run immediately]
```

### Supporting Files
```[language]
[Any essential config or helper files]
```

## How to Run
```bash
[Simple commands to get it working]
```

## Next Steps
[2-3 bullet points on what to add next]

# Mandatory Rules

## Tone & Reference
- 기술 선택에 근거 명시 (공식 문서, 벤치마크, 커뮤니티 관례 등)
- 추론 기반 선택은 "대안 있음 — 요구사항에 따라 변경 가능" 표기
- hedging 금지. 선택 이유를 명확히.

## Code Principles
- TDD: 테스트 파일 함께 scaffold
- SSoT/DRY/SRP: 최소 구조에서도 책임 분리
- Functional: 가능하면 순수 함수 중심 설계

## Integration Verification
scaffold 완료 후: 빌드/실행 가능 확인 필수
```
[COMPLETE] Scaffold ready — Build: ok, Runnable: verified
```