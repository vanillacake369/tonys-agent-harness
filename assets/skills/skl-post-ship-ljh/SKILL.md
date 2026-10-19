---
name: skl-post-ship-ljh
description: Prepare an explicitly approved release or external operation with rollback and observation evidence.
---

# Post-Ship Engineering Skill

This skill prepares an operation; it does not imply permission to execute it.

- Identify environment, target resources, operation ID, request fingerprint,
  approval scope, rollback, and observation window.
- Run or describe a dry run before external mutation.
- Treat timeout as `UNKNOWN` and query state before retrying.
- Require deterministic Human Gate approval for release, deploy, migration,
  push, merge, or external resource changes.
- Close only with verification evidence or an explicit blocked state.
