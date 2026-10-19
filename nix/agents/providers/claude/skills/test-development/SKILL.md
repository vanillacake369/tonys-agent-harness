---
name: test-development
description: Create comprehensive test suites by discovering and adapting to any testing framework, following project test patterns and ensuring robust coverage. Use when writing tests, improving coverage, validating functionality. Triggers: 'test', 'coverage', 'unit test', 'integration test', 'E2E', 'spec', '테스트', '커버리지', '단위 테스트', '통합 테스트', '테스트 작성', working with *.test.*, *.spec.*, test/, __tests__/.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(test:*)
  - Bash(go test:*)
  - Bash(npm test:*)
  - Bash(pytest:*)
  - Bash(jest:*)
---

# Test Development Methodology

This skill enables creation of comprehensive, project-appropriate tests by learning from existing test patterns and conventions.

**Leverages:** [codebase-analysis] skill for discovering testing frameworks and patterns.

## Testing Philosophy

### Pattern-Driven Testing
- **Learn from existing tests**: Match structure, naming, and assertions
- **Framework agnostic**: Adapt to any testing framework or methodology
- **Project conventions**: Follow discovered test organization
- **Quality first**: Robust coverage and validation

### Test Coverage Principles
- Test what matters most for the project
- Follow project's testing pyramid (unit/integration/e2e ratio)
- Match existing coverage standards
- Ensure tests are maintainable and readable
## Testing Workflow

**중요: 본 스킬을 사용할 때 모든 응답의 최상단에 `[PHASE: EXECUTION]`을 명시하라.**

### Phase 1: Test Environment Discovery
... (기존 내용) ...

### Phase 2: Test Planning (Mandatory)
... (기존 내용) ...

### Phase 3: Integration Oracle (통합 실행 증명)
구현이 완료된 후, 단순히 단위 테스트 통과에 만족하지 마라:
1. **Live Execution**: `run_shell_command`를 사용하여 실제 환경에서 전체 기능을 통합 실행한다.
2. **Evidence Collection**: 실행 결과 로그, 터미널 출력, 혹은 생성된 파일의 내용을 직접 확인하고 보고서에 포함한다.
3. **Exit Condition**: 실제 실행 결과가 포함된 통합 검증 리포트를 사용자에게 제출해야만 "작업 완료"로 간주한다.

Create tests matching patterns:
1. Follow discovered test structure exactly
2. Use same testing libraries and utilities
3. Match naming and organization conventions
4. Apply consistent assertion patterns
5. Integrate with existing test data/fixtures

## Framework Detection and Adaptation

### JavaScript/TypeScript

```typescript
// Detected: Jest framework (from jest.config.js, *.test.ts)
// Match existing pattern:

describe('ProductService', () => {
  let service: ProductService;
  let mockRepository: jest.Mocked<ProductRepository>;

  beforeEach(() => {
    mockRepository = {
      findById: jest.fn(),
      save: jest.fn(),
    } as any;
    service = new ProductService(mockRepository);
  });

  it('should return product when found', async () => {
    // Arrange
    const productId = 1;
    const expectedProduct = { id: productId, name: 'Test' };
    mockRepository.findById.mockResolvedValue(expectedProduct);

    // Act
    const result = await service.getProduct(productId);

    // Assert
    expect(result).toEqual(expectedProduct);
    expect(mockRepository.findById).toHaveBeenCalledWith(productId);
  });
});
```

### Python

```python
# Detected: pytest framework (from pytest.ini, conftest.py)
# Match existing pattern:

import pytest
from services.product_service import ProductService

class TestProductService:
    @pytest.fixture
    def service(self, mock_repository):
        return ProductService(mock_repository)

    @pytest.fixture
    def mock_repository(self, mocker):
        return mocker.Mock()

    def test_get_product_returns_product_when_found(self, service, mock_repository):
        # Arrange
        product_id = 1
        expected_product = Product(id=product_id, name="Test")
        mock_repository.find_by_id.return_value = expected_product

        # Act
        result = service.get_product(product_id)

        # Assert
        assert result == expected_product
        mock_repository.find_by_id.assert_called_once_with(product_id)
```

### Go

```go
// Detected: Standard go test framework (from *_test.go files)
// Match existing pattern:

package product

import (
    "testing"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

type MockRepository struct {
    mock.Mock
}

func (m *MockRepository) FindByID(id int) (*Product, error) {
    args := m.Called(id)
    return args.Get(0).(*Product), args.Error(1)
}

func TestProductService_GetProduct_ReturnsProductWhenFound(t *testing.T) {
    // Arrange
    mockRepo := new(MockRepository)
    service := NewProductService(mockRepo)
    productID := 1
    expectedProduct := &Product{ID: productID, Name: "Test"}
    mockRepo.On("FindByID", productID).Return(expectedProduct, nil)

    // Act
    result, err := service.GetProduct(productID)

    // Assert
    assert.NoError(t, err)
    assert.Equal(t, expectedProduct, result)
    mockRepo.AssertExpectations(t)
}
```

### Java

```java
// Detected: JUnit 5 + Mockito (from @Test, @ExtendWith annotations)
// Match existing pattern:

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.mockito.Mock;
import org.mockito.InjectMocks;
import org.mockito.junit.jupiter.MockitoExtension;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

    @Mock
    private ProductRepository productRepository;

    @InjectMocks
    private ProductService productService;

    @Test
    @DisplayName("Should return product when found")
    void getProduct_WhenProductExists_ReturnsProduct() {
        // Arrange
        Long productId = 1L;
        Product expectedProduct = Product.builder()
            .id(productId)
            .name("Test Product")
            .build();
        when(productRepository.findById(productId))
            .thenReturn(Optional.of(expectedProduct));

        // Act
        Product result = productService.getProduct(productId);

        // Assert
        assertThat(result).isEqualTo(expectedProduct);
        verify(productRepository).findById(productId);
    }
}
```

## Test Pattern Matching

### Test Naming Conventions

```python
# Learn from existing tests:
# Pattern found: test_methodName_condition_expectedResult

# ✅ Match the pattern:
def test_createProduct_withValidData_returnsProduct():
    pass

def test_createProduct_withDuplicateName_raisesValidationError():
    pass

def test_createProduct_withNegativePrice_raisesValidationError():
    pass
```

### Test Organization

```typescript
// Learn from existing tests:
// Pattern found: Describe blocks for class, nested for methods

// ✅ Match the structure:
describe('OrderService', () => {
  describe('createOrder', () => {
    it('should create order with valid data', () => {});
    it('should throw error with invalid customer', () => {});
    it('should throw error with empty items', () => {});
  });

  describe('cancelOrder', () => {
    it('should cancel order when pending', () => {});
    it('should throw error when already shipped', () => {});
  });
});
```

### Assertion Style Matching

```javascript
// Learn from existing tests:
// Pattern found: expect() with matcher methods

// ✅ Match assertion style:
expect(result).toBe(expected);
expect(array).toHaveLength(3);
expect(object).toEqual({ id: 1, name: 'Test' });
expect(fn).toHaveBeenCalledWith(arg1, arg2);

// ❌ Don't use different style:
assert.equal(result, expected);  // Wrong - project uses expect()
```

### Test Data Management

```python
# Learn from existing tests:
# Pattern found: Fixtures in conftest.py

# ✅ Follow existing fixture pattern:
# In conftest.py
@pytest.fixture
def valid_product_data():
    return {
        "name": "Test Product",
        "price": 99.99,
        "category": "Electronics"
    }

# In test file
def test_create_product_success(valid_product_data):
    product = create_product(valid_product_data)
    assert product.name == valid_product_data["name"]
```

## Coverage Strategies

### Unit Testing

```java
// Focus on single unit isolation
// Test all paths: happy path + error cases + edge cases

@Test
void calculateDiscount_RegularCustomer_Returns10Percent() {
    // Test happy path
}

@Test
void calculateDiscount_NullCustomer_ThrowsException() {
    // Test error case
}

@Test
void calculateDiscount_ZeroAmount_ReturnsZero() {
    // Test edge case
}
```

### Integration Testing

```typescript
// Test component interactions
// Use project's integration test patterns

describe('OrderController Integration', () => {
  let app: INestApplication;
  let orderRepository: Repository<Order>;

  beforeAll(async () => {
    // Setup test database
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = module.createNestApplication();
    await app.init();
  });

  it('should create order end-to-end', async () => {
    const response = await request(app.getHttpServer())
      .post('/orders')
      .send({ customerId: 1, items: [...] })
      .expect(201);

    expect(response.body).toHaveProperty('id');
  });
});
```

### End-to-End Testing

```python
# Detected: Selenium/Playwright for E2E
# Match existing E2E patterns

def test_user_can_complete_purchase_flow(browser):
    # Navigate to product page
    browser.goto("/products/1")

    # Add to cart
    browser.click("#add-to-cart")

    # Proceed to checkout
    browser.click("#checkout")

    # Fill shipping info
    browser.fill("#shipping-address", "123 Main St")

    # Complete purchase
    browser.click("#complete-order")

    # Verify success
    assert browser.is_visible("#order-confirmation")
```

## Test Quality Standards

### AAA Pattern (Arrange-Act-Assert)

```go
func TestOrderService_ProcessOrder(t *testing.T) {
    // Arrange
    order := &Order{
        ID: 1,
        CustomerID: 100,
        Items: []Item{{ProductID: 1, Quantity: 2}},
    }
    mockRepo := new(MockRepository)
    service := NewOrderService(mockRepo)

    // Act
    result, err := service.ProcessOrder(order)

    // Assert
    assert.NoError(t, err)
    assert.Equal(t, OrderStatus.Processing, result.Status)
}
```

### Test Independence

```python
# ✅ Each test is independent
class TestUserService:
    def test_create_user(self):
        service = UserService()  # Fresh instance
        user = service.create_user({"email": "test@example.com"})
        assert user.email == "test@example.com"

    def test_delete_user(self):
        service = UserService()  # Fresh instance
        # Test doesn't depend on test_create_user
        pass
```

### Clear Test Failures

```typescript
// ✅ Descriptive assertions that help debug failures
it('should calculate correct total with tax', () => {
  const result = calculator.calculateTotal(100);

  // Good: Clear what's being tested
  expect(result.subtotal).toBe(100);
  expect(result.tax).toBe(10);
  expect(result.total).toBe(110);

  // ❌ Bad: Unclear which part failed
  // expect(result).toEqual({ subtotal: 100, tax: 10, total: 110 });
});
```

## Test Execution Integration

### Match Project Test Commands

```bash
# Detect from package.json, Makefile, justfile, etc.

# Found in package.json:
"scripts": {
  "test": "jest",
  "test:watch": "jest --watch",
  "test:coverage": "jest --coverage"
}

# Ensure new tests work with existing commands
npm test  # Must pass
npm run test:coverage  # Must maintain coverage
```

### CI/CD Integration

```yaml
# Learn from existing .github/workflows/test.yml
# Ensure new tests integrate with CI pipeline

# Existing CI runs:
# - npm test
# - npm run lint
# - npm run build

# New tests must pass all these checks
```

## Quality Checklist

Before finalizing tests:
- [ ] Test structure matches existing tests
- [ ] Naming follows project conventions
- [ ] Assertions use same style as project
- [ ] Test data follows existing patterns
- [ ] All tests pass when run
- [ ] Tests are independent and isolated
- [ ] Test failures provide clear diagnostics
- [ ] Coverage meets project standards
- [ ] Tests integrate with existing CI/CD

## Anti-Patterns to Avoid

❌ **Testing Implementation Details**:
```javascript
// Wrong - testing internal state
expect(service.internalCache.size).toBe(3);

// Right - testing behavior
expect(service.getUsers()).toHaveLength(3);
```

❌ **Fragile Tests**:
```python
# Wrong - breaks with minor changes
assert user.created_at == datetime(2024, 1, 1, 12, 30, 45)

# Right - tests what matters
assert user.created_at is not None
assert user.created_at <= datetime.now()
```

❌ **Dependent Tests**:
```java
// Wrong - tests depend on order
@Test
void test1_createUser() { ... }

@Test
void test2_updateUser() {  // Depends on test1
    // Breaks if test1 fails or runs separately
}
```

---

**Remember**: Great tests are readable, maintainable, and follow project patterns. Use [codebase-analysis] to discover testing conventions, then create tests that feel native to the project's testing culture.

## Mandatory: Tone & Reference Policy

- 모든 기술적 주장/판단에 출처 명시 (공식 문서 URL, GitHub issue, RFC 등)
- 출처 없는 주장은 "출처 미확인 — 검증 필요"로 표기
- "~일 수 있습니다", "아마도", "대체로" 등 hedging 표현 금지. 확인 상태를 명시.
- 톤: 간결, 사실 중심. 불필요한 수식어 배제.

## Mandatory: Code Principles (테스트 작성 시 적용)

- TDD 사이클 엄수: Red → Green → Refactor
- SSoT: 테스트 데이터 원천 하나로 관리 (fixture/factory)
- SRP: 하나의 테스트는 하나의 동작만 검증
- DDD: 도메인 용어로 테스트 네이밍
- 엣지케이스 필수: happy path + error cases + boundary conditions

## Mandatory: Integration Verification

테스트 작성 완료 후:
1. 전체 테스트 스위트 실행 — 신규 + 기존 모두 통과
2. 커버리지 확인 (프로젝트 기준 충족)
3. CI 파이프라인 호환 확인

완료 보고 형식:
```
[COMPLETE] Tests: {pass}/{total}, Coverage: {%}, New tests: {count}
```
