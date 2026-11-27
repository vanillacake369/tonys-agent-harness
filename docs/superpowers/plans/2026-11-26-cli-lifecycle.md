# CLI lifecycle implementation plan

**Goal** Make onboarding, editing, and recovery discoverable from the root command.

**Architecture** Compute guidance from observed state. Route new commands through the existing Cobra commands and core transactions. Setup registers a checkout explicitly.

1. Unify root and config status. Verify missing Vault and key, restored Vault, workspace, and connected states with synthetic scenarios. Commit.
2. Register a default checkout with setup. Add root edit and apply, preserving the legacy edit behavior under config. Verify invocation outside the checkout and edit/apply boundaries. Commit.
3. Separate Source candidate checks from reviewed pinning and expose Skill authoring together. Document recovery and migration. Verify command contracts and the public build. Commit.

Status is read-only. Provider approval and Source pinning are explicit. Vault and Runtime retain their separate transaction boundaries.
