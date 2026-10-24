# Operation Activation Reconcile v2 Execution Report

Date: 2026-10-24

Status: implementation complete; repository-wide acceptance is blocked only by
two superseded assertions in a preserved user-owned test file.

## Changes made

- Added the single pinned-Python activation, latch, classification, feedback,
  notification, telemetry, and state authority.
- Added the five-state schema, provider/version/surface porter rules, Kiro
  executable mapping, structural managed-hook validation, scoped fingerprints,
  bounded transition locks, atomic private records, cooldown recovery, and
  runtime replacement detection.
- Rewired generated and Nix provider hooks to the common authority while
  preserving native timeout units. Removed Claude's competing command, path,
  and branch deny hooks.
- Kept capabilities descriptive (`hook_porter = implemented`) rather than
  publishing a second activation status.
- Added provider-shape, privacy, concurrency, corruption, symlink, cooldown,
  doctor, version/surface, payload-normalization, and performance fixtures.

## Verification

| Command | Result |
| --- | --- |
| `python3 -m unittest discover -s tests -v` | PASS, 73 tests |
| Bats suites excluding preserved `harness-remediation.bats` | PASS, 85 tests |
| `cargo test --workspace` | PASS, 26 tests |
| `nix flake check --no-build` | PASS on aarch64-darwin |
| `python3 tests/benchmarks/operation-policy.py --samples 200 ...` | PASS, all five p95 distributions <= 100 ms |
| full `bats tests/hooks/*.bats` | 129 PASS, 2 stale assertion failures |

The formal benchmark is
[recorded as JSON](default-allow-operations-reconcile-v2-benchmark.json). It
uses an executable notifier that sleeps for one second; the runtime bounds that
child to 20 ms. Recorded p95 values were 50.045 ms cached, 50.307 ms full
preflight, 96.753 ms DENY, 95.114 ms FAILED inside cooldown, and 50.838 ms
FAILED after cooldown.

## Independent review and repair

Three read-only reviews initially blocked release on structural fingerprinting,
version/surface compatibility, Kiro discovery, and competing Claude deny hooks.
All four findings were repaired and covered by focused tests. Review also
confirmed that the two remaining Bats failures are obsolete v1 assertions, not
product regressions:

- a Read hook is expected to contain `path-guard.sh`, although v2 requires
  `policy-runtime.py`;
- Codex is expected to contain `pre-tool-gate.sh`, although v2 requires
  `policy-runtime.py`.

The assertions live in `tests/hooks/harness-remediation.bats`, which already
contains unrelated user-owned schema-v2 work and was deliberately not edited.

## Residual risks and blockers

- Native hook deletion remains undetectable by the deleted hook itself. Doctor
  and subsequent activation report the missing managed structure truthfully.
- Only Codex was installed on the reference host. Other provider native smoke
  remains `UNAVAILABLE`; generated structural fixtures pass for all four.
- Native Codex filesystem permission denials cannot be routed through the hook
  feedback adapter when the provider does not emit a blocking file-tool event.
  The common runtime covers every configured blocking hook surface.
- Full `nix flake check` inherits the two preserved stale Bats assertions. The
  product, Python, Rust, structural Nix, and all other Bats checks pass.
