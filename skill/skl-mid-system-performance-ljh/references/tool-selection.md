# Performance tools and environments

## Match the tool to the workload

| Target | First choice | Follow-up when the hypothesis requires it |
| --- | --- | --- |
| CLI or batch process | Repository scenario or benchmark. Use hyperfine for process wall time when no A/B runner exists. | Process counters or a runtime profiler to explain where the time goes. |
| Function or library | Existing language benchmark with a representative fixture. For Go, use `go test -bench` and benchmem when relevant. | Compare repeated Go benchmark results with benchstat. Use Go pprof for CPU, allocation, or blocking evidence. |
| Request or query | Existing replay or read-only observation within the authorized environment. Verify response or result equivalence. | Use the relevant service tracing or database plan capability if available and authorized. |

Prefer a release-like build when timing production behavior. Record cache setup, failures, and work completed.
Check that the load generator, fixture setup, or process startup does not dominate a claim about application code.
For Go network code, verify a real runtime polling, blocking, or scheduling bottleneck before proposing
platform-specific syscalls or a concurrency change.

## Pin and verify tools

- Use the repository's reviewed, locked dev shell with `nix develop --no-update-lock-file` when it covers both
  revisions. Use one environment for both. Otherwise provision only the needed packages with `nix shell` from a
  reviewed nixpkgs commit. If that output is unavailable within scope, reuse a verified, immutable local store
  output or a versioned repository runner when the comparison can still be reproduced. Record the fallback.
- Record the flake or package pin and actual tool versions. Check OS, architecture, tool support, and authority before
  collecting. Pass only reviewed public inputs into Nix evaluation. Keep fixtures, raw profiles, and credentials
  outside the Nix input as appropriate.
- On Linux, use perf or bpftrace only for a qualifying question and within authorized scope. On macOS, use a supported
  language profiler or macOS tooling such as Instruments or sample when appropriate. If the metric requires Linux
  and there is no authorized Linux runner, report that metric as unavailable and scope any fallback result to the
  metric it actually measures.
