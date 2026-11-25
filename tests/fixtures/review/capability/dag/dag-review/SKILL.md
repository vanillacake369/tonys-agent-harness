---
name: dag-review
description: Guide an evidence-first incident review and explicitly gated remediation; not for unrelated general questions.
---

# Incident review

Use [DAG.yaml](DAG.yaml) for the stages and stop conditions. Start with skill-review-evidence. Never perform remediation without native approval of the exact scope. The workflow is guidance, not an executor. Report missing evidence as UNRESOLVED.

```json composition
{"requires": ["skill-review-evidence"], "hints": []}
```
