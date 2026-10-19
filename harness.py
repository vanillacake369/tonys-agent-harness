#!/usr/bin/env python3
"""Provider-neutral agent harness CLI using only the Python standard library."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parent
PRESETS = {
    "minimal": {"providers": ["codex"], "roles": ["implementer", "reviewer"]},
    "application": {
        "providers": ["codex", "claude"],
        "roles": ["requirement-designer", "researcher", "implementer", "reviewer"],
    },
    "infra-devops": {
        "providers": ["codex", "claude", "kiro"],
        "roles": ["requirement-designer", "researcher", "architect", "implementer", "reviewer"],
    },
    "regulated": {
        "providers": ["codex", "claude", "gemini", "kiro"],
        "roles": ["requirement-designer", "researcher", "architect", "implementer", "reviewer"],
    },
}
MANDATORY = tomllib.loads((ROOT / "core/policy.toml").read_text())["mandatory"]
CAPABILITIES = tomllib.loads((ROOT / "core/providers.toml").read_text())
PROVIDERS = tuple(name for name in CAPABILITIES if name != "schema_version")
DEFAULT_PROJECT_GUIDE = """# Agent Operating Guide

This file is the provider-neutral instruction source for this project.

- Inspect repository rules and existing changes before editing.
- Keep changes scoped and preserve user-owned work.
- Run relevant verification and report actual evidence.
- Require explicit approval for destructive, production, migration, or external mutations.
- Treat generated provider files as adapters; keep shared behavior here.
"""


class HarnessError(Exception):
    pass


def manifest_path(project: Path) -> Path:
    return project / "agent-harness.toml"


def render_manifest(preset: str) -> str:
    selected = PRESETS[preset]
    provider_lines = "\n".join(f"{name} = {'true' if name in selected['providers'] else 'false'}" for name in PROVIDERS)
    roles = ", ".join(json.dumps(role) for role in selected["roles"])
    return f'''# Project-owned input for tonys-agent-harness.\n\
schema_version = 1\n\
preset = {json.dumps(preset)}\n\
\n\
[project]\n\
instruction = "AGENTS.md"\n\
spec_root = "docs/agent"\n\
\n\
[providers]\n\
{provider_lines}\n\
\n\
[workflow]\n\
public_commands = ["work", "comment", "handoff", "ship"]\n\
roles = [{roles}]\n\
\n\
[permissions]\n\
secret_access = "deny"\n\
reviewer_write = false\n\
researcher_write = false\n\
single_writer = true\n\
\n\
[approval]\n\
production = true\n\
destructive = true\n\
migration = true\n\
external_mutation = true\n\
\n\
[verification]\n\
retry_max = 3\n\
require_clean_git_for_done = true\n'''


def load_manifest(project: Path) -> dict:
    path = manifest_path(project)
    if not path.is_file():
        raise HarnessError(f"manifest missing: {path}")
    try:
        data = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise HarnessError(f"invalid manifest: {error}") from error
    if data.get("schema_version") != 1:
        raise HarnessError("unsupported schema_version; expected 1")
    if data.get("preset") not in PRESETS:
        raise HarnessError("unknown preset")
    validate_policy(data)
    return data


def validate_policy(data: dict) -> None:
    permissions = data.get("permissions", {})
    approval = data.get("approval", {})
    required = {
        "secret_access": MANDATORY["secret_access"],
        "reviewer_write": MANDATORY["reviewer_write"],
        "researcher_write": MANDATORY["researcher_write"],
        "single_writer": MANDATORY["single_writer"],
    }
    for key, expected in required.items():
        if permissions.get(key, expected) != expected:
            raise HarnessError(f"policy weakening rejected: permissions.{key}")
    for key in ("production", "destructive", "migration", "external_mutation"):
        if approval.get(key, True) is not True:
            raise HarnessError(f"policy weakening rejected: approval.{key}")
    retry = data.get("verification", {}).get("retry_max", 3)
    if not isinstance(retry, int) or isinstance(retry, bool) or retry < 1 or retry > 3:
        raise HarnessError("verification.retry_max must be between 1 and 3")
    providers = data.get("providers", {})
    if any(not isinstance(value, bool) for value in providers.values()):
        raise HarnessError("provider values must be booleans")
    unknown = set(providers) - set(PROVIDERS)
    if unknown:
        raise HarnessError(f"unknown providers: {', '.join(sorted(unknown))}")


def normalized(data: dict) -> dict:
    preset = PRESETS[data["preset"]]
    configured = data.get("providers", {})
    providers = [name for name in PROVIDERS if configured.get(name, name in preset["providers"])]
    return {
        "schema_version": 1,
        "preset": data["preset"],
        "project": data.get("project", {"instruction": "AGENTS.md", "spec_root": "docs/agent"}),
        "providers": providers,
        "workflow": data.get("workflow", {}),
        "permissions": {
            "secret_access": "deny", "reviewer_write": False,
            "researcher_write": False, "single_writer": True,
        },
        "approval": {
            "production": True, "destructive": True,
            "migration": True, "external_mutation": True,
        },
        "verification": data.get("verification", {"retry_max": 3}),
    }


def digest(value: dict) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def instruction_content(project: Path, config: dict) -> bytes:
    relative = Path(config.get("project", {}).get("instruction", "AGENTS.md"))
    if relative.is_absolute() or ".." in relative.parts:
        raise HarnessError("project.instruction must stay inside the project")
    path = (project / relative).resolve()
    try:
        path.relative_to(project.resolve())
    except ValueError as error:
        raise HarnessError("project.instruction must stay inside the project") from error
    if not path.is_file():
        raise HarnessError(f"project instruction missing: {path}")
    return path.read_bytes()


def source_digest(config: dict, instruction: bytes) -> str:
    material = dict(config)
    material["instruction_sha256"] = hashlib.sha256(instruction).hexdigest()
    return digest(material)


def target_files(config: dict, instruction: bytes) -> dict[str, bytes]:
    marker = f"# Generated by tonys-agent-harness; source digest: {source_digest(config, instruction)}\n"
    files: dict[str, bytes] = {}
    for provider in config["providers"]:
        files[f"{provider}/AGENTS.md"] = instruction
        if provider == "codex":
            files["codex/config.toml"] = (marker + '''default_permissions = "default"\n\n[[hooks.SessionStart]]\n[[hooks.SessionStart.hooks]]\ntype = "command"\ncommand = "python3 ~/.config/agents/governance/task-lifecycle.py start"\ntimeout = 10\n\n[[hooks.PreToolUse]]\nmatcher = "Bash"\n[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = "bash ~/.config/agents/governance/pre-tool-gate.sh"\ntimeout = 5\n\n[[hooks.PostToolUse]]\nmatcher = "Bash"\n[[hooks.PostToolUse.hooks]]\ntype = "command"\ncommand = "bash ~/.config/agents/governance/retry-hook.sh post"\ntimeout = 5\n\n[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "python3 ~/.config/agents/governance/task-lifecycle.py stop"\ntimeout = 10\n\n[permissions.default.filesystem]\n":minimal" = "read"\n"**/.env*" = "deny"\n"**/*credentials*" = "deny"\n"**/secrets/**" = "deny"\n"**/*private*key*" = "deny"\n\n[permissions.default.filesystem.":workspace_roots"]\n"." = "write"\n\n[permissions.agent-reviewer.filesystem]\n":minimal" = "read"\n"**/.env*" = "deny"\n"**/*credentials*" = "deny"\n"**/secrets/**" = "deny"\n"**/*private*key*" = "deny"\n\n[permissions.agent-reviewer.filesystem.":workspace_roots"]\n"." = "read"\n''').encode()
        elif provider == "claude":
            payload = {
                "generated": True,
                "sandbox": {"enabled": True, "autoAllowBashIfSandboxed": False},
                "reviewer": {"write": False},
                "hooks": {
                    "SessionStart": [{"hooks": [{"type": "command", "command": "python3 ~/.config/agents/governance/task-lifecycle.py start", "timeout": 10}]}],
                    "PreToolUse": [
                        {"matcher": "mcp__.*", "hooks": [{"type": "command", "command": "bash ~/.config/agents/governance/mcp-hook.sh", "timeout": 5}]},
                        {"matcher": "Bash|Read|Write|Edit|NotebookEdit", "hooks": [{"type": "command", "command": "bash ~/.config/agents/governance/pre-tool-gate.sh", "timeout": 5}]},
                    ],
                    "PostToolUseFailure": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.config/agents/governance/retry-hook.sh failure", "timeout": 5}]}],
                    "Stop": [{"hooks": [{"type": "command", "command": "python3 ~/.config/agents/governance/task-lifecycle.py stop", "timeout": 10}]}],
                },
            }
            files["claude/settings.json"] = (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode()
            files["claude/CLAUDE.md"] = b"@AGENTS.md\n"
            files["claude/agents/independent-reviewer.md"] = b'''---
name: independent-reviewer
description: Read-only independent review of requirements, diffs, tests, and evidence.
tools: Read, Grep, Glob
disallowedTools: Write, Edit, NotebookEdit, Bash
---

Review independently and return structured findings. Never mutate files.
'''
        elif provider == "gemini":
            payload = {
                "context": {"fileName": ["AGENTS.md"]},
                "hooks": {
                    "BeforeAgent": [{"hooks": [{"type": "command", "command": "python3 ~/.config/agents/governance/task-lifecycle.py start", "timeout": 10000}]}],
                    "BeforeTool": [{"matcher": "run_shell_command|read_file|write_file|replace|replace_in_file", "hooks": [{"type": "command", "command": "bash ~/.config/agents/governance/pre-tool-gate.sh", "timeout": 5000}]}],
                    "AfterTool": [{"matcher": "run_shell_command", "hooks": [{"type": "command", "command": "bash ~/.config/agents/governance/retry-hook.sh post", "timeout": 5000}]}],
                    "AfterAgent": [{"hooks": [{"type": "command", "command": "python3 ~/.config/agents/governance/task-lifecycle.py stop", "timeout": 5000}]}],
                },
            }
            files["gemini/settings.json"] = (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode()
        elif provider == "kiro":
            payload = {
                "name": "independent-reviewer", "tools": ["read"], "includeMcpJson": False,
                "permissions": {"fs_write": "deny", "secret_access": "deny"},
            }
            files["kiro/agents/independent-reviewer.json"] = (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode()
            hooks = {"hooks": [{"trigger": "AgentSpawn", "command": "python3 ~/.config/agents/governance/task-lifecycle.py start"}, {"trigger": "PreToolUse", "matcher": "execute_bash|fs_read|fs_write", "command": "bash ~/.config/agents/governance/pre-tool-gate.sh"}, {"trigger": "PostToolUse", "matcher": "execute_bash|fs_write", "command": "bash ~/.config/agents/governance/retry-hook.sh post"}, {"trigger": "Stop", "command": "bash ~/.config/agents/governance/kiro-stop.sh"}]}
            files["kiro/hooks/engineering-governance.json"] = (json.dumps(hooks, indent=2, sort_keys=True) + "\n").encode()
    retry_max = str(config.get("verification", {}).get("retry_max", 3))
    for name in ("codex/config.toml", "claude/settings.json", "gemini/settings.json", "kiro/hooks/engineering-governance.json"):
        if name in files:
            files[name] = files[name].replace(b"retry-hook.sh post", f"retry-hook.sh post {retry_max}".encode())
            files[name] = files[name].replace(b"retry-hook.sh failure", f"retry-hook.sh failure {retry_max}".encode())
    capabilities = {name: CAPABILITIES[name] for name in config["providers"]}
    files["capabilities.json"] = (json.dumps(capabilities, indent=2, sort_keys=True) + "\n").encode()
    skill_sources = sorted(path for path in (ROOT / "assets/skills").rglob("*") if path.is_file())
    command_sources = sorted((ROOT / "assets/commands").glob("cmd-vpp-*.md"))
    for provider in config["providers"]:
        for source in skill_sources:
            relative = source.relative_to(ROOT / "assets/skills")
            files[f"{provider}/skills/{relative}"] = source.read_bytes()
        for source in command_sources:
            if provider == "codex":
                body = source.read_text()
                rendered = f'''---\nname: workflow-{source.stem}\ndescription: "Public engineering command facade: {source.stem}"\n---\n\n# {source.stem}\n\n{body}'''
                files[f"codex/skills/workflow-{source.stem}/SKILL.md"] = rendered.encode()
            elif provider in ("claude", "gemini"):
                files[f"{provider}/commands/{source.name}"] = source.read_bytes()
            elif provider == "kiro":
                files[f"kiro/workflows/{source.name}"] = source.read_bytes()
    for source in sorted(path for path in (ROOT / "runtime").rglob("*")
                         if path.is_file() and "__pycache__" not in path.parts and path.suffix in {".sh", ".py"}):
        files[f"runtime/{source.relative_to(ROOT / 'runtime')}"] = source.read_bytes()
    files["install-map.json"] = (json.dumps({
        "runtime": "~/.config/agents",
        "providers": {name: f"~/.{name}" for name in config["providers"]},
        "activation": "consumer-owned-explicit-step",
    }, indent=2, sort_keys=True) + "\n").encode()
    return files


def plan(project: Path, output: Path) -> dict:
    config = normalized(load_manifest(project))
    instruction = instruction_content(project, config)
    files = target_files(config, instruction)
    return {
        "status": "READY", "source_digest": source_digest(config, instruction),
        "providers": config["providers"], "output": str(output),
        "files": sorted(files), "warnings": [], "errors": [],
    }


def export(project: Path, output: Path) -> dict:
    config = normalized(load_manifest(project))
    instruction = instruction_content(project, config)
    files = target_files(config, instruction)
    output_parent = output.parent
    output_parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.stage-", dir=output_parent))
    backup = Path(tempfile.mkdtemp(prefix=f".{output.name}.backup-", dir=output_parent))
    backup.rmdir()
    try:
        hashes = {}
        modes = {}
        for name, content in files.items():
            destination = stage / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
            mode = 0o755 if name.startswith("runtime/") and destination.suffix in (".sh", ".py") else 0o644
            destination.chmod(mode)
            hashes[name] = hashlib.sha256(content).hexdigest()
            modes[name] = mode
        export_manifest = {
            "schema_version": 1, "generated_by": "tonys-agent-harness",
            "source_digest": source_digest(config, instruction),
            "files": hashes, "modes": modes, "providers": config["providers"],
        }
        (stage / "manifest.json").write_text(json.dumps(export_manifest, indent=2, sort_keys=True) + "\n")
        if output.exists():
            current_manifest = output / "manifest.json"
            try:
                current = json.loads(current_manifest.read_text())
            except (OSError, json.JSONDecodeError):
                raise HarnessError(f"refusing to replace unmanaged output: {output}")
            if (
                current.get("generated_by") != "tonys-agent-harness"
                or current.get("schema_version") != 1
                or not isinstance(current.get("files"), dict)
                or not isinstance(current.get("modes"), dict)
            ):
                raise HarnessError(f"refusing to replace unmanaged output: {output}")
            current_files = {str(path.relative_to(output)) for path in output.rglob("*") if path.is_file()}
            managed_files = set(current["files"]) | {"manifest.json"}
            if current_files != managed_files:
                raise HarnessError(f"refusing to replace output with unmanaged or missing files: {output}")
            os.replace(output, backup)
        os.replace(stage, output)
        if backup.exists():
            shutil.rmtree(backup)
    except Exception:
        if stage.exists():
            shutil.rmtree(stage)
        if backup.exists() and not output.exists():
            os.replace(backup, output)
        raise
    return export_manifest


def verify(project: Path, output: Path) -> dict:
    config = normalized(load_manifest(project))
    instruction = instruction_content(project, config)
    manifest = output / "manifest.json"
    if not manifest.is_file():
        raise HarnessError("generated manifest missing")
    exported = json.loads(manifest.read_text())
    if exported.get("generated_by") != "tonys-agent-harness" or exported.get("schema_version") != 1:
        raise HarnessError("generated manifest ownership mismatch")
    if exported.get("source_digest") != source_digest(config, instruction):
        raise HarnessError("generated output is stale")
    expected = target_files(config, instruction)
    if set(exported.get("files", {})) != set(expected):
        raise HarnessError("generated inventory mismatch")
    actual_files = {str(path.relative_to(output)) for path in output.rglob("*") if path.is_file()}
    allowed_files = set(expected) | {"manifest.json"}
    unexpected = actual_files - allowed_files
    if unexpected:
        raise HarnessError(f"unexpected generated files: {', '.join(sorted(unexpected))}")
    for name, expected_content in expected.items():
        path = output / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != exported["files"][name]:
            raise HarnessError(f"generated file missing or tampered: {name}")
        if path.read_bytes() != expected_content:
            raise HarnessError(f"generated file stale: {name}")
        expected_mode = 0o755 if name.startswith("runtime/") and path.suffix in (".sh", ".py") else 0o644
        if path.stat().st_mode & 0o777 != expected_mode or exported.get("modes", {}).get(name) != expected_mode:
            raise HarnessError(f"generated file mode mismatch: {name}")
    return {"status": "PASS", "source_digest": source_digest(config, instruction), "files": len(expected)}


def command_init(args: argparse.Namespace) -> dict:
    if args.preset not in PRESETS:
        raise HarnessError(f"unknown preset: {args.preset}")
    path = manifest_path(args.project.resolve())
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x") as handle:
            handle.write(render_manifest(args.preset))
    except FileExistsError as error:
        raise HarnessError(f"refusing to overwrite existing manifest: {path}") from error
    instruction = args.project.resolve() / "AGENTS.md"
    instruction_created = False
    if not instruction.exists():
        instruction.write_text(DEFAULT_PROJECT_GUIDE)
        instruction_created = True
    return {
        "status": "CREATED", "manifest": str(path),
        "instruction": str(instruction), "instruction_created": instruction_created,
    }


def command_doctor(_: argparse.Namespace) -> dict:
    binaries = {name: shutil.which({"codex": "codex", "claude": "claude", "gemini": "gemini", "kiro": "kiro-cli"}[name]) for name in PROVIDERS}
    return {"status": "PASS", "python": sys.version.split()[0], "providers": binaries, "assets": asset_inventory()}


def asset_inventory() -> dict:
    skills = sorted(p.parent.name for p in (ROOT / "assets/skills").glob("*/SKILL.md"))
    commands = sorted(p.stem for p in (ROOT / "assets/commands").glob("cmd-vpp-*.md"))
    return {"skills": skills, "commands": commands}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="harness")
    sub = result.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init")
    init.add_argument("--project", type=Path, default=Path.cwd())
    init.add_argument("--preset", default="minimal", choices=sorted(PRESETS))
    init.set_defaults(handler=command_init)
    doctor = sub.add_parser("doctor")
    doctor.set_defaults(handler=command_doctor)
    for name in ("plan", "export", "verify"):
        command = sub.add_parser(name)
        command.add_argument("--project", type=Path, default=Path.cwd())
        command.add_argument("--output", type=Path)
        command.set_defaults(handler={
            "plan": lambda a: plan(
                a.project.resolve(),
                a.output.resolve() if a.output else a.project.resolve() / "build/agent-harness",
            ),
            "export": lambda a: export(
                a.project.resolve(),
                a.output.resolve() if a.output else a.project.resolve() / "build/agent-harness",
            ),
            "verify": lambda a: verify(
                a.project.resolve(),
                a.output.resolve() if a.output else a.project.resolve() / "build/agent-harness",
            ),
        }[name])
    return result


def main() -> int:
    try:
        args = parser().parse_args()
        print(json.dumps(args.handler(args), indent=2, sort_keys=True))
        return 0
    except (HarnessError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"harness: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
