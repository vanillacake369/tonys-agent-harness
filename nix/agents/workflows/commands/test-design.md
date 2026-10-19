요구사항과 설계에서 검증 가능한 테스트 명세를 만든다.

# Task
$ARGUMENTS

# Workflow
Requirement ID별 happy path, boundary, invalid input, dependency failure, regression을 도출한다. 외부 I/O·시간·난수·네트워크는 adapter boundary와 명시적 의존성 전략으로 분리한다. 각 테스트는 기대 결과와 실행 명령을 가져야 하며 implementation detail에 결합하지 않는다.

# Output
Test strategy, cases, fixtures, test level, dependency strategy, traceability matrix, evidence gates, and exemptions.
