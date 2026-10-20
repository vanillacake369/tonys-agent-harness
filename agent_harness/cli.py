"""Command handlers, parser construction, and CLI entrypoint."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys

from agent_harness.control_plane.reconcile import export, plan, reconcile_guides, verify
from agent_harness.domain.config import DEFAULT_PROJECT_GUIDE, HarnessError, PRESETS, PROVIDERS, ROOT, normalized
from agent_harness.ingress.manifest import load_manifest, manifest_path, render_manifest

PUBLIC_CONTRACT_VERSION = 1
PUBLIC_VALIDATION_COMMANDS = ["validate", "doctor", "plan", "export", "verify"]


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
    return {"status": "CREATED", "manifest": str(path), "instruction": str(instruction), "instruction_created": instruction_created}


def asset_inventory() -> dict:
    skills = sorted(p.parent.name for p in (ROOT / "assets/skills").glob("*/SKILL.md"))
    commands = sorted(p.stem for p in (ROOT / "assets/commands").glob("cmd-*.md"))
    return {"skills": skills, "commands": commands}


def command_doctor(_: argparse.Namespace) -> dict:
    binaries = {name: shutil.which({"codex": "codex", "claude": "claude", "gemini": "gemini", "kiro": "kiro-cli"}[name]) for name in PROVIDERS}
    return {
        "status": "PASS",
        "contract_version": PUBLIC_CONTRACT_VERSION,
        "python": sys.version.split()[0],
        "providers": binaries,
        "assets": asset_inventory(),
    }


def command_validate(args: argparse.Namespace) -> dict:
    config = normalized(load_manifest(args.project.resolve()))
    return {
        "status": "PASS",
        "contract_version": PUBLIC_CONTRACT_VERSION,
        "schema_version": config["schema_version"],
        "providers": config["providers"],
        "commands": PUBLIC_VALIDATION_COMMANDS,
    }


def command_normalize(args: argparse.Namespace) -> dict:
    return normalized(load_manifest(args.project.resolve()))


def command_reconcile_guides(args: argparse.Namespace) -> dict:
    return reconcile_guides(
        args.project.resolve(),
        args.workspace.resolve() if args.workspace else args.project.resolve(),
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="harness")
    sub = result.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init")
    init.add_argument("--project", type=Path, default=Path.cwd())
    init.add_argument("--preset", default="minimal", choices=sorted(PRESETS))
    init.set_defaults(handler=command_init)
    doctor = sub.add_parser("doctor")
    doctor.set_defaults(handler=command_doctor)
    validate = sub.add_parser("validate")
    validate.add_argument("--project", type=Path, default=Path.cwd())
    validate.set_defaults(handler=command_validate)
    normalize_command = sub.add_parser("normalize")
    normalize_command.add_argument("--project", type=Path, default=Path.cwd())
    normalize_command.set_defaults(handler=command_normalize)
    guides_command = sub.add_parser("reconcile-guides")
    guides_command.add_argument("--project", type=Path, default=Path.cwd())
    guides_command.add_argument("--workspace", type=Path)
    guides_command.set_defaults(handler=command_reconcile_guides)
    for name in ("plan", "export", "verify"):
        command = sub.add_parser(name)
        command.add_argument("--project", type=Path, default=Path.cwd())
        command.add_argument("--output", type=Path)
        command.set_defaults(handler={
            "plan": lambda a: plan(a.project.resolve(), a.output.resolve() if a.output else a.project.resolve() / "build/agent-harness"),
            "export": lambda a: export(a.project.resolve(), a.output.resolve() if a.output else a.project.resolve() / "build/agent-harness"),
            "verify": lambda a: verify(a.project.resolve(), a.output.resolve() if a.output else a.project.resolve() / "build/agent-harness"),
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
