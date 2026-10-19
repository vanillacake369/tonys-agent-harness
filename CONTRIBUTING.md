# Contributing

Keep provider-neutral behavior in `AGENTS.md` and `core/`; keep provider syntax
at the `harness.py` export edge. Do not duplicate shared policy in generated
files or weaken mandatory controls.

Before proposing a change:

```bash
python3 -m unittest discover -s tests -v
python3 -m compileall -q harness.py runtime/governance tests
nix flake check
git diff --check
```

Behavior changes need a failing regression test first. Document requirement or
architecture changes under `docs/agent/`, and update traceability when the mapped
evidence changes. Never commit telemetry, generated bundles, credentials,
approval/review receipts, raw local evidence, or memory state.

Use `type(scope): description` for commit subjects. Pull requests should contain
Overview, Changes, Tests, and Discussion sections as defined in `AGENTS.md`.
