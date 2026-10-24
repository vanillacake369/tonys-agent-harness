"""Project manifest parsing, rendering, and validation."""

from __future__ import annotations

import json
from pathlib import Path
import tomllib

from agent_harness.domain.config import HarnessError, MANDATORY, PRESETS, PROVIDERS


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
spec_root = ".codex"\n\
\n\
[project.guides]\n\
enabled = false\n\
source = ""\n\
link = ".agent-context/team-guides"\n\
\n\
[providers]\n\
{provider_lines}\n\
\n\
[operations]\n\
profile = "default-allow-operations-v1"\n\
\n\
[workflow]\n\
public_commands = ["cmd-mid-work-ljh", "cmd-mid-comment-ljh", "cmd-post-blog-ljh", "cmd-post-handoff-ljh", "cmd-post-ship-ljh", "cmd-post-commit-ljh"]\n\
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
public_key_path = ""\n\
expected_fingerprint = ""\n\
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
    validate_project_inputs(data, project.resolve())
    return data


def inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def validate_project_inputs(data: dict, project: Path) -> None:
    project_config = data.get("project", {})
    spec_root = Path(project_config.get("spec_root", ".codex"))
    if spec_root.is_absolute() or ".." in spec_root.parts:
        raise HarnessError("project.spec_root must stay inside the project")
    guides = project_config.get("guides", {})
    if guides.get("enabled", False):
        source_value = guides.get("source", "")
        link = Path(guides.get("link", ".agent-context/team-guides"))
        if not source_value:
            raise HarnessError("project.guides.source is required when enabled")
        source = Path(source_value).expanduser()
        if not source.is_absolute() or not source.is_dir():
            raise HarnessError("project.guides.source must be an existing absolute directory")
        if link.is_absolute() or ".." in link.parts:
            raise HarnessError("project.guides.link must stay inside the project")
    approval = data.get("approval", {})
    trust_value = approval.get("public_key_path", "")
    fingerprint = approval.get("expected_fingerprint", "")
    if trust_value:
        trust = Path(trust_value).expanduser()
        if not trust.is_absolute():
            raise HarnessError("approval.public_key_path must be absolute")
        if inside(trust, project):
            raise HarnessError("approval public key must stay outside the project")
        if fingerprint and (len(fingerprint) != 64 or any(char not in "0123456789abcdef" for char in fingerprint.lower())):
            raise HarnessError("approval.expected_fingerprint must be a SHA-256 hex digest")


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
        raise HarnessError(f"UNKNOWN_PROVIDER: {', '.join(sorted(unknown))}")
    operations = data.get("operations", {})
    if not isinstance(operations, dict) or set(operations) - {"profile"}:
        raise HarnessError("operations must contain only profile")
    if operations.get("profile", "default-allow-operations-v1") != "default-allow-operations-v1":
        raise HarnessError("unsupported operations.profile")


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
