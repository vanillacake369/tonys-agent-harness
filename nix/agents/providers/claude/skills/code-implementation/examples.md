# Code Implementation Examples

This file contains detailed code examples referenced from the main SKILL.md file.

## Naming Convention Matching

### JavaScript Example
```javascript
// ✅ Learn and apply existing pattern
// Found in codebase:
function getUserById(id) {
  return users.find(u => u.id === id);
}

function getOrderById(id) {
  return orders.find(o => o.id === id);
}

// New code matches:
function getProductById(id) {
  return products.find(p => p.id === id);
}

// ❌ Don't impose different pattern:
function fetchProduct(id) { ... }  // Wrong - breaks convention
```

## Structural Pattern Matching

### Python Example
```python
# ✅ Follow existing structure
# Found in codebase:
class UserService:
    def __init__(self, repository, cache):
        self.repository = repository
        self.cache = cache

    def get_user(self, id):
        cached = self.cache.get(f"user:{id}")
        if cached:
            return cached

        user = self.repository.find_by_id(id)
        self.cache.set(f"user:{id}", user)
        return user

# New code matches structure:
class ProductService:
    def __init__(self, repository, cache):
        self.repository = repository
        self.cache = cache

    def get_product(self, id):
        cached = self.cache.get(f"product:{id}")
        if cached:
            return cached

        product = self.repository.find_by_id(id)
        self.cache.set(f"product:{id}", product)
        return product
```

## Import Pattern Matching

### TypeScript Example
```typescript
// ✅ Match existing import organization
// Found in existing files:
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { User } from '../entities/user.entity';
import { CreateUserDto } from '../dto/create-user.dto';

@Injectable()
export class UserService {
  constructor(
    @InjectRepository(User)
    private userRepository: Repository<User>,
  ) {}
}

// New code follows same pattern:
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { Product } from '../entities/product.entity';
import { CreateProductDto } from '../dto/create-product.dto';

@Injectable()
export class ProductService {
  constructor(
    @InjectRepository(Product)
    private productRepository: Repository<Product>,
  ) {}
}
```

## Error Handling Pattern Matching

### Java Example
```java
// ✅ Match existing error handling
// Found in UserService.java:
public User findById(Long id) {
    return repository.findById(id)
        .orElseThrow(() -> new EntityNotFoundException(
            ErrorCode.USER_NOT_FOUND,
            "User not found with id: " + id
        ));
}

// New code in OrderService.java matches:
public Order findById(Long id) {
    return repository.findById(id)
        .orElseThrow(() -> new EntityNotFoundException(
            ErrorCode.ORDER_NOT_FOUND,
            "Order not found with id: " + id
        ));
}
```

### Go Example
```go
// ✅ Match existing error patterns
// Found in user_service.go:
func (s *UserService) GetUser(ctx context.Context, id string) (*User, error) {
    user, err := s.repo.FindByID(ctx, id)
    if err != nil {
        if errors.Is(err, ErrNotFound) {
            return nil, fmt.Errorf("user not found: %w", err)
        }
        return nil, fmt.Errorf("failed to get user: %w", err)
    }
    return user, nil
}

// New code in product_service.go matches:
func (s *ProductService) GetProduct(ctx context.Context, id string) (*Product, error) {
    product, err := s.repo.FindByID(ctx, id)
    if err != nil {
        if errors.Is(err, ErrNotFound) {
            return nil, fmt.Errorf("product not found: %w", err)
        }
        return nil, fmt.Errorf("failed to get product: %w", err)
    }
    return product, nil
}
```

## Library and Framework Integration

### Using Existing Libraries (Python)
```python
# ✅ Study how existing code uses libraries
# Found in existing services:
from app.utils.logger import get_logger
from app.utils.validator import validate_email

logger = get_logger(__name__)

class UserService:
    def create_user(self, email, name):
        if not validate_email(email):
            logger.error(f"Invalid email: {email}")
            raise ValueError("Invalid email format")

        logger.info(f"Creating user: {email}")
        # ... create user

# New code uses same approach:
from app.utils.logger import get_logger
from app.utils.validator import validate_product_code

logger = get_logger(__name__)

class ProductService:
    def create_product(self, code, name):
        if not validate_product_code(code):
            logger.error(f"Invalid product code: {code}")
            raise ValueError("Invalid product code format")

        logger.info(f"Creating product: {code}")
        # ... create product

# ❌ Don't introduce different logging:
import logging  # Wrong - project has custom logger
```

### Dependency Consistency (Go)
```go
// ✅ Use existing dependencies
// Found in existing handlers:
import (
    "github.com/gin-gonic/gin"
    "project/internal/service"
    "project/internal/middleware"
)

func NewUserHandler(userService service.UserService) *UserHandler {
    return &UserHandler{service: userService}
}

func (h *UserHandler) GetUser(c *gin.Context) {
    // Implementation
}

// New handler uses same:
import (
    "github.com/gin-gonic/gin"
    "project/internal/service"
    "project/internal/middleware"
)

func NewProductHandler(productService service.ProductService) *ProductHandler {
    return &ProductHandler{service: productService}
}

func (h *ProductHandler) GetProduct(c *gin.Context) {
    // Implementation
}

// ❌ Don't add new HTTP framework:
import "github.com/gorilla/mux"  // Wrong - project uses Gin
```

## Comment Style Matching

### Rust Example
```rust
// ✅ Match existing comment patterns
// Found in existing code:

/// Validates user credentials and returns auth token.
///
/// # Arguments
/// * `username` - The user's username
/// * `password` - The user's password
///
/// # Returns
/// * `Result<Token, AuthError>` - Auth token or error
pub fn authenticate(username: &str, password: &str) -> Result<Token, AuthError> {
    // Implementation
}

// New code matches style:

/// Validates product availability and reserves inventory.
///
/// # Arguments
/// * `product_id` - The product identifier
/// * `quantity` - Requested quantity
///
/// # Returns
/// * `Result<Reservation, InventoryError>` - Reservation or error
pub fn reserve_inventory(product_id: &str, quantity: u32) -> Result<Reservation, InventoryError> {
    // Implementation
}
```

## Formatting and Spacing

### JavaScript Example
```javascript
// ✅ Match exact formatting
// Found in existing code (2 spaces, no semicolons):
function processUser(user) {
  const validated = validateUser(user)
  const enriched = enrichData(validated)
  return saveUser(enriched)
}

// New code matches formatting:
function processOrder(order) {
  const validated = validateOrder(order)
  const enriched = enrichData(validated)
  return saveOrder(enriched)
}

// ❌ Don't use different style:
function processOrder(order) {
    const validated = validateOrder(order);  // Wrong indentation and semicolons
    const enriched = enrichData(validated);
    return saveOrder(enriched);
}
```

## Test Pattern Matching

### Python Example
```python
# ✅ Follow existing test structure
# Found in test_user_service.py:
class TestUserService:
    @pytest.fixture
    def service(self, mock_repository):
        return UserService(mock_repository)

    def test_get_user_success(self, service):
        # Arrange
        user_id = 1
        expected_user = User(id=user_id, name="Test")

        # Act
        result = service.get_user(user_id)

        # Assert
        assert result == expected_user

    def test_get_user_not_found(self, service):
        # Arrange
        user_id = 999

        # Act & Assert
        with pytest.raises(UserNotFoundError):
            service.get_user(user_id)

# New test_product_service.py matches:
class TestProductService:
    @pytest.fixture
    def service(self, mock_repository):
        return ProductService(mock_repository)

    def test_get_product_success(self, service):
        # Arrange
        product_id = 1
        expected_product = Product(id=product_id, name="Test")

        # Act
        result = service.get_product(product_id)

        # Assert
        assert result == expected_product

    def test_get_product_not_found(self, service):
        # Arrange
        product_id = 999

        # Act & Assert
        with pytest.raises(ProductNotFoundError):
            service.get_product(product_id)
```

## Anti-Patterns Examples

### Wrong: Imposing External Style
```javascript
// ❌ Wrong - introducing async/await when project uses promises
const result = await service.execute();

// ✅ Right - following project's promise pattern
const result = service.execute().then(data => data);
```

### Wrong: Adding Unnecessary Dependencies
```python
# ❌ Wrong - project uses httpx
import requests
response = requests.get(url)

# ✅ Right - using project's HTTP client
from app.http import client
response = client.get(url)
```

### Wrong: Reinventing Existing Utilities
```java
// ❌ Wrong - creating own date formatter
SimpleDateFormat formatter = new SimpleDateFormat("yyyy-MM-dd");
String formatted = formatter.format(date);

// ✅ Right - using project's date utility
String formatted = DateUtils.formatDate(date);
```

### Wrong: Breaking Architectural Boundaries
```java
// ❌ Wrong - API layer directly accessing database
@RestController
public class UserController {
    @Autowired
    private UserRepository repository;  // Skips service layer!

    @GetMapping("/users/{id}")
    public User getUser(@PathVariable Long id) {
        return repository.findById(id);  // Wrong layer access
    }
}

// ✅ Right - following layered architecture
@RestController
public class UserController {
    @Autowired
    private UserService service;  // Uses service layer

    @GetMapping("/users/{id}")
    public User getUser(@PathVariable Long id) {
        return service.findById(id);  // Correct layer access
    }
}
```
