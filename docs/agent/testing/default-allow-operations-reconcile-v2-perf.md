# Performance Plan: Operation Activation Reconcile v2

Status: Pre-implementation performance contract (2026-10-24)

Related PRD:
[`default-allow-operations-reconcile-v2-2026-10-24.md`](../prd/default-allow-operations-reconcile-v2-2026-10-24.md)

## Budget

The provider-observed PreTool policy overhead is p95 <= 100 ms on the current
aarch64-darwin Nix reference host. Other supported local Nix systems report the
same fixtures informationally until CI designates them release-blocking.
Measure these paths independently:

1. matching fingerprint with cached `ENFORCED` state;
2. `PENDING` or changed fingerprint requiring full local preflight;
3. classified DENY including feedback persistence and a stub notifier;
4. unchanged `FAILED` state inside the five-second cooldown;
5. unchanged `FAILED` state after cooldown, requiring locked full preflight.

Provider tool execution, provider model latency, desktop notification display
latency, and Home Manager activation are outside this budget. The hook process
and every child process it starts are inside it.

## Existing baseline

An exploratory sequential measurement on 2026-10-24 ran 100 harmless allow
payloads on the local aarch64-darwin development host:

| Path | Wall time | Approximate mean |
| --- | ---: | ---: |
| `execution-gate.py` directly | 3.54 s / 100 | 35 ms |
| `pre-tool-gate.sh` end to end | 10.05 s / 100 | 100 ms |

Commands:

```bash
/usr/bin/time -p sh -c 'i=0; while [ $i -lt 100 ]; do printf "%s" "$PAYLOAD" | python3 runtime/governance/execution-gate.py --provider codex --profile default-allow-operations-v1 >/dev/null || exit; i=$((i+1)); done'

/usr/bin/time -p sh -c 'i=0; while [ $i -lt 100 ]; do printf "%s" "$PAYLOAD" | bash runtime/governance/pre-tool-gate.sh --provider codex --profile default-allow-operations-v1 >/dev/null || exit; i=$((i+1)); done'
```

These figures are directional only: they are sequential means, not p95; they
used the developer shell rather than a clean Nix benchmark derivation; and the
shell variable must be fixed to the same harmless JSON payload in the formal
fixture. They justify measuring process fan-out but do not authorize a language
migration.

## Hypotheses

- H1: consolidating Bash/JQ/Python fan-out into one pinned Python process will
  reduce the cached allow path materially because the direct Python path is
  approximately one third of the current end-to-end mean.
- H2: hashing only managed fragments and immutable runtime identity will keep
  an unchanged fingerprint below the budget.
- H3: full local preflight can remain below the budget if it does not invoke a
  provider binary on each tool call.
- H4: notification must remain outside the decision-critical latency except
  for a bounded adapter timeout; a stub notifier makes the regression fixture
  deterministic.

## Benchmark design

- Use a repository-owned benchmark driver with monotonic nanosecond timing and
  machine-readable JSON output.
- Use the current aarch64-darwin Nix development host as the v2 release-blocking
  reference system. Warm each case, then record at least 200 samples per case.
  Other supported Nix systems report the same metrics but are informational
  until a repository CI runner is explicitly designated release-blocking.
- Report count, min, median, p95, p99, max, mean, host system, Python/runtime
  identity, harness revision, and fixture digest.
- Use isolated temporary state per benchmark and fixed provider-native fixture
  files; never read credentials or contact a provider or external resource.
- Benchmark one process invocation per hook event because process startup is
  part of the production path.
- Add a small concurrent transition case for correctness and contention
  evidence; do not turn throughput into a substitute for the latency SLO.

## Optimization sequence

1. Record the formal baseline for the current split path.
2. Consolidate parsing, path invariants, activation latch, classifier, state,
   feedback, and notification dispatch in one pinned Python entry point.
3. Measure all five required paths and compare against the same fixtures.
4. Optimize only a measured bottleneck, one change at a time.
5. If any required path still exceeds p95 100 ms, do not waive the budget.
   Start the accepted Rust shadow/cutover evaluation instead.

## Correctness gates

Performance evidence is invalid unless all decision fixtures, privacy tests,
state transition tests, concurrency tests, provider structural fixtures, and
native smoke tests remain green. Benchmark shortcuts may not bypass atomic
writes, fingerprint validation, redaction, or fail-closed behavior.

## Rust cutover evidence

A native hot-path candidate must demonstrate:

- 100% semantic parity on frozen Python fixtures;
- p95 improvement on the same five benchmark cases;
- available-provider native smoke success;
- independent rollback to the Python authority;
- one authoritative decision maker at every rollout stage.

Go remains a rejected v2 optimization because it adds a third language and a
second native policy engine without evidence that the existing Rust toolchain
cannot meet the same objective.
