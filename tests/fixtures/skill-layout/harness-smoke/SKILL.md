---
name: harness-smoke
description: Check the Harness test fixture when explicitly asked for a Harness smoke check; no external services or file changes are needed.
---

Read [the fixture](references/fixture.md). Report its two labels in alphabetical
order, followed by their total count. Use the form `labels: <comma-separated labels>; count: <number>`.
This is a packaging/resource-loading smoke check, not an engineering capability.
Do not access external services or change files.
