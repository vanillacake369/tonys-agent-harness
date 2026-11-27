#!/usr/bin/env python3
"""Measure equivalent dry-run candidates with BEFORE and AFTER Harness binaries."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shlex
import shutil
import statistics
import subprocess
import tempfile
import time


def fixture(root, count):
    root.mkdir(mode=0o700)
    bundle = root / "bundle"
    for kind in ("agent", "dag", "skill", "tool"):
        (bundle / kind).mkdir(parents=True)
    for i in range(count):
        name = f"audit-skill-{i}"
        path = bundle / "skill" / name
        path.mkdir()
        (path / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Synthetic measurement.\n---\n\n"
            "Body with a [fixture](NOTES.md).\n\n"
            '```json composition\n{"requires":[],"hints":[]}\n```\n'
        )
        (path / "NOTES.md").write_text("Supporting fixture.\n")
    return bundle


def invoke(binary, args, env):
    return subprocess.check_output([binary, *args], env=env)


def measure(binaries, env, samples, root):
    args = ["apply", "--dry-run", "--format", "json"]
    timings = [[] for _ in binaries]
    expected = invoke(binaries[0], args, env)
    for repeat in range(samples + 1):
        for index, binary in enumerate(binaries):
            before = time.perf_counter()
            result = invoke(binary, args, env)
            elapsed = (time.perf_counter() - before) * 1000
            if result != expected:
                raise ValueError("dry-run reports differ")
            if repeat:
                timings[index].append(elapsed)
    for binary, times in zip(binaries, timings):
        print(binary.name, "median/min/max (ms)", *(round(v, 2) for v in
              (statistics.median(times), min(times), max(times))), flush=True)

    tools = root / "bin"
    tools.mkdir()
    trace = root / "trace"
    for name in ("bash", "find", "awk", "jq", "grep", "realpath", "python3"):
        command = shutil.which(name)
        if command is None:
            continue
        wrapper = tools / name
        wrapper.write_text(
            f"#!/bin/sh\nprintf '%s\\n' {name} >> \"$HARNESS_MEASURE_TRACE\"\n"
            f"exec {shlex.quote(command)} \"$@\"\n"
        )
        wrapper.chmod(0o700)
    traced = env | {"PATH": f"{tools}:{env['PATH']}", "HARNESS_MEASURE_TRACE": str(trace)}
    for binary in binaries:
        trace.write_text("")
        check = invoke(binary, args, traced)
        if check != expected:
            raise ValueError("instrumented report differs")
        print(binary.name, "subprocess counts", json.dumps(Counter(trace.read_text().splitlines()), sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binaries", nargs=2, type=Path, metavar="BINARY")
    parser.add_argument("--samples", type=int, default=5)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("samples must be positive")
    repo = Path(__file__).resolve().parent.parent
    binaries = [p.resolve(strict=True) for p in args.binaries]
    with tempfile.TemporaryDirectory(prefix="harness-apply-benchmark-") as directory:
        root = Path(directory).resolve()
        checkout = root / "checkout"
        public = (
            "core/environment-public.txt", "core/skill-validate.sh", "core/metadata-validate.py",
            "provider/provider-catalog.json", "contract/local-access.json",
        )
        for name in public:
            target = checkout / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(repo / name, target)
        for count in (8, 86):
            case = root / str(count)
            bundle = fixture(case, count)
            env = os.environ | {
                "HARNESS_REPO": str(checkout),
                "HARNESS_STATE": str(case / "state"),
                "HARNESS_VAULT": str(case / "vault.enc"),
                "HARNESS_AGE_KEY": str(case / "age.key"),
            }
            invoke(binaries[0], ["config", "init", bundle], env)
            invoke(binaries[0], ["apply"], env)
            print(f"{count} skills", flush=True)
            measure(binaries, env, args.samples, case)


if __name__ == "__main__":
    main()
