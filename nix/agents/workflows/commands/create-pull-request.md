현재 브랜치의 변경사항을 분석하여 PR을 생성한다

# Context
$ARGUMENTS

# Workflow

1. `git log`과 `git diff`로 변경사항 파악
2. `git remote -v`로 fork/upstream 관계 파악
3. PR 본문을 아래 템플릿으로 작성
4. `gh pr create`로 PR 생성

# Fork 감지

- origin이 fork이고 upstream이 있으면 → `--repo upstream --head user:branch`
- origin이 본인 repo이면 → 일반 PR

# PR 본문 템플릿

```markdown
## 개요

[무엇을 왜 하는지 1-2문장]

## 변경사항

[핵심 변경 내용을 bullet으로. 파일 목록이 아닌 맥락 중심]

## 테스트

[실행 명령어와 결과 요약]

## 논의사항

### 이슈 : [문제가 무엇인지]

[원인과 영향 설명]

### 대안

[왜 현재 선택을 했는지 설명]

| 대안 | 장점 | 단점 |
|------|------|------|
| **현재 선택** | ... | ... |
| 다른 옵션 | ... | ... |

> ***리뷰어 요청사항 : [판단이 필요한 부분]***
```

# 주의사항

- 논의사항이 없으면 해당 섹션 생략
- 변경사항에 파일 경로 나열 금지. "무엇을 어떻게"만 기술
- PR 제목은 70자 이내, conventional commit 형식
