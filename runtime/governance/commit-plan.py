#!/usr/bin/env python3
"""Create a deterministic, non-mutating SRP commit plan from staged scope."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def block(message):
    print(message, file=sys.stderr)
    raise SystemExit(2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--scope", type=Path)
    parser.add_argument("--requirement", action="append")
    parser.add_argument("--verify-plan", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    if args.verify_plan:
        plan = json.loads(args.verify_plan.read_text())
        bindings = []
        for item in plan.get("commits", []):
            commit = item.get("result_commit", "")
            if not commit or not item.get("requirements"):
                block("commit plan verification blocked: result commit and requirements required")
            actual = set(git(repo, "show", "--format=", "--name-only", commit).splitlines())
            if actual != set(item.get("files", [])):
                block("commit plan verification blocked: committed files differ from plan")
            for name in actual:
                patch = subprocess.check_output(["git", "-C", str(repo), "show", "--format=", "--binary", commit, "--", name])
                if hashlib.sha256(patch).hexdigest() != item.get("staged_diff_sha256", {}).get(name):
                    block("commit plan verification blocked: committed patch differs from plan")
            bindings.append({"commit": git(repo, "rev-parse", f"{commit}^{{commit}}"), "requirements": item["requirements"], "files": sorted(actual)})
        if not bindings:
            block("commit plan verification blocked: no commit bindings")
        print(json.dumps({"status": "VERIFIED", "bindings": bindings}, sort_keys=True))
        return 0
    if not args.scope or not args.requirement:
        parser.error("--scope and --requirement are required when planning")
    scope = {line for line in args.scope.read_text().splitlines() if line}
    staged = set(git(repo, "diff", "--cached", "--name-only").splitlines())
    outside = sorted(staged - scope)
    missing = sorted(scope - staged)
    history = git(repo, "log", "-20", "--format=%s").splitlines()
    conventional = sum(bool(re.match(r"^(feat|fix|refactor|docs|test|chore)(\([^)]*\))?: ", item)) for item in history)
    style = "conventional" if conventional * 2 >= max(1, len(history)) else "repository-native"
    groups = []
    remaining = set(staged & scope)
    for name in sorted(staged & scope):
        if name not in remaining or "test" in Path(name).parts or Path(name).name.startswith("test_"):
            continue
        coupled = sorted(candidate for candidate in remaining if candidate != name and
                         ("test" in Path(candidate).parts or Path(candidate).name.startswith("test_")) and
                         Path(name).stem in Path(candidate).stem)
        files = [name, *coupled]
        remaining.difference_update(files)
        groups.append(files)
    groups.extend([[name] for name in sorted(remaining)])
    commits = []
    for files in groups:
        digests = {}
        for name in files:
            patch = subprocess.check_output(["git", "-C", str(repo), "diff", "--cached", "--", name])
            digests[name] = hashlib.sha256(patch).hexdigest()
        commits.append({"responsibility": Path(files[0]).stem, "files": files,
                        "staged_diff_sha256": digests, "requirements": args.requirement,
                        "result_commit": None})
    plan = {
        "status": "BLOCKED" if outside or missing or not staged else "READY",
        "baseline_commit": git(repo, "rev-parse", "HEAD"),
        "subject_style": style,
        "history_samples": history[:5],
        "requirements": args.requirement,
        "staged_files": sorted(staged),
        "outside_scope": outside,
        "missing_from_stage": missing,
        "commits": commits,
    }
    print(json.dumps(plan, sort_keys=True))
    return 0 if plan["status"] == "READY" else 2


if __name__ == "__main__":
    raise SystemExit(main())
