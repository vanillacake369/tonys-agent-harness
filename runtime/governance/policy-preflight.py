#!/usr/bin/env python3
"""Lightweight SessionStart validation for the shared policy hook."""
from __future__ import annotations
import argparse, json, os, subprocess, sys
from pathlib import Path
import tomllib
from operation_policy import PROFILE, SUPPORTED_PROVIDERS

def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--provider", required=True); parser.add_argument("--status-file")
    parser.add_argument("--managed-fragment", default="")
    args = parser.parse_args(); root = Path(__file__).resolve().parent
    problems = []
    if args.provider not in SUPPORTED_PROVIDERS: problems.append("unsupported-hook-porter")
    for name in ("pre-tool-gate.sh", "path-guard.sh", "execution-gate.py", "operation_policy.py", "policy-feedback.py"):
        path = root / name
        if not path.is_file() or (path.suffix == ".sh" and not os.access(path, os.X_OK)) or not os.access(path, os.R_OK):
            problems.append(f"missing-or-not-executable:{name}")
    default_configs = {
        "codex": Path.home() / ".codex/config.toml",
        "claude": Path.home() / ".claude/settings.json",
        "gemini": Path.home() / ".gemini/settings.json",
        "kiro": Path.home() / ".kiro/hooks/engineering-governance.json",
    }
    config_path = Path(os.environ.get("AGENT_POLICY_CONFIG", default_configs.get(args.provider, ""))).expanduser()
    try:
        if args.provider == "codex":
            with config_path.open("rb") as handle: native = tomllib.load(handle)
        else: native = json.loads(config_path.read_text())
    except (OSError, json.JSONDecodeError, tomllib.TOMLDecodeError):
        native = {}; problems.append("invalid-or-missing-native-config")
    operation_signature = f"pre-tool-gate.sh --provider {args.provider} --profile {PROFILE} --managed-fragment harness-operation-policy-v1"
    preflight_signature = f"policy-preflight.py --provider {args.provider} --managed-fragment harness-policy-preflight-v1"
    expected_events = {
        "codex": ("SessionStart", "PreToolUse", "Bash"),
        "claude": ("SessionStart", "PreToolUse", "Bash"),
        "gemini": ("BeforeAgent", "BeforeTool", "run_shell_command"),
        "kiro": ("AgentSpawn", "PreToolUse", "execute_bash"),
    }
    def command(entry):
        action = entry.get("action", {}) if isinstance(entry, dict) else {}
        return entry.get("command", action.get("command", "")) if isinstance(entry, dict) else ""
    def nested_commands(entry):
        if not isinstance(entry, dict): return []
        hooks = entry.get("hooks", [])
        return [command(hook) for hook in hooks if isinstance(hook, dict)] or [command(entry)]
    found_preflight = found_operation = found_path = False
    if args.provider == "kiro":
        for entry in native.get("hooks", []) if isinstance(native, dict) else []:
            if not isinstance(entry, dict): continue
            value = command(entry); trigger = entry.get("trigger"); matcher = entry.get("matcher", "")
            found_preflight |= trigger == expected_events[args.provider][0] and entry.get("name") == "harness-policy-preflight-v1" and preflight_signature in value
            found_operation |= trigger == expected_events[args.provider][1] and entry.get("name") == "harness-operation-policy-v1" and set(filter(None, matcher.strip("^$()").split("|"))) == {"execute_bash", "execute_pwsh"} and operation_signature in value
            found_path |= trigger == "PreToolUse" and entry.get("name") == "harness-path-invariants-v1" and set(filter(None, matcher.strip("^$()").split("|"))) == {"fs_read", "fs_write", "fs_append", "str_replace", "delete_file"} and "path-guard.sh" in value and "harness-path-invariants-v1" in value
    else:
        hooks = native.get("hooks", {}) if isinstance(native, dict) else {}
        start_event, tool_event, matcher_text = expected_events.get(args.provider, ("", "", ""))
        for entry in hooks.get(start_event, []) if isinstance(hooks, dict) else []:
            found_preflight |= any(preflight_signature in value for value in nested_commands(entry))
        for entry in hooks.get(tool_event, []) if isinstance(hooks, dict) else []:
            matcher = str(entry.get("matcher", ""))
            if matcher_text in matcher:
                values = nested_commands(entry)
                found_operation |= any(operation_signature in value for value in values)
                if args.provider == "gemini":
                    found_path |= all(tool in matcher for tool in ("read_file", "write_file", "replace"))
            if args.provider == "claude" and set(filter(None, matcher.split("|"))) == {"Read", "Write", "Edit", "NotebookEdit"} and any("path-guard.sh" in value and "harness-path-invariants-v1" in value for value in nested_commands(entry)):
                found_path = True
        if args.provider == "codex":
            profile = native.get("permissions", {}).get(PROFILE, {}) if isinstance(native, dict) else {}
            filesystem = profile.get("filesystem", {}) if isinstance(profile, dict) else {}
            workspace = filesystem.get(":workspace_roots", {}) if isinstance(filesystem, dict) else {}
            found_path = (
                native.get("default_permissions") == PROFILE
                and filesystem.get("~/.ssh") == "deny"
                and filesystem.get("~/.gnupg") == "deny"
                and workspace.get("**/.env*") == "deny"
                and workspace.get("**/secrets/**") == "deny"
            )
    if native and (not found_preflight or not found_operation or not found_path):
        problems.append("missing-managed-policy-hook")
    status = "FAILED" if problems else "ENFORCED"
    record = {"provider": args.provider, "profile": PROFILE, "status": status, "problems": problems}
    target = Path(args.status_file).expanduser() if args.status_file else Path.home() / f".local/state/agent-harness/provider-{args.provider}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(record, sort_keys=True) + "\n"); os.chmod(target, 0o600)
    if problems:
        notifier = Path(os.environ.get("AGENT_NOTIFY_HOOK", Path.home() / ".config/agents/hooks/agent-notify.sh"))
        if notifier.is_file() and os.access(notifier, os.X_OK):
            try: subprocess.run([str(notifier), f"preflight-failed:{args.provider}"], timeout=1, check=False)
            except (OSError, subprocess.TimeoutExpired): pass
        print(f"operation policy preflight failed: {','.join(problems)}", file=sys.stderr); return 2
    return 0

if __name__ == "__main__": raise SystemExit(main())
