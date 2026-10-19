# Project Bootstrap

프로젝트를 먼저 읽고, 기존 설정을 보존하는 맞춤형 Engineering System 제안서를 만든다.

## 절차

1. 언어, 프레임워크, 디렉터리, 모듈 경계를 근거와 함께 조사한다.
2. build, test, lint, format, CI/CD, IaC, 보안·운영 요구사항을 확인한다.
3. AGENTS.md와 provider 설정의 중복·누락·불일치를 찾는다.
4. 필요한 role, skill, workflow, MCP 권한과 위험·승인 정책을 제안한다.
5. 기존 파일을 덮어쓰지 않고 적용 전 diff와 영향 범위를 출력한다.

## 산출물

- Project Profile
- AGENTS.md 보완안
- Provider별 설정 변경안
- 추천 Skill 및 MCP 권한 목록
- Test / Verification Policy
- 위험도, 승인 조건, 적용 전 Diff 및 영향 분석

이 workflow는 제안만 생성하며, 설정 파일 변경은 별도 승인과 단일 writer를 요구한다.
