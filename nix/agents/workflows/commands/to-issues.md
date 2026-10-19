PRD를 vertical-slice 이슈로 분해한다.

# Task
$ARGUMENTS

# Workflow
각 slice가 schema/API/logic/test 등 필요한 경계를 end-to-end로 통과하고 독립 검증 가능한지 확인한다. AFK와 HITL을 구분하고, blocked-by 의존성을 명시한다. 먼저 제안된 분해를 사용자와 확인해야 하며 승인 전에는 issue 파일을 쓰지 않는다.

# Output
Numbered issue proposal with title, type, dependencies, user stories, acceptance criteria, and approved output paths.
