# ADR-0001: Headless Core With Provider Exporters

## Status

Accepted for MVP.

## Context

The framework must be easy to configure while preserving deterministic policy
across providers with different native capabilities.

## Independent strategies

- Strategy A: keep Nix as the only configuration and rendering API. This has
  strong evaluation but excludes non-Nix projects and exposes implementation
  details to users.
- Strategy B: use a standalone manifest and imperative generator. This is easy
  to adopt but can drift unless schema, policy, and generated output are tested.

## Consensus

- One provider-neutral contract and one project manifest.
- Provider files are generated adapters, not policy sources.
- Export and activation are separate operations.
- Mandatory policy cannot be weakened by a project or provider.

## Conflicts and decision

Use TOML as the user interface, Python standard library for the portable CLI,
and retain Nix as a packaging/Home Manager integration backend. Generated
artifacts carry a digest of normalized input, and `verify` checks that digest.

## Rollback

`tonys-nix` retains its current implementation until parity and consumer wiring
are independently verified. Removing the new flake input restores the previous
integration without deleting project specifications.
