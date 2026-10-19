Generate comprehensive Korean test case documentation using external policies and code analysis

# Task
$ARGUMENTS

# Workflow

This command orchestrates MCP servers and skills for test documentation with **Human-in-the-Loop (HITL) checkpoints**:

1. **sequential-thinking MCP**: Systematic analysis planning and hypothesis testing
2. **HITL Checkpoint 1**: Input clarification and external document confirmation
3. **memory MCP**: Create temporary knowledge graph for analysis context
4. **Figma MCP** (if URL provided): Fetch external design/policy documents
5. **Google Drive MCP** (if URL provided): Access test standards from Google Sheets
6. **JIRA MCP** (if URL/issue key provided): Fetch requirements from JIRA issues
7. **[codebase-analysis]**: Understand feature implementation and architecture
8. **HITL Checkpoint 2**: Business rules and boundary value confirmation
9. **[test-development]**: Identify success/failure/edge case scenarios
10. **HITL Checkpoint 3**: Test scope and priority finalization
11. **Documentation generation**: Create structured Korean test case table
12. **memory MCP cleanup**: Preserve patterns, delete temporary analysis data

# Input Format

Provide code files or features to analyze, with optional external document URLs:

```bash
/testdoc "path/to/UserService.java"
/testdoc "OrderAPI feature --figma=https://figma.com/file/xyz"
/testdoc "PaymentController.java --sheets=https://docs.google.com/spreadsheets/d/abc"
/testdoc "Authentication flow --jira=PROJ-123"
/testdoc "Payment feature --figma=URL --sheets=URL --jira=https://jira.company.com/browse/PAY-456"
```

# MCP Integration Strategy

## sequential-thinking Usage
Use for complex, multi-step analysis:
- Breaking down feature requirements
- Hypothesis testing for edge cases
- Systematic scenario identification
- Trade-off analysis for test priorities

## memory MCP Usage
**Temporary Entities** (deleted after execution):
- `Feature_{name}`: File paths, endpoints, components analyzed
- `Scenario_{id}`: Specific test scenarios identified
- `Analysis_{timestamp}`: Current session findings

**Persistent Entities** (kept for future reference):
- `TestPattern_{category}`: Reusable test scenario patterns
- `ErrorScenario_{type}`: Common failure scenarios by type
- `PolicyReference_{source}`: External policy standards

**Relations to Create**:
- `Feature → has_scenario → Scenario`
- `Scenario → follows → TestPattern`
- `Scenario → references → PolicyReference`

## Figma MCP Usage (Optional)
When `--figma=URL` provided:
- Fetch design specifications and requirements
- Extract policy standards and acceptance criteria
- Reference UI/UX constraints in test cases
- Use design states for test condition variations

## Google Drive MCP Usage (Optional)
When `--sheets=URL` provided:
- Access existing test templates and standards
- Fetch organizational testing policies
- Reference approved test case formats
- Import domain-specific test criteria

## JIRA MCP Usage (Optional)
When `--jira=URL` or `--jira=ISSUE-KEY` provided:
- Fetch user stories and acceptance criteria from JIRA issues
- Extract requirements and business rules from issue descriptions
- Reference linked issues and dependencies for comprehensive coverage
- Import test scenarios from JIRA comments or attachments
- Track which requirements are being tested (traceability)

# HITL Interaction Points

This command uses **AskUserQuestion** tool at strategic checkpoints to ensure accuracy and business alignment.

## Phase 1: Pre-Analysis (HITL Checkpoint 1)

**Always Ask** (before codebase analysis):

1. **External Document Confirmation**
   ```
   Questions to ask:
   - "Figma URL이 제공되지 않았습니다. 의도적으로 생략하신 건가요?"
     Options: "예, 디자인 문서 없음" / "아니요, URL 제공하겠습니다"

   - "Google Sheets URL이 제공되지 않았습니다. 테스트 표준 문서가 필요한가요?"
     Options: "예, URL 제공하겠습니다" / "아니요, 표준 문서 없이 진행"

   - "JIRA 이슈가 제공되지 않았습니다. 요구사항 문서가 필요한가요?"
     Options: "예, JIRA 이슈 키/URL 제공하겠습니다" / "아니요, 코드 분석만으로 진행"
   ```

2. **Test Scope Clarification**
   ```
   When multiple files match the pattern:
   - "UserService.java가 3개 경로에서 발견되었습니다. 어느 것을 분석할까요?"
     Options: "domain/user/api/" / "legacy/user/" / "admin/user/" / "모두 분석"

   When feature name is ambiguous:
   - "createUser 메서드만 분석? 관련 CRUD 전체를 포함?"
     Options: "createUser만" / "User CRUD 전체" / "User 도메인 전체"
   ```

3. **Platform Scope**
   ```
   - "어떤 플랫폼의 테스트 케이스가 필요한가요?"
     Options: "API만" / "Web만" / "Mobile만" / "API + Web" / "전체 플랫폼"
   ```

## Phase 2: During Analysis (HITL Checkpoint 2)

**Ask When Detected** (코드 분석 중 불확실성 발견 시):

| 감지 조건 | 질문 템플릿 | 옵션 예시 |
|----------|------------|----------|
| **Validation 누락** | "`@Valid` 어노테이션이 없습니다. 서버 검증 없이 프론트 검증만?" | "서버 검증 추가 필요" / "프론트만으로 충분" |
| **경계값 미정의** | "`email` 필드 최대 길이가 코드에 없습니다. 어떻게 설정할까요?" | "255자" / "100자" / "제약 없음" |
| **Optional 반환 타입** | "`Optional<User>` 반환. `null`과 `empty` 케이스 구분?" | "구분 필요" / "동일하게 처리" |
| **Transactional 누락** | "`@Transactional` 없음. 롤백 시나리오 필요?" | "필요" / "불필요" |
| **외부 API 호출** | "외부 PG사 API 호출 감지. 타임아웃/실패 시나리오 포함?" | "포함" / "Mock만" / "제외" |
| **Enum 필드** | "`OrderStatus` enum 발견. 모든 상태별 테스트?" | "모든 상태" / "주요 상태만" |
| **권한 체계 불명확** | "`ADMIN` 권한 체크. `MANAGER`도 접근 가능?" | "ADMIN만" / "MANAGER 포함" / "확인 필요" |

## Phase 3: Pre-Generation (HITL Checkpoint 3)

**Ask Before Creating Test Cases**:

1. **Boundary Value Confirmation**
   ```
   Template:
   "다음 필드의 경계값을 확인해주세요:
   - amount: 최소값 ___, 최대값 ___
   - username: 최소 길이 ___, 최대 길이 ___, 허용 문자 ___
   - uploadFile: 최대 크기 ___, 허용 확장자 ___"
   ```

2. **Test Case Priority**
   ```
   When many scenarios identified (>30):
   - "35개 테스트 케이스가 도출되었습니다. 어떻게 진행할까요?"
     Options:
     - "핵심 15개만 (성공 5 + 실패 5 + 엣지 5)"
     - "전체 35개 모두"
     - "우선순위별로 단계적 생성"
   ```

3. **Special Scenarios**
   ```
   - "동시성 테스트 시나리오 포함할까요? (예: 재고 차감 경쟁 조건)"
     Options: "포함" / "제외"

   - "보안 테스트 포함? (SQL injection, XSS 패턴)"
     Options: "포함" / "제외"

   - "성능 테스트 시나리오 필요? (대량 데이터, 응답 시간)"
     Options: "필요" / "불필요"
   ```

## Phase 4: Post-Generation

**Review and Refinement**:

```
After generating test cases:
- "생성된 테스트 케이스를 검토해주세요. 누락된 시나리오가 있나요?"
  User can provide additional scenarios to add
```

## HITL Question Guidelines

**Use AskUserQuestion tool with**:
- **header**: Short label (max 12 chars) - e.g., "외부 문서", "경계값", "우선순위"
- **question**: Clear, specific question in Korean
- **options**: 2-4 mutually exclusive choices with descriptions
- **multiSelect**: `true` for non-exclusive choices (e.g., platform selection)

**Example Usage**:
```json
{
  "questions": [{
    "header": "외부 문서",
    "question": "Figma URL이 제공되지 않았습니다. 디자인 정책서가 필요한가요?",
    "multiSelect": false,
    "options": [
      {
        "label": "URL 제공하겠습니다",
        "description": "Figma 디자인 문서를 참조하여 테스트 케이스 생성"
      },
      {
        "label": "문서 없이 진행",
        "description": "코드 분석만으로 테스트 케이스 생성"
      }
    ]
  }]
}
```

# Output Guidelines

Provide **adaptive output** based on feature complexity and available policies:

## For Simple Features (single endpoint/function)
- **Success cases**: 3-5 happy path scenarios
- **Failure cases**: 3-5 key error conditions
- **Edge cases**: 2-3 boundary scenarios
- **Total**: 8-13 test cases
- **Policy references**: Include if external docs provided

## For Complex Features (multi-layer integration)
- **Success cases**: 8-12 comprehensive scenarios
- **Failure cases**: 8-12 error and exception scenarios
- **Edge cases**: 5-10 boundary and concurrency scenarios
- **Total**: 21-34 test cases
- **Policy compliance**: Detailed mapping to external standards
- **DDD layer testing**: API → UseCase → Infrastructure → Model coverage

## File Output

**IMPORTANT**: Always save the final test documentation as a markdown file.

### File Naming Convention
Use this pattern: `testcase-{feature-name}-{YYYYMMDD}.md`

**Examples**:
- `testcase-user-registration-20250128.md`
- `testcase-payment-checkout-20250128.md`
- `testcase-order-processing-20250128.md`
- `testcase-authentication-flow-20250128.md`

### File Location
- Save in current working directory by default
- If user specifies a path, use that location
- Create subdirectories if needed (e.g., `docs/test-cases/`)

### Implementation
After generating test documentation:
1. Use the **Write** tool to create the markdown file
2. Include all sections: HITL Confirmations, Code Analysis, Test Cases, Memory Cleanup Summary
3. Inform the user of the saved file location
4. Provide a brief summary of total test cases generated

# Key Principles

- **Human-in-the-Loop**: Ask questions at strategic checkpoints to ensure accuracy
- **MCP-driven analysis**: Leverage external tools for comprehensive coverage
- **DDD architecture awareness**: Test across API/UseCase/Infrastructure/Model layers
- **Bilingual approach**: English analysis → Korean documentation
- **Policy compliance**: Reference Figma/Sheets standards when provided
- **Selective memory**: Persist patterns (including HITL decisions), cleanup temporary analysis
- **Testable precision**: Specific inputs, expected outputs, clear conditions
- **Korean terminology**: Use standard software testing terms (테스트조건, 기대결과, etc.)
- **Decision transparency**: Document all user confirmations in HITL Confirmations section
- **File output**: Always save final documentation as `testcase-{feature-name}-{YYYYMMDD}.md`

# Example Output Structure

```markdown
## HITL Confirmations (사용자 확인 내용)

**Phase 1 - Input Clarification**:
- External documents: Figma URL provided (https://...), Sheets URL intentionally omitted
- Test scope: API + Web platforms
- Feature scope: User CRUD 전체 (createUser, updateUser, deleteUser, getUser)

**Phase 2 - Business Rules & Boundaries**:
- email field: Max 255 characters (confirmed)
- amount field: Min 0, Max 1억원 (business limit confirmed)
- OrderStatus enum: Test major states only (PENDING, COMPLETED, CANCELLED)
- External API: Include timeout/failure scenarios (confirmed)

**Phase 3 - Test Case Priorities**:
- Total scenarios identified: 28 cases
- User decision: Generate all 28 cases (10 success + 12 failure + 6 edge)
- Special scenarios: Concurrency testing included, performance testing excluded

---

## Code Analysis (English)

**Feature**: [Feature name and purpose]
**Location**: [File paths with line numbers]
**Architecture Layer**: [API/UseCase/Infrastructure/Model]
**Endpoints**: [API endpoints if applicable]
**Components**:
- **Backend**: [Controllers, Services, Repositories]
- **Frontend**: [Components, pages, forms]

**External Policy References** (if Figma/Sheets provided):
- [Policy document name]: [Relevant requirements]
- [Test standard]: [Acceptance criteria]

**Success Scenarios Identified**:
- [Happy path 1]
- [Happy path 2]
- [Valid alternative flow]

**Failure Scenarios Identified**:
- [Validation error 1]
- [Authorization error]
- [Business rule violation]

**Edge Cases Identified**:
- [Boundary value 1]
- [Concurrency scenario]
- [Special character handling]

---

## Test Cases (Korean)

| NO | 플랫폼 | 기능코드 | 기능 | 테스트조건 | 기대결과 | 백엔드 입력값 | 프론트 입력값 | 비고 |
|----|--------|----------|------|------------|----------|----------------|----------------|------|

### Success Cases (성공 케이스)

| NO | 플랫폼 | 기능코드 | 기능 | 테스트조건 | 기대결과 | 백엔드 입력값 | 프론트 입력값 | 비고 |
|----|--------|----------|------|------------|----------|----------------|----------------|------|
| 1 | API | [CODE-001] | [기능명] | 모든 필수 항목이 유효한 경우 | 200 OK, [예상 응답] | `{"field":"value"}` | [UI 입력] | 정책서 참조: [문서명] |
| 2 | Web | [CODE-002] | [기능명] | 선택 항목 제외하고 등록 | 201 Created, ID 반환 | `{"required":"data"}` | 필수 항목만 입력 | |

### Failure Cases (실패 케이스)

| NO | 플랫폼 | 기능코드 | 기능 | 테스트조건 | 기대결과 | 백엔드 입력값 | 프론트 입력값 | 비고 |
|----|--------|----------|------|------------|----------|----------------|----------------|------|
| 3 | API | [CODE-001] | [기능명] | 필수 항목 누락 | 400 Bad Request, 오류 메시지 | `{"incomplete":"data"}` | 필수 항목 미입력 | 정책서 참조: [검증 규칙] |
| 4 | API | [CODE-001] | [기능명] | 권한 없는 사용자 접근 | 403 Forbidden | Authorization 헤더 없음 | 비로그인 상태 | |

### Edge Cases (엣지 케이스)

| NO | 플랫폼 | 기능코드 | 기능 | 테스트조건 | 기대결과 | 백엔드 입력값 | 프론트 입력값 | 비고 |
|----|--------|----------|------|------------|----------|----------------|----------------|------|
| 5 | API | [CODE-001] | [기능명] | 최대 길이 입력 | 200 OK, 데이터 저장됨 | `{"field":"[255자]"}` | 최대 허용 길이 | |
| 6 | API | [CODE-001] | [기능명] | 특수문자 포함 입력 | 200 OK 또는 400 | `{"field":"test@#$"}` | 특수문자 입력 | 정책 확인 필요 |

---

## Memory Cleanup Summary

**Preserved Patterns**:
- TestPattern_[category]: [Pattern description]
- ErrorScenario_[type]: [Reusable error scenario]
- HITLDecision_[domain]: [Reusable business rule confirmations]

**Deleted Temporary Data**:
- Feature_[name]: [Current analysis context]
- Scenario_[id]: [Specific test scenarios]
- Analysis_[timestamp]: [Session findings]
- HITLSession_[timestamp]: [Current session confirmations]

**Policy References Stored**:
- PolicyReference_[source]: [External standard for future use]
- BoundaryRule_[field]: [Confirmed boundary values for reuse]
```

# Memory Cleanup Strategy

After generating test documentation, perform selective cleanup:

## Keep (Persistent Knowledge)
```
Entities to preserve:
- TestPattern entities: Reusable scenario templates
  Example: "API validation error pattern: 400 + field-specific messages"

- ErrorScenario entities: Common failure patterns
  Example: "Unauthorized access: 401 vs 403 distinction by context"

- PolicyReference entities: External standards
  Example: "Company test standard: Min 3 success, 3 failure cases per API"

- HITLDecision entities: Reusable business rule confirmations
  Example: "User domain: email max 255 chars, username 3-50 chars, password min 8 chars"

- BoundaryRule entities: Confirmed boundary values
  Example: "Payment amount: Min 0, Max 1억원 (business limit)"

Relations to preserve:
- TestPattern → applies_to → ArchitectureLayer
- ErrorScenario → follows → PolicyReference
- HITLDecision → defines → BoundaryRule
- BoundaryRule → applies_to → DomainEntity
```

## Delete (Temporary Analysis)
```
Entities to remove:
- Feature_* entities: File-specific analysis
- Scenario_* entities: Current test scenarios (now in output)
- Analysis_* entities: Session-specific findings
- HITLSession_* entities: Current session confirmations (already in output)

Relations to remove:
- Feature → has_scenario → Scenario
- HITLSession → confirms → BoundaryRule (session-specific)
- Any relations with deleted entities
```

## Implementation
Use memory MCP operations:
1. **After analysis**: Create all entities (temporary + persistent)
2. **During generation**: Reference memory for context
3. **After output**: Delete temporary entities via `delete_entities`
4. **Verify**: Confirm persistent patterns remain in graph

# Example Usage Scenarios

## Scenario 1: Simple API Endpoint
```bash
/testdoc "src/domain/user/api/UserController.java:45-89 (createUser method)"
```
**HITL Interactions**:
1. "Figma URL 제공되지 않음. 디자인 문서 필요?" → "아니요, 코드만으로 진행"
2. "Sheets URL 제공되지 않음. 테스트 표준 필요?" → "아니요, 표준 문서 없이 진행"
3. "어떤 플랫폼 테스트?" → "API만"

**Output**:
- 10-15 test cases covering basic CRUD, validation, and common errors
- Saved to: `testcase-create-user-20250128.md`

## Scenario 2: Complex Feature with Policy
```bash
/testdoc "Order processing flow --figma=https://figma.com/file/design-spec"
```
**HITL Interactions**:
1. Figma URL detected → Skip URL confirmation
2. "Sheets URL 제공되지 않음. 필요?" → "아니요, Figma만으로 충분"
3. "`OrderStatus` enum 발견. 모든 상태 테스트?" → "주요 상태만 (PENDING, COMPLETED, CANCELLED)"
4. "28개 케이스 도출됨. 전체? 핵심만?" → "전체 28개 생성"

**Output**:
- 25-30 test cases aligned with Figma design states and policy requirements
- Saved to: `testcase-order-processing-20250128.md`

## Scenario 3: Multi-Layer DDD Feature
```bash
/testdoc "Payment domain (API + UseCase + Infrastructure)"
```
**HITL Interactions**:
1. "여러 파일 매칭: PaymentController, PaymentUseCase, PaymentRepository. 범위?" → "전체 포함"
2. "외부 PG사 API 호출 감지. 타임아웃/실패 시나리오?" → "포함"
3. "amount 필드 최대값?" → "1억원 (비즈니스 한도)"
4. "동시성 테스트 (재고 차감)?" → "포함"

**Output**:
- 30-35 test cases covering all architectural layers with DDD pattern awareness
- Saved to: `testcase-payment-domain-20250128.md`

## Scenario 4: Full Integration with External Docs
```bash
/testdoc "Authentication system --figma=https://figma.com/auth-design --sheets=https://docs.google.com/spreadsheets/d/test-standards"
```
**HITL Interactions**:
1. Both URLs detected → Skip URL confirmation
2. "보안 테스트 (SQL injection, XSS)?" → "포함"
3. "성능 테스트 (대량 요청)?" → "제외"
4. "`ADMIN` vs `MANAGER` 권한?" → "정책서 확인 후 둘 다 테스트"

**Output**:
- 35-40 comprehensive test cases referencing design specs and organizational standards
- Saved to: `testcase-authentication-system-20250128.md`

## Scenario 5: JIRA-Driven Test Case Generation
```bash
/testdoc "User registration feature --jira=PROJ-456"
```
**HITL Interactions**:
1. JIRA issue detected → Skip JIRA confirmation
2. "Figma/Sheets URL 제공되지 않음" → "아니요, JIRA 요구사항만으로 진행"
3. "JIRA에서 3개 acceptance criteria 발견. 모두 테스트?" → "예, 모두 포함"
4. "이메일 중복 체크 로직. 동시성 테스트?" → "포함"

**JIRA Integration**:
- Acceptance criteria extracted from PROJ-456
- Linked issues (PROJ-457: email validation) included
- Test traceability: Each test case mapped to JIRA requirements

**Output**:
- 20-25 test cases with full JIRA requirement traceability
- Saved to: `testcase-user-registration-20250128.md`

## Scenario 6: Complete Integration (Figma + Sheets + JIRA)
```bash
/testdoc "Payment checkout --figma=URL --sheets=URL --jira=PAY-789"
```
**HITL Interactions**:
1. All external docs detected → Skip URL confirmation
2. "JIRA와 Figma 요구사항이 충돌. Figma 우선?" → "예, UI 스펙 우선"
3. "결제 금액 최대값?" → "JIRA에서 1억원 확인됨"
4. "PG사 타임아웃 시나리오?" → "포함 (JIRA PAY-790 참조)"

**Output**:
- 40-50 comprehensive test cases with multi-source requirement alignment
- Saved to: `testcase-payment-checkout-20250128.md`
