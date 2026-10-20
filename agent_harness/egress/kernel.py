"""Read-only observation port for the non-authoritative Rust decision kernel."""

from __future__ import annotations

import json
import os
from pathlib import Path
import resource
import subprocess
import tempfile

from agent_harness.domain.config import HarnessError
from agent_harness.domain.permissions import decide, validate_typed_request


SEMANTIC_FIELDS = (
    "contract_version",
    "decision",
    "grant_id",
    "policy_revision",
    "reason_code",
)
MAX_KERNEL_OUTPUT = 64 * 1024


def _limit_output_files() -> None:
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_KERNEL_OUTPUT + 1, MAX_KERNEL_OUTPUT + 1))


def compare_decisions(request: dict, kernel: Path) -> dict:
    """Run both pure evaluators and report parity without selecting a decision."""
    try:
        validate_typed_request(request)
    except ValueError as error:
        raise HarnessError(str(error)) from error
    reference = decide(request)
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            completed = subprocess.run(
                [str(kernel)],
                input=json.dumps(request).encode(),
                stdout=stdout,
                stderr=stderr,
                timeout=5,
                check=False,
                env={"PATH": os.environ.get("PATH", ""), "LANG": "C.UTF-8"},
                preexec_fn=_limit_output_files,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise HarnessError(f"Rust shadow kernel unavailable: {error}") from error
        if stdout.tell() > MAX_KERNEL_OUTPUT or stderr.tell() > MAX_KERNEL_OUTPUT:
            raise HarnessError("Rust shadow kernel exceeded the output limit")
        stdout.seek(0)
        raw_output = stdout.read(MAX_KERNEL_OUTPUT + 1)
    if completed.returncode != 0:
        raise HarnessError(f"Rust shadow kernel failed with exit code {completed.returncode}")
    try:
        shadow = json.loads(raw_output)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise HarnessError("Rust shadow kernel returned invalid JSON") from error
    expected_fields = set(SEMANTIC_FIELDS) | {"mode", "authoritative"}
    if (
        not isinstance(shadow, dict)
        or set(shadow) != expected_fields
        or shadow.get("mode") != "shadow"
        or shadow.get("authoritative") is not False
        or shadow.get("contract_version") != 2
        or shadow.get("decision") not in {"ALLOW", "ASK", "DENY"}
        or not isinstance(shadow.get("policy_revision"), str)
        or not isinstance(shadow.get("reason_code"), str)
        or not shadow["reason_code"]
        or (
            shadow.get("grant_id") is not None
            and (not isinstance(shadow["grant_id"], str) or not shadow["grant_id"])
        )
    ):
        raise HarnessError("Rust shadow kernel returned an invalid observation envelope")
    differences = sorted(
        field for field in SEMANTIC_FIELDS if reference.get(field) != shadow.get(field)
    )
    return {
        "status": "IN_SYNC" if not differences else "DRIFTED",
        "authoritative": False,
        "differences": differences,
        "python_reference": reference,
        "rust_shadow": shadow,
    }
