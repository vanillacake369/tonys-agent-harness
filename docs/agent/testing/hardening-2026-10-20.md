# TDD and TODO: 2026-10-20 Harness Usability Hardening

## Red

- [x] AH-261020-001: prove local `git commit`, declared Nix commands, and
  rootless test-container commands pass the shared execution classifier while
  push and host-changing operations remain gated.
- [x] AH-261020-002: prove search text containing sensitive words passes, while
  actual sensitive paths still fail.
- [x] AH-261020-003: prove benign command substitution passes and nested push or
  destructive operations remain blocked.
- [x] AH-261020-004: prove a dead lifecycle lock is recovered and a live lock is
  preserved.
- [x] AH-261020-005: prove an explicit pre-stage responsibility plan rejects
  overlaps and unassigned files, then verifies exact commit bindings.
- [x] AH-261020-006: prove exports use native formats: Codex/Claude/Kiro
  `SKILL.md` bundles and Gemini TOML commands, with no Kiro Markdown workflow or
  Gemini Markdown command masquerading as a supported surface.
- [x] AH-261020-006: prove Home Manager activation maps Codex, Claude, Kiro,
  and Gemini generated surfaces to provider-native roots without replacing
  unmanaged entries.

## Green

- [x] Implement the smallest hook/classifier changes satisfying Red tests.
- [x] Add owner-aware lifecycle locking with deterministic stale recovery.
- [x] Replace filename-derived staged commit grouping with explicit pre-stage
  responsibility plans.
- [x] Add provider activation to the harness Home Manager module and remove the
  consumer-owned Codex-only activation.
- [x] Record installed-provider native checks separately from static export
  checks; report missing Claude/Gemini CLIs as `UNAVAILABLE`, never `PASS`.

## Refactor and Verify

- [x] Keep provider path mapping in one contract.
- [x] Run focused Python/Bats/Nix checks.
- [x] Run the full harness suite and `nix flake check`.
- [x] Independently review policy boundaries, user-file preservation, and
  provider discovery.
- [x] Create SRP commits with requirement and verification evidence.
- [ ] Push the harness, update the `tonys-nix` pin, verify, and apply Home
  Manager.
