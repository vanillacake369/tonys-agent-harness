---
name: skl-mid-system-performance-ljh
description: >-
  Use for repository performance work when a bottleneck must be found or a specified workload must be profiled,
  benchmarked, or optimized with reproducible before-and-after evidence. Covers local diagnosis and changes
  affecting latency, throughput, CPU, memory, allocations, I/O, syscalls, or concurrency.
metadata:
  kind: skill
  behavior: not-verified
---

# Skill / System Performance

Treat optimization as a controlled experiment. Preserve correctness, locate one measured bottleneck, change one
material variable, and compare equivalent workloads. Use the project's team performance workflow for API or SQL
investigations that rely on team observability. For an active production incident, start with the incident workflow.

## Scope and tools

1. Use the requested command, function, or request path when specified. Otherwise, locate real entry points,
   existing benchmarks or scenario fixtures, and available signals such as latency, load, or resource use.
   Rank plausible candidates by observed impact and reproducibility. Pick one representative workload and explain
   the evidence for it. Static code observations are hypotheses. Report the missing signal or fixture if no
   meaningful local workload can be reproduced.
2. Reuse the closest maintained repository measurement command and correctness check. Select the least invasive
   profiler that distinguishes the hypothesis. Use [tool selection and environment setup](references/tool-selection.md)
   for Nix, tool choice, and platform limitations. Verify the actual command and version before measuring.
3. Honor the requested effects. For diagnosis or planning, collect authorized evidence and return a recommendation.
   Change source or configuration only within implementation scope. Confirm the exact target and authority before
   attaching to a process, using privileged counters, or generating production load.

## Experiment contract

1. Before changes, record the target and source revision or patch identity, correctness command and expected
   work/output, inputs and data size, toolchain and OS/architecture, host conditions, build flags, cache policy,
   warm-up, repetitions, primary metric, and smallest meaningful change. Capture a repeatable baseline.
2. Profile separately from timing. Link the observed bottleneck to a source path and state one falsifiable hypothesis.
   If a material architecture choice remains, give `$skl-pre-design-assessment-ljh` the baseline, profile, hypothesis,
   smallest discriminating PoC, success or rejection thresholds, and decision the result would change. Use
   `$dag-worklog-ljh` for multi-stage implementation handoff and verification when needed.
3. For an authorized change, vary the proposed mechanism and preserve the workload and correctness contract.
   Compare baseline and candidate on the same host with the same pinned tools and settings, except any setting
   intentionally under test. Interleave repetitions when practical and report sample counts, dispersion, and relevant
   guardrail metrics. Record any comparison condition that could not be held.
4. Check correctness, errors, and evidence that the intended work ran before interpreting timings. Reject a candidate
   with a failed correctness check. Require an effect that exceeds the predeclared threshold and is supported by
   the sample spread or the tool's statistical comparison. Use an A/A control to check for false gains when needed.

## Report

Use `VERIFIED_IMPROVEMENT`, `NO_MATERIAL_CHANGE`, `REGRESSION`, or `UNRESOLVED`. Use `NO_MATERIAL_CHANGE` for an
equivalent comparison with adequate evidence and an effect below the practical threshold. Use `UNRESOLVED` when
evidence is missing, conditions differ, uncertainty could change the decision, or correctness invalidates the comparison.
Report correctness failures explicitly and reject the candidate. Record AS-IS behavior and the TO-BE hypothesis
separately from measured BEFORE and AFTER results.

Keep commands, revision and environment, workload, samples, profile evidence, correctness, decision, and rollback or
next action in the report. Scope conclusions to the observed workload and environment.

Apply the Harness adaptive capability policy.

```json composition
{
  "requires": [],
  "hints": [
    "tool-time-space-complexity-ljh",
    "tool-linux-kernel-ljh",
    "tool-concurrency-ljh",
    "tool-go-ljh",
    "tool-nix-ljh"
  ]
}
```
