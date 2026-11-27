---
name: skl-pre-nix-complexity-ljh
description: Use when ranking complex Nix files or comparing Nix code structure before and after a refactor.
metadata:
  kind: skill
  behavior: not-verified
---

# Skill / Nix Complexity Assessment

Measure Nix structure with a Nix-aware parser. Separate structural size and decision counts
from lint, evaluation, build, and runtime performance. Do not report Lizard's zero CCN for
unsupported `.nix` files as a complexity result.

## Measurement

1. Pin the checkout revision, dirty state, target paths, and the decision the measurement will inform.
2. Run the bundled read-only reporter against the same paths at a Git ref and in the worktree:

   ```sh
   python3 scripts/nix-complexity.py --repo /path/to/checkout --base HEAD \
     --paths flake.nix lib modules > /tmp/nix-complexity.json
   jq '{before: .before.summary, after: .after.summary, delta}' /tmp/nix-complexity.json
   ```

   Resolve `scripts/` relative to this `SKILL.md` when calling from another directory.
   The script needs Python 3 and `nix-instantiate` on `PATH`. It reads tracked and untracked
   nonignored `.nix` files in the selected scope; `--base` reads the pinned Git tree. It never evaluates
   imports or executes Nix expressions. A missing parser, empty scope, or parse failure stops
   the measurement rather than returning a misleading partial total.
3. Inspect per-file changes and the largest remaining `decisions` and `max_if_depth` values.
   For lint evidence, run `statix check .` **from the target checkout root** so its local
   `statix.toml` is discovered. Record the command, working directory, config, version/source
   if known, exit status, and diagnostics. `statix` detects Nix
   antipatterns; a clean result is not a low-complexity score. If `statix` is unavailable, record
   `NOT_RUN`; do not install it or run `statix fix` as part of analysis.
4. Compare output names, derivations, tests, or other behavior contracts before claiming the
   refactor preserved behavior. Parsing and lint alone cannot establish that.

## Metric contract

- `loc`: physical lines; `nloc`: nonempty lines except lines beginning with `#` after whitespace.
  Block comments and lines in multiline strings remain in `nloc`.
- `ifs`, `asserts`, `boolean_ops` (`&&`, `||`, `->`) come from the normalized output of
  `nix-instantiate --parse`. `decisions` is their sum; `max_if_depth` counts nested `if` expressions.
- `lambdas` counts colon separators outside strings in the normalized parser output.
- These are structural proxies, **not** cyclomatic or cognitive complexity, evaluation time,
  memory usage, or proof that fewer lines are easier to maintain. State the metric definition
  and inspect concrete code paths before recommending a change.

Tree-sitter can be useful for node-level exploration, but its recovered `ERROR`/`MISSING`
nodes must be checked against Nix's parser before using counts. The observed PyPI
`tree-sitter-nix` 0.1.0 grammar recovered on several valid Nix files in a sampled checkout;
the reporter therefore uses Nix's own parser for complete-repository comparison.
See the [Nix parser command](https://nix.dev/manual/nix/stable/command-ref/nix-instantiate.html)
and [statix usage](https://github.com/oppiliappan/statix/blob/master/readme.md).

## Report

Return `revision/scope | parser and availability | BEFORE/AFTER/delta | highest-complexity
files | statix result | behavior checks | interpretation and limits | next action`.
Use `NOT_RUN` for missing checks and `UNRESOLVED` for claims without direct evidence.
Do not add dependencies or change code merely to lower a metric.

```json composition
{"requires": [], "hints": ["tool-nix-ljh"]}
```
