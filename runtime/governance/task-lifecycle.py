"""Managed SessionStart/Stop adapter; stdin is provider hook JSON.

Baseline state is outside the repository. File metadata detects ordinary task
changes without reading credentials. It is not protection from a malicious
same-user process restoring timestamps or forging evidence.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import secrets


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("start", "stop"):
        raise ValueError("expected start or stop")
    payload = json.load(sys.stdin)
    session = payload.get("session_id")
    cwd = payload.get("cwd")
    if not isinstance(session, str) or not session or not isinstance(cwd, str) or not cwd:
        raise ValueError("hook requires session_id and cwd")
    repo = Path(subprocess.check_output(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"], text=True
    ).strip()).resolve()
    state_root = Path(os.environ.get("AGENT_TASK_STATE_DIR", str(
        Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "agent-policy/tasks"
    )))
    state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    retry_state = Path(os.environ.get("AGENT_RETRY_STATE", str(
        Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "agent-policy/retry.json"
    )))
    # Pending work survives provider session IDs. Only a validated stop advances
    # the repository baseline; restarting the CLI cannot forget an unfinished diff.
    key = hashlib.sha256(str(repo).encode()).hexdigest()
    state_file = state_root / f"{key}.json"
    lock = state_root / f"{key}.lock"
    lock.mkdir(mode=0o700)
    try:
        def git(*args):
            return subprocess.check_output(["git", "-C", str(repo), *args])

        def snapshot():
            names = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
            files = {}
            for raw in names.split(b"\0"):
                if not raw:
                    continue
                name = os.fsdecode(raw)
                try:
                    stat = (repo / name).lstat()
                    files[name] = [stat.st_size, stat.st_mtime_ns, stat.st_mode]
                except FileNotFoundError:
                    files[name] = None
            head_result = subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "HEAD"],
                                         capture_output=True, text=True)
            return {"files": files, "head": head_result.stdout.strip() if head_result.returncode == 0 else None}

        if sys.argv[1] == "start":
            if not state_file.exists():
                with state_file.open("x") as handle:
                    state_file.chmod(0o600)
                    json.dump({"repo": str(repo), "session": session,
                               "task_id": secrets.token_hex(16), "baseline": snapshot()}, handle)
            print("task baseline preserved")
            return 0
        if not state_file.is_file():
            raise ValueError("missing task baseline; cannot validate completion")
        state = json.loads(state_file.read_text())
        if state["repo"] != str(repo):
            raise ValueError("task identity mismatch")
        baseline = state["baseline"]
        current = snapshot()
        if retry_state.is_file():
            retry = json.loads(retry_state.read_text())
            if retry.get("tasks", {}).get(state.get("task_id"), {}).get("status") == "BLOCKED":
                print("BLOCKED: retry budget remains BLOCKED; explicit human resolution required")
                return 0
        changed = {name for name in baseline["files"].keys() | current["files"].keys()
                   if baseline["files"].get(name) != current["files"].get(name)}
        if baseline["head"] != current["head"]:
            if not baseline["head"] or not current["head"]:
                changed.update(current["files"])
            else:
                changed.update(os.fsdecode(name) for name in git(
                    "diff", "--name-only", "-z", baseline["head"], current["head"]
                ).split(b"\0") if name)
        # Only plain documentation qualifies for the non-code completion path.
        code_changes = sorted(name for name in changed if Path(name).suffix.lower() not in (".md", ".rst"))
        if not code_changes:
            print(json.dumps({"completion": "non-code", "changed_artifacts": sorted(changed)}))
            state.update({"session": session, "task_id": secrets.token_hex(16),
                          "baseline": current})
            state_file.write_text(json.dumps(state))
            return 0
        evidence = os.environ.get("AGENT_COMPLETION_EVIDENCE")
        scope = os.environ.get("AGENT_TASK_SCOPE")
        if not evidence or not scope:
            print("BLOCKED: code changed: completion evidence and scope required; preserve work and report BLOCKED")
            return 0
        allowed = set(Path(scope).read_text().splitlines())
        if not set(code_changes).issubset(allowed):
            print("BLOCKED: task code changes exceed completion scope")
            return 0
        code = subprocess.call(["bash", str(Path(__file__).with_name("completion-gate.sh")),
                                "--repo", str(repo), "--scope", scope, "--evidence", evidence])
        if code == 0:
            state.update({"session": session, "task_id": secrets.token_hex(16),
                          "baseline": snapshot()})
            state_file.write_text(json.dumps(state))
        else:
            print("BLOCKED: completion evidence did not satisfy the completion gate")
        return 0
    finally:
        lock.rmdir()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f"task lifecycle blocked: {error}", file=sys.stderr)
        raise SystemExit(2)
