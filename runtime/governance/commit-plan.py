#!/usr/bin/env python3
"""Create a deterministic, non-mutating SRP commit plan from staged scope."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--scope", required=True, type=Path)
    parser.add_argument("--requirement", required=True, action="append")
    args = parser.parse_args()
    repo = args.repo.resolve()
    scope = {line for line in args.scope.read_text().splitlines() if line}
    staged = set(git(repo, "diff", "--cached", "--name-only").splitlines())
    outside = sorted(staged - scope)
    missing = sorted(scope - staged)
    history = git(repo, "log", "-20", "--format=%s").splitlines()
    conventional = sum(bool(re.match(r"^(feat|fix|refactor|docs|test|chore)(\([^)]*\))?: ", item)) for item in history)
    style = "conventional" if conventional * 2 >= max(1, len(history)) else "repository-native"
    plan = {
        "status": "BLOCKED" if outside or missing or not staged else "READY",
        "baseline_commit": git(repo, "rev-parse", "HEAD"),
        "subject_style": style,
        "history_samples": history[:5],
        "requirements": args.requirement,
        "staged_files": sorted(staged),
        "outside_scope": outside,
        "missing_from_stage": missing,
        "commits": [
            {"responsibility": Path(name).stem, "files": [name], "requirements": args.requirement}
            for name in sorted(staged & scope)
        ],
    }
    print(json.dumps(plan, sort_keys=True))
    return 0 if plan["status"] == "READY" else 2


if __name__ == "__main__":
    raise SystemExit(main())
