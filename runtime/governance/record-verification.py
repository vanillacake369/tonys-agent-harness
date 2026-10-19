"""Execute an explicit verification command and record its actual Git snapshot.

This records evidence, not permission. It must run within the provider sandbox.
Use an output path outside the repository to avoid making a clean tree dirty.
The file is local evidence, not a cryptographic attestation against its owner.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--requirement", required=True, action="append")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("an explicit command is required")
    repo = Path(args.repo).resolve()
    output = Path(args.output).resolve()
    if output.exists():
        parser.error("output already exists; evidence must not be overwritten")

    def git(*argv):
        return subprocess.check_output(["git", "-C", str(repo), *argv], text=True).strip()

    before = git("rev-parse", "HEAD")
    baseline = git("rev-parse", f"{args.baseline}^{{commit}}")
    subprocess.check_call(["git", "-C", str(repo), "merge-base", "--is-ancestor", baseline, before])
    clean_before = not git("status", "--porcelain")
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=repo, text=True, capture_output=True)
        code = result.returncode
        actual = result.stdout + result.stderr
    except OSError as error:
        code, actual = 127, str(error)
    duration = round((time.monotonic() - start) * 1000)
    after = git("rev-parse", "HEAD")
    clean = clean_before and not git("status", "--porcelain") and before == after
    files = git("diff", "--name-only", baseline, after).splitlines()
    # A test change requires human review, including deleted/disabled tests.
    # Conservatively gate every changed test; do not infer intent from regexes.
    test_changes = [name for name in files if any(
        part in ("test", "tests", "__tests__") for part in Path(name).parts
    ) or Path(name).name.startswith("test_")
        or name.endswith((".bats", "_test.go", "_test.py", ".test.js", ".spec.js", ".test.ts", ".spec.ts"))]
    errors = []
    if code:
        errors.append(f"verification exit code {code}")
    if not clean:
        errors.append("verification requires an unchanged clean Git snapshot before DONE")
    status = "BLOCKED" if errors else ("REVIEW_REQUIRED" if test_changes else "DONE")
    artifact = {
        "status": status,
        "requirements": [{"id": item, "result": "pass" if code == 0 else "fail"} for item in args.requirement],
        "commands": [{"command": shlex.join(command), "exit_code": code,
                      "duration_ms": duration, "result": actual or "(no output)",
                      "executed_commit": before}],
        "changed_files": files,
        "diff_summary": git("diff", "--stat", baseline, after),
        "unresolved_errors": errors,
        "commit": after,
        "baseline_commit": baseline,
        "worktree_clean": clean,
        "test_changes_requiring_review": test_changes,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as handle:
        output.chmod(0o600)
        json.dump(artifact, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps({"status": artifact["status"], "evidence": str(output),
                      "exit_code": code, "duration_ms": duration}))
    return code if code else (0 if artifact["status"] == "DONE" else 2)


if __name__ == "__main__":
    raise SystemExit(main())
