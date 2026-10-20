# Test Plan: Runtime Contract Kernel and Consumer Boundary

| Requirement | Test level | Required evidence |
| --- | --- | --- |
| RCK-001 | Python CLI + Nix contract | versioned `validate`/`doctor`/`verify` JSON and module contract |
| RCK-002 | architecture test | stable module/port dependency direction |
| RCK-003 | unit + native probe | desired/applied/observed status and truthful unsupported state |
| RCK-004 | Rust table/property + adapter | deny dominance and `ALLOW/ASK/DENY` transport mapping |
| RCK-005 | Rust/adversarial integration | expiry, revoke, identity, symlink/path, DNS/redirect/port |
| RCK-006 | differential + Nix matrix | Python/Rust parity, one authority, supported platforms |
| RCK-007 | provider contract/native | apply/revoke/observe capability tied to version |
| RCK-008 | consumer Nix | stable URL, lock revision, module evaluation and activation build |

Focused checks run before full `just test` and `nix flake check`. Performance
work requires a reproducible baseline; the initial correctness slice adds no
optimization without a measured bottleneck.
