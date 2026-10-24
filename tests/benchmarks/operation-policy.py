#!/usr/bin/env python3
"""Measure the five frozen operation-policy v2 latency paths."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/governance/policy-runtime.py"
PROFILE = "default-allow-operations-v1"
ALLOW = {"tool_name": "Bash", "tool_input": {"command": "git status"}}
DENY = {"tool_name": "Bash", "tool_input": {"command": "kubectl delete pod fixture"}}


def percentile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, int(len(ordered) * percentile + 0.999999) - 1))]


def fixture(root: Path) -> dict[str, str]:
    config = root / "config.toml"
    config.write_text(
        'default_permissions = "default-allow-operations-v1"\n'
        '[[hooks.SessionStart]]\n[[hooks.SessionStart.hooks]]\n'
        'command = "policy-runtime.py startup --provider codex --surface cli --managed-fragment harness-policy-preflight-v1"\n'
        '[[hooks.PreToolUse]]\nmatcher = "Bash"\n[[hooks.PreToolUse.hooks]]\n'
        'command = "policy-runtime.py pretool --provider codex --surface cli --profile default-allow-operations-v1 --managed-fragment harness-operation-policy-v1"\n'
    )
    binary = root / "codex"
    binary.write_text("#!/bin/sh\necho 'codex-cli 0.162.1'\n")
    binary.chmod(0o755)
    notifier = root / "notify"
    notifier.write_text("#!/bin/sh\nsleep 1\n")
    notifier.chmod(0o755)
    return os.environ | {
        "AGENT_POLICY_STATE_DIR": str(root / "state"),
        "AGENT_POLICY_CONFIG": str(config),
        "AGENT_PROVIDER_EXECUTABLE": str(binary),
        "AGENT_NOTIFY_HOOK": str(notifier),
        "AGENT_SESSION_ID": "benchmark",
    }


def invoke(env: dict[str, str], mode: str, payload: dict | None = None, now: int | None = None, extra: dict[str, str] | None = None) -> tuple[int, float]:
    args = [sys.executable, str(RUNTIME), mode, "--provider", "codex", "--surface", "cli", "--profile", PROFILE]
    if now is not None:
        args += ["--now", str(now)]
    started = time.perf_counter_ns()
    completed = subprocess.run(
        args,
        input=json.dumps(payload) if payload is not None else "",
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env | (extra or {}),
        check=False,
    )
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    return completed.returncode, elapsed_ms


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=200)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        env = fixture(root)
        assert invoke(env, "startup", now=100)[0] == 0
        state_path = next((root / "state").glob("provider-*.json"))
        pending = state_path.read_bytes()
        distributions: dict[str, list[float]] = {name: [] for name in (
            "cached_enforced", "full_preflight", "deny", "failed_inside_cooldown", "failed_after_cooldown"
        )}

        state_path.write_bytes(pending)
        assert invoke(env, "pretool", ALLOW, now=100)[0] == 0
        enforced = state_path.read_bytes()
        assert invoke(env, "pretool", ALLOW, now=100, extra={"AGENT_POLICY_FORCE_PREFLIGHT_FAILURE": "1"})[0] == 0
        for _ in range(args.samples):
            state_path.write_bytes(enforced)
            code, elapsed = invoke(env, "pretool", ALLOW, now=100)
            assert code == 0
            distributions["cached_enforced"].append(elapsed)

            state_path.write_bytes(pending)
            code, elapsed = invoke(env, "pretool", ALLOW, now=100)
            assert code == 0
            distributions["full_preflight"].append(elapsed)

            state_path.write_bytes(enforced)
            code, elapsed = invoke(env, "pretool", DENY, now=100 + 60 * _)
            assert code == 2
            distributions["deny"].append(elapsed)

            state_path.write_bytes(pending)
            assert invoke(env, "pretool", ALLOW, now=100, extra={"AGENT_POLICY_FORCE_PREFLIGHT_FAILURE": "1"})[0] == 2
            failed = state_path.read_bytes()
            state_path.write_bytes(failed)
            code, elapsed = invoke(env, "pretool", ALLOW, now=104)
            assert code == 2
            distributions["failed_inside_cooldown"].append(elapsed)

            state_path.write_bytes(failed)
            code, elapsed = invoke(env, "pretool", ALLOW, now=105)
            assert code == 0
            distributions["failed_after_cooldown"].append(elapsed)

    paths = {
        name: {
            "samples": len(values),
            "median_ms": round(statistics.median(values), 3),
            "p95_ms": round(percentile(values, 0.95), 3),
            "max_ms": round(max(values), 3),
            "pass": percentile(values, 0.95) <= 100,
        }
        for name, values in distributions.items()
    }
    result = {
        "schema_version": 1,
        "host": {"system": platform.system(), "machine": platform.machine(), "python": platform.python_version()},
        "reference_host": platform.system() == "Darwin" and platform.machine() == "arm64",
        "budget_ms": 100,
        "paths": paths,
        "pass": all(item["pass"] for item in paths.values()),
    }
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end="")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
