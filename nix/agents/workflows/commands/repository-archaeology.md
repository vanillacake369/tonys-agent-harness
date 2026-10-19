기존 저장소의 숨은 계약을 구현 전에 확인한다.

# Task
$ARGUMENTS

# Workflow
`rg`와 저장소의 기존 task runner를 사용해 진입점, 호출자, 의존성, 생성 산출물, 테스트, 문서를 추적한다. 변경 대상의 직접·간접 소비자와 호환성 제약을 기록한다. 추론은 미검증으로 표시한다.

# Output
Repository map, data/control flow, conventions, affected boundaries, compatibility constraints, unknowns, and recommended read-only next step.
