코드 변경의 영향과 안전성을 사전·사후 점검한다.

# Task
$ARGUMENTS

# Checklist
호출자·소비자·데이터 호환성을 먼저 추적하고, DB/인프라 변경은 모든 read/write 경로와 rollback을 확인한다. 기존 테스트 baseline과 관련 테스트를 실행한다. 불확실하거나 unrelated issue는 추측해 수정하지 말고 별도 finding으로 보고한다. 시크릿과 credential store는 읽지 않는다.

# Output
Impact scope, baseline command, related verification, assumptions, blockers, and guardrail gate.
