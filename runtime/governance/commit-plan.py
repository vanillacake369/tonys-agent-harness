#!/usr/bin/env python3
"""Create and verify explicit pre-stage SRP commit plans."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.strip()


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)


def changed_files(repo: Path) -> set[str]:
    tracked = set(filter(None, git(repo, "diff", "--name-only", "HEAD").splitlines()))
    untracked = set(filter(None, git(repo, "ls-files", "--others", "--exclude-standard").splitlines()))
    return tracked | untracked


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create_plan(repo: Path, responsibilities: Path) -> dict:
    raw = json.loads(responsibilities.read_text())
    commits = raw.get("commits")
    if not isinstance(commits, list) or not commits:
        fail("responsibility plan requires a non-empty commits list")
    actual = changed_files(repo)
    assigned: dict[str, str] = {}
    names: set[str] = set()
    errors: list[str] = []
    rendered = []
    for item in commits:
        name = item.get("responsibility", "")
        files = item.get("files", [])
        requirements = item.get("requirements", [])
        verification = item.get("verification_command", "")
        if not name or name in names:
            errors.append(f"duplicate or empty responsibility: {name!r}")
        names.add(name)
        if not files or not requirements or not verification:
            errors.append(f"{name}: files, requirements, and verification_command are required")
        for file in files:
            if file in assigned:
                errors.append(f"overlap: {file} belongs to {assigned[file]} and {name}")
            assigned[file] = name
        rendered.append({
            "responsibility": name,
            "files": files,
            "requirements": requirements,
            "verification_command": verification,
            "content_sha256": {
                file: digest(repo / file) for file in files if (repo / file).is_file()
            },
        })
    missing = sorted(actual - set(assigned))
    extra = sorted(set(assigned) - actual)
    if missing:
        errors.append("unassigned changed files: " + ", ".join(missing))
    if extra:
        errors.append("planned files are not changed: " + ", ".join(extra))
    if errors:
        fail("; ".join(errors))
    return {
        "schema_version": 1,
        "subject_style": "conventional",
        "baseline_commit": git(repo, "rev-parse", "HEAD"),
        "commits": rendered,
    }


def verify_plan(repo: Path, plan_path: Path) -> dict:
    plan = json.loads(plan_path.read_text())
    previous = plan.get("baseline_commit")
    bindings = []
    for item in plan.get("commits", []):
        commit = item.get("result_commit")
        if not previous or not commit:
            fail("baseline_commit and every result_commit are required")
        if git(repo, "rev-parse", f"{commit}^") != git(repo, "rev-parse", previous):
            fail(f"commit sequence mismatch at {commit}")
        files = sorted(filter(None, git(repo, "diff-tree", "--no-commit-id", "--name-only", "-r", commit).splitlines()))
        expected = sorted(item.get("files", []))
        if files != expected:
            fail(f"commit file binding mismatch at {commit}: expected {expected}, got {files}")
        for file in expected:
            content = subprocess.run(
                ["git", "-C", str(repo), "show", f"{commit}:{file}"], check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            ).stdout
            actual = hashlib.sha256(content).hexdigest()
            if actual != item.get("content_sha256", {}).get(file):
                fail(f"committed content mismatch for {file} at {commit}")
        bindings.append({"responsibility": item["responsibility"], "commit": commit, "files": files})
        previous = commit
    return {"status": "VERIFIED", "baseline_commit": plan["baseline_commit"], "bindings": bindings}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--responsibilities", type=Path)
    mode.add_argument("--verify-plan", type=Path)
    args = parser.parse_args()
    result = create_plan(args.repo, args.responsibilities) if args.responsibilities else verify_plan(args.repo, args.verify_plan)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
