"""Pure Python semantic reference for typed permission decision fixtures."""

from __future__ import annotations

from pathlib import PurePosixPath
CONTRACT_VERSION = 2
KNOWN_PROVIDERS = {"codex", "claude", "gemini", "kiro"}


def _nonempty(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _decision(request: dict, decision: str, reason_code: str, grant_id=None) -> dict:
    return {
        "contract_version": CONTRACT_VERSION,
        "mode": "python-reference",
        "authoritative": False,
        "policy_revision": request.get("policy_revision", ""),
        "decision": decision,
        "reason_code": reason_code,
        "grant_id": grant_id,
    }


def _unavailable(request: dict, reason_code: str) -> dict:
    decision = "ASK" if request.get("provider_can_pause") is True else "DENY"
    return _decision(request, decision, reason_code)


def _valid_directory_target(value) -> bool:
    if not _nonempty(value) or not value.startswith("/"):
        return False
    return all(part not in (".", "..") for part in PurePosixPath(value).parts)


def _valid_network_target(value) -> bool:
    if not _nonempty(value):
        return False
    if "://" not in value:
        return False
    scheme, authority = value.split("://", 1)
    if scheme not in ("http", "https") or any(character in authority for character in "/?#@"):
        return False
    if ":" not in authority:
        return False
    host, port_text = authority.rsplit(":", 1)
    if not port_text.isascii() or not port_text.isdigit():
        return False
    port = int(port_text)
    if not 0 < port <= 65535:
        return False
    return not host.startswith(("-", ".")) and not host.endswith(("-", ".")) and all(
        label
        and not label.startswith("-")
        and not label.endswith("-")
        and all(character.isascii() and (character.isalnum() or character == "-") for character in label)
        for label in host.split(".")
    )


def _valid_resource(resource) -> bool:
    if not isinstance(resource, dict):
        return False
    resource_type = resource.get("resource_type")
    operation = resource.get("operation")
    target = resource.get("canonical_target")
    if resource_type == "directory":
        return operation in {"read", "write", "execute", "delete"} and _valid_directory_target(target)
    if resource_type == "network":
        return operation == "connect" and _valid_network_target(target)
    return False


def _valid_grant(grant, policy_revision: str) -> bool:
    if not isinstance(grant, dict):
        return False
    state = grant.get("state")
    termination = grant.get("termination_evidence")
    if state == "ACTIVE":
        valid_state = termination is None
    elif state in {"REVOKED", "EXPIRED"}:
        valid_state = _nonempty(termination)
    else:
        valid_state = False
    operations = grant.get("allowed_operations")
    resource_type = grant.get("resource_type")
    valid_operations = isinstance(operations, list) and bool(operations) and all(
        operation in ({"read", "write", "execute", "delete"} if resource_type == "directory" else {"connect"})
        for operation in operations
    )
    scope = grant.get("scope")
    end_condition = grant.get("end_condition")
    valid_scope = (
        scope == "task" and end_condition in {"task_end", "expiry"}
    ) or (
        scope == "session"
        and _nonempty(grant.get("session_id"))
        and end_condition in {"session_end", "expiry"}
    )
    return (
        all(_nonempty(grant.get(key)) for key in (
            "grant_id", "task_id", "role", "agent", "approval_identity", "evidence_ref"
        ))
        and grant.get("policy_revision") == policy_revision
        and valid_state
        and valid_operations
        and valid_scope
        and _valid_resource({
            "resource_type": resource_type,
            "canonical_target": grant.get("canonical_target"),
            "operation": operations[0] if operations else None,
        })
    )


def _identity_matches(grant: dict, request: dict) -> bool:
    return (
        grant.get("task_id") == request.get("task_id")
        and grant.get("role") == request.get("role")
        and grant.get("agent") == request.get("agent")
        and (grant.get("scope") == "task" or grant.get("session_id") == request.get("session_id"))
    )


def _resource_matches(grant: dict, resource: dict) -> bool:
    if grant.get("resource_type") != resource.get("resource_type"):
        return False
    if resource["resource_type"] == "network":
        return grant.get("canonical_target") == resource.get("canonical_target")
    try:
        PurePosixPath(resource["canonical_target"]).relative_to(PurePosixPath(grant["canonical_target"]))
        return True
    except (KeyError, TypeError, ValueError):
        return False


def decide(request: dict) -> dict:
    """Evaluate an already typed v2 request without side effects or authority."""
    if request.get("contract_version") != CONTRACT_VERSION:
        return _decision(request, "DENY", "unsupported_contract_version")
    if not all(_nonempty(request.get(key)) for key in (
        "request_id", "task_id", "role", "agent", "provider", "policy_revision"
    )) or not _valid_resource(request.get("resource")):
        return _decision(request, "DENY", "invalid_request")
    if request.get("secret_access") is True:
        return _decision(request, "DENY", "secret_access_forbidden")
    if request.get("external_mutation") is True:
        return _decision(request, "DENY", "external_mutation_requires_operation_approval")
    enforcement = request.get("enforcement")
    if (
        not isinstance(enforcement, dict)
        or request["provider"] not in KNOWN_PROVIDERS
        or enforcement.get("provider") != request["provider"]
        or not _nonempty(enforcement.get("provider_version"))
        or not _nonempty(enforcement.get("evidence_ref"))
    ):
        return _decision(request, "DENY", "invalid_enforcement_observation")
    resource = request["resource"]
    grant = next((grant for grant in request.get("grants", []) if (
        _valid_grant(grant, request["policy_revision"])
        and grant["state"] == "ACTIVE"
        and grant.get("expires_at", 0) > request.get("now", 0)
        and _identity_matches(grant, request)
        and _resource_matches(grant, resource)
        and resource["operation"] in grant["allowed_operations"]
    )), None)
    if grant is None:
        return _unavailable(request, "matching_active_grant_required")
    if enforcement.get("status") != "OBSERVED":
        return _unavailable(request, "enforcement_not_observed")
    return _decision(request, "ALLOW", "active_grant_observed", grant["grant_id"])
