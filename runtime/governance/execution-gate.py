#!/usr/bin/env python3
"""Fail-closed execution-boundary classifier for approval-scoped commands."""

import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import subprocess
import sys


MUTATING_SUBCOMMANDS = {
    "git": {"push"},
    "kubectl": {"apply", "create", "delete", "edit", "patch", "replace", "rollout", "scale", "set"},
    "terraform": {"apply", "destroy", "import"},
    "tofu": {"apply", "destroy", "import"},
    "pulumi": {"up", "destroy", "import"},
    "helm": {"install", "upgrade", "uninstall", "rollback"},
    "nixos-rebuild": {"switch", "boot"},
    "darwin-rebuild": {"switch"},
    "home-manager": {"switch"},
}
DESTRUCTIVE = {"rm", "rmdir", "shred", "mkfs", "wipefs"}
MIGRATION_WORDS = {"migrate", "migration", "db:migrate", "prisma"}


def classify(command: str) -> str | None:
    if "${!" in command:
        return "unparseable-shell-command"
    # Preserve visibility of commands nested in ordinary substitutions while
    # avoiding a blanket denial of benign shell syntax such as $(pwd). This is
    # a classifier, not a shell evaluator; provider sandboxing remains the
    # execution boundary.
    lexical_command = re.sub(r"\$\(|[()`]", " ", command)
    try:
        lexer = shlex.shlex(lexical_command.replace("\n", ";"), posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return "unparseable-shell-command"
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token in {";", "&", "&&", "||", "|"}:
            segments.append([])
        else:
            segments[-1].append(token)
    known = set(MUTATING_SUBCOMMANDS) | DESTRUCTIVE
    for segment in segments:
        lowered = [token.lower() for token in segment]
        shell_index = next((index for index, token in enumerate(lowered)
                            if Path(token).name in {"bash", "sh", "zsh", "dash", "ksh"}), None)
        if shell_index is not None and "-c" in lowered[shell_index + 1:]:
            command_index = lowered.index("-c", shell_index + 1) + 1
            if command_index >= len(segment):
                return "unparseable-shell-command"
            nested = classify(segment[command_index])
            if nested:
                return nested
        executable_index = next((index for index, token in enumerate(lowered)
                                 if Path(token).name in known), None)
        if executable_index is not None:
            executable = Path(lowered[executable_index]).name
            if executable in DESTRUCTIVE:
                return "destructive-command"
            operations = {token for token in lowered[executable_index + 1:] if not token.startswith("-")}
            selected = MUTATING_SUBCOMMANDS[executable] & operations
            if selected:
                return f"{executable}-{sorted(selected)[0]}"
        if any(token in MIGRATION_WORDS or token.endswith(":migrate") for token in lowered):
            return "data-migration"
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        print("execution gate blocked: invalid hook payload", file=sys.stderr)
        return 2
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        print("execution gate blocked: tool_input required", file=sys.stderr)
        return 2
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        return 0
    action = classify(command)
    if action is None:
        return 0
    if action == "unparseable-shell-command":
        print("execution gate blocked: command classification failed", file=sys.stderr)
        return 2

    repo = Path(payload.get("cwd") or os.getcwd()).resolve()
    environment = os.environ.get("AGENT_TARGET_ENVIRONMENT", "unknown")
    canonical = json.dumps({"action": action, "command": command, "environment": environment,
                            "repo": str(repo)}, sort_keys=True, separators=(",", ":"))
    request_digest = hashlib.sha256(canonical.encode()).hexdigest()
    receipt = os.environ.get("AGENT_APPROVAL_RECEIPT", "")
    if not receipt or environment == "unknown":
        print(f"execution gate blocked: scoped approval required action={action} digest={request_digest}", file=sys.stderr)
        return 2
    gate = Path(__file__).with_name("approval-gate.sh")
    trusted_environment = os.environ.copy()
    trusted_environment["AGENT_APPROVAL_PUBLIC_KEY"] = str(
        Path(pwd.getpwuid(os.getuid()).pw_dir) / ".config/agents/trust/approval-public.pem"
    )
    result = subprocess.run([
        "bash", str(gate), "--repo", str(repo), "--receipt", receipt,
        "--digest", request_digest, "--action", action, "--environment", environment,
    ], env=trusted_environment)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
