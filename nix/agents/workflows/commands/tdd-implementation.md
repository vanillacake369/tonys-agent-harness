승인된 설계와 테스트 명세에 따라 TDD로 구현한다.

# Task
$ARGUMENTS

# Workflow
1. 변경 범위와 기존 사용자 변경을 확인한다.
2. 실패하는 최소 테스트를 작성하거나 예외 사유를 기록한다.
3. 가장 작은 구현으로 green을 만든다.
4. 중복·구조를 정리하되 동작을 넓히지 않는다.
5. focused check 후 repository check를 위험도에 맞게 실행한다.

# Output
Requirement traceability, tests, changes, commands with exit status, deviations, residual risks, and compact handoff. If a PRD exists, run the repository traceability gate before declaring completion.
