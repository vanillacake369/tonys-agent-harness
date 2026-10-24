# Operation Activation Reconcile v2 Execution Report

Date: 2026-10-24

Status: implementation and repository-wide verification complete. Downstream
publication and `tonys-nix` revision consumption remain pending.

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
| `nix flake check` | PASS on aarch64-darwin; pinned Python 75 tests, Bats 131 tests, Rust 26 tests, and Nix contracts |
| `python3 tests/benchmarks/operation-policy.py --samples 200 ...` | PASS, all five p95 distributions <= 100 ms |

The formal benchmark is
[recorded as JSON](default-allow-operations-reconcile-v2-benchmark.json). It
uses an executable notifier that sleeps for one second; the runtime bounds that
child to 20 ms. Recorded p95 values were 50.045 ms cached, 50.307 ms full
preflight, 96.753 ms DENY, 95.114 ms FAILED inside cooldown, and 50.838 ms
FAILED after cooldown.

## Independent review and repair

Three read-only reviews initially blocked release on structural fingerprinting,
version/surface compatibility, Kiro discovery, and competing Claude deny hooks.
All four findings were repaired and covered by focused tests. The obsolete v1
assertions were updated to require the v2 authority:

- a Read hook is expected to contain `path-guard.sh`, although v2 requires
  `policy-runtime.py`;
- Codex is expected to contain `pre-tool-gate.sh`, although v2 requires
  `policy-runtime.py`.

A final read-only mid-review then found direct-PreTool surface validation,
mutable legacy-guard migration, applicable telemetry fingerprints, and stale
evidence gaps. The implementation now validates the requested surface at the
blocking edge, migrates only exact legacy harness guard commands, records the
current fingerprint on classified denials, and covers each correction with a
regression test. The two assertion lines were staged independently from the
unrelated user-owned schema-v2 work in the same file.

## Residual risks

- Native hook deletion remains undetectable by the deleted hook itself. Doctor
  and subsequent activation report the missing managed structure truthfully.
- Only Codex was installed on the reference host. Other provider native smoke
  remains `UNAVAILABLE`; generated structural fixtures pass for all four.
- Native Codex filesystem permission denials cannot be routed through the hook
  feedback adapter when the provider does not emit a blocking file-tool event.
  The common runtime covers every configured blocking hook surface.
- Direct `/usr/bin/python3` on the reference macOS host is Python 3.9 and lacks
  `tomllib`; authoritative verification therefore runs through the pinned Nix
  check rather than claiming a host-Python or `just check` pass.
- Linux outputs were evaluated but not executed on the aarch64-darwin host.
