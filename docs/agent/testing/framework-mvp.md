# Test Specification: Framework MVP

| Requirement | Test evidence |
|---|---|
| FR-001 | schema version, malformed manifest, init no-overwrite tests |
| FR-002 | policy weakening rejection tests |
| FR-003 | four preset normalization tests |
| FR-004 | provider capability and unsupported enforcement tests |
| FR-005 | plan purity, deterministic export, atomic output tests |
| FR-006 | exact skill and command inventory tests |
| FR-007 | tamper and stale-output verification tests |
| FR-008 | flake evaluation/check |
| FR-009 | source repository preservation and extraction report |
| FR-010 | instruction export equality, stale digest, and provider drift gate tests |

Tests use temporary directories and must not mutate provider home directories.
