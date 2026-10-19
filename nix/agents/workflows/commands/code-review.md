완료된 변경을 adversarial code review한다.

# Task
$ARGUMENTS

# Focus
버그·보안·성능·동시성·프레임워크 계약을 구현자와 독립적으로 확인한다. 누락된 caller나 query를 찾지 못했다면 verdict의 미검증 영역으로 명시한다. CRITICAL finding 하나라도 있으면 FAIL이다.

# Output
`## Verdict: PASS | FAIL`, severity findings, scenarios verified, evidence, and recommended fix direction.
