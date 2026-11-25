# Engineering and infrastructure principles

- Use domain/value objects only when they simplify validation, self-regulation or useful behavior.
- Respect requirements, infrastructure and existing contracts. Prefer early success/failure and guard clauses.
- Production if/for/range nesting <= 2; flat modules, managed source directories <= 2 levels.
- Prioritize SRP/DIP, avoid over-splitting interfaces; minimize abstraction.
- Explicit errors; avoid mutable shared state; use OS locks and value structs where appropriate.
- At most five declared parameters; group cohesive inputs into a request DTO.
- Meaningful named booleans (`var needsInit = ...` for nontrivial conditions); prefer vertical code.
- 120 columns, gofmt, C-style role-feature filenames; Go mixedCaps/PascalCase identifiers.
- Korean multiline intent comments for core state transitions. Explain why, invariants and failure behavior.
- Keep tests beside code, with synthetic fixtures only. Standard tool/skill resource layouts are exceptions.

## Invariants

Agent decides; Contract declares; Tool executes; Nix provisions reviewed public dependencies; Go reconciles.
Never auto-install plugins, OAuth, hooks or execute user Skill scripts as validation.
No plaintext or age identity in Git, Nix or CI. Use the reviewed public manifest before Nix evaluation.
No automatic Source pin changes or provider connections. Preserve existing provider files and unmanaged links.
Validate before mutation; preserve unchanged ciphertext and active generations on candidate failure.
Plan must not change the archive or active runtime; temporary work and operation metadata may be used.
Status must not create user state. Explicit editing holds the operation lock; external editors require coordination.
Vault commit and Runtime activation are separate transactions; never claim all-or-nothing deployment.
Single Cobra CLI. Never report skipped checks as passing.
Do not weaken security validation or tests to make a build pass.
