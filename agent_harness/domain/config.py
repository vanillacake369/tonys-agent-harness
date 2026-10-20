"""Domain configuration, errors, and stable digests."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[2]
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


def digest(value: dict) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def source_digest(config: dict, instruction: bytes) -> str:
    material = dict(config)
    material["instruction_sha256"] = hashlib.sha256(instruction).hexdigest()
    return digest(material)


def normalized(data: dict) -> dict:
    preset = PRESETS[data["preset"]]
    configured = data.get("providers", {})
    providers = [name for name in PROVIDERS if configured.get(name, name in preset["providers"])]
    return {
        "schema_version": 1,
        "preset": data["preset"],
        "project": {
            "instruction": data.get("project", {}).get("instruction", "AGENTS.md"),
            "spec_root": data.get("project", {}).get("spec_root", ".codex"),
            "guides": {
                "enabled": data.get("project", {}).get("guides", {}).get("enabled", False),
                "source": data.get("project", {}).get("guides", {}).get("source", ""),
                "link": data.get("project", {}).get("guides", {}).get("link", ".agent-context/team-guides"),
            },
        },
        "providers": providers,
        "workflow": data.get("workflow", {}),
        "permissions": {
            "secret_access": "deny", "reviewer_write": False,
            "researcher_write": False, "single_writer": True,
        },
        "approval": {
            "production": True, "destructive": True,
            "migration": True, "external_mutation": True,
            "public_key_path": data.get("approval", {}).get("public_key_path", ""),
            "expected_fingerprint": data.get("approval", {}).get("expected_fingerprint", ""),
        },
        "verification": data.get("verification", {"retry_max": 3}),
    }
