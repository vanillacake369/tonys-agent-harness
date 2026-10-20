# TDD and TODO: 2026-10-20 Harness Usability Hardening

## Red

- [ ] AH-261020-001: prove local `git commit`, declared Nix commands, and
  rootless test-container commands pass the shared execution classifier while
  push and host-changing operations remain gated.
- [ ] AH-261020-002: prove search text containing sensitive words passes, while
  actual sensitive paths still fail.
- [ ] AH-261020-003: prove benign command substitution passes and nested push or
  destructive operations remain blocked.
- [ ] AH-261020-004: prove a dead lifecycle lock is recovered and a live lock is
  preserved.
- [ ] AH-261020-005: prove an explicit pre-stage responsibility plan rejects
  overlaps and unassigned files, then verifies exact commit bindings.
- [ ] AH-261020-006: prove exports use native formats: Codex/Claude/Kiro
  `SKILL.md` bundles and Gemini TOML commands, with no Kiro Markdown workflow or
  Gemini Markdown command masquerading as a supported surface.
- [ ] AH-261020-006: prove Home Manager activation maps Codex, Claude, Kiro,
  and Gemini generated surfaces to provider-native roots without replacing
  unmanaged entries.

## Green

- [ ] Implement the smallest hook/classifier changes satisfying Red tests.
- [ ] Add owner-aware lifecycle locking with deterministic stale recovery.
- [ ] Replace filename-derived staged commit grouping with explicit pre-stage
  responsibility plans.
- [ ] Add provider activation to the harness Home Manager module and remove the
  consumer-owned Codex-only activation.
- [ ] Record installed-provider native checks separately from static export
  checks; report missing Claude/Gemini CLIs as `UNAVAILABLE`, never `PASS`.

## Refactor and Verify

- [ ] Keep provider path mapping in one contract.
- [ ] Run focused Python/Bats/Nix checks.
- [ ] Run the full harness suite and `nix flake check`.
- [ ] Independently review policy boundaries, user-file preservation, and
  provider discovery.
- [ ] Create SRP commits with requirement and verification evidence.
- [ ] Push the harness, update the `tonys-nix` pin, verify, and apply Home
  Manager.
