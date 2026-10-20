"""Plan, export, verify, guide reconciliation, and approval trust."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from agent_harness.domain.config import HarnessError, digest, normalized, source_digest
from agent_harness.egress.providers import target_files
from agent_harness.ingress.manifest import inside, instruction_content, load_manifest


def approval_trust_status(project: Path, config: dict) -> str:
    approval = config["approval"]
    value = approval.get("public_key_path", "")
    if not value:
        return "UNPROVISIONED"
    path = Path(value).expanduser()
    if not path.is_file():
        return "UNPROVISIONED"
    if inside(path, project):
        raise HarnessError("approval public key must stay outside the project")
    pem = path.read_bytes()
    if b"-----BEGIN PUBLIC KEY-----" not in pem or b"PRIVATE KEY" in pem:
        raise HarnessError("approval trust path must contain a valid public key")
    openssl = shutil.which("openssl")
    if openssl is None:
        raise HarnessError("openssl is required to validate the approval public key")
    validation = subprocess.run(
        [openssl, "pkey", "-pubin", "-in", str(path), "-noout"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if validation.returncode != 0:
        raise HarnessError("approval trust path must contain a valid public key")
    actual = hashlib.sha256(pem).hexdigest()
    expected = approval.get("expected_fingerprint", "")
    if expected and actual != expected.lower():
        raise HarnessError("approval public key fingerprint mismatch")
    return "PROVISIONED"


def plan(project: Path, output: Path) -> dict:
    config = normalized(load_manifest(project))
    instruction = instruction_content(project, config)
    files = target_files(config, instruction)
    desired = source_digest(config, instruction)
    observed = None
    reconciliation_status = "NOT_APPLIED"
    warnings = []
    manifest = output / "manifest.json"
    if output.exists():
        try:
            current = json.loads(manifest.read_text())
            observed = current.get("source_digest")
            reconciliation_status = "IN_SYNC" if observed == desired else "DRIFTED"
            if reconciliation_status == "DRIFTED":
                warnings.append("generated output does not match desired source digest")
        except (OSError, json.JSONDecodeError):
            reconciliation_status = "UNMANAGED"
            warnings.append("output exists without a readable harness manifest")
    return {
        "status": "READY", "contract_version": 1, "source_digest": desired,
        "desired_digest": desired, "observed_digest": observed,
        "reconciliation_status": reconciliation_status,
        "providers": config["providers"], "output": str(output),
        "provider_status": {provider: "STATICALLY_VERIFIED" for provider in config["providers"]},
        "normalized_config_digest": digest(config),
        "approval_trust_status": approval_trust_status(project, config),
        "files": sorted(files), "warnings": warnings, "errors": [],
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
            "contract_version": 1, "schema_version": 1, "generated_by": "tonys-agent-harness",
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
    return {
        "status": "PASS",
        "contract_version": 1,
        "source_digest": source_digest(config, instruction),
        "files": len(expected),
    }


def reconcile_guides(project: Path, workspace: Path | None = None) -> dict:
    config = normalized(load_manifest(project))
    workspace = workspace or project
    guides = config["project"]["guides"]
    if not guides["enabled"]:
        return {"status": "DISABLED", "changed": False}
    source = Path(guides["source"]).expanduser().resolve()
    link = workspace / guides["link"]
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink():
        if link.resolve() == source:
            return {"status": "READY", "changed": False, "link": str(link), "source": str(source)}
        raise HarnessError(f"refusing to replace existing symlink: {link}")
    if link.exists():
        raise HarnessError(f"refusing to replace user-owned guide path: {link}")
    link.symlink_to(source, target_is_directory=True)
    return {"status": "READY", "changed": True, "link": str(link), "source": str(source)}
