#!/usr/bin/env python3
"""Upsert harness-owned provider fragments into mutable native settings."""
from __future__ import annotations
import argparse, json, os, shutil, stat, tempfile, time
from pathlib import Path
import tomllib

FRAGMENT_IDS = ("harness-operation-policy-v1", "harness-policy-preflight-v1", "harness-path-invariants-v1")
LEGACY_POLICY_COMMANDS = ("pre-tool-gate.sh", "policy-preflight.py")

def managed(value) -> bool:
    if isinstance(value, str): return any(fragment_id in value for fragment_id in FRAGMENT_IDS)
    if isinstance(value, list): return any(managed(item) for item in value)
    if isinstance(value, dict): return any(managed(item) for item in value.values())
    return False

def legacy_policy(value) -> bool:
    if isinstance(value, str): return any(command in value for command in LEGACY_POLICY_COMMANDS)
    if isinstance(value, list): return any(legacy_policy(item) for item in value)
    if isinstance(value, dict): return any(legacy_policy(item) for item in value.values())
    return False

def merge(existing, desired):
    if isinstance(existing, dict) and isinstance(desired, dict):
        result = dict(existing)
        for key, value in desired.items():
            if key == "hooks" and isinstance(value, dict): result[key] = merge_hooks(existing.get(key, {}), value)
            elif key == "hooks" and isinstance(value, list): result[key] = merge_hook_list(existing.get(key, []), value)
            elif key in {"permissions", "features"} and isinstance(value, dict):
                result[key] = dict(existing.get(key, {})) if isinstance(existing.get(key), dict) else {}
                result[key].update(value)
            elif key in {"default_permissions", "approval_policy"}: result[key] = value
            elif key not in result: result[key] = value
        return result
    return desired

def merge_hook_list(existing, desired):
    old = existing if isinstance(existing, list) else []
    preserved = [entry for entry in old if not managed(entry) and not legacy_policy(entry)]
    return preserved + [entry for entry in desired if managed(entry) or entry not in preserved]

def merge_hooks(existing, desired):
    result = dict(existing) if isinstance(existing, dict) else {}
    for event, entries in desired.items():
        old = result.get(event, [])
        if isinstance(old, list) and isinstance(entries, list):
            preserved = [entry for entry in old if not managed(entry) and not legacy_policy(entry)]
            result[event] = preserved + [entry for entry in entries if managed(entry) or entry not in preserved]
        else: result[event] = entries
    return result

def remove_fragments(value):
    if isinstance(value, list): return [remove_fragments(item) for item in value if not managed(item)]
    if isinstance(value, dict): return {key: remove_fragments(item) for key, item in value.items()}
    return value

def owned_snapshot(existing):
    def field(container, key):
        return {"present": isinstance(container, dict) and key in container, "value": container.get(key) if isinstance(container, dict) else None}
    permissions = existing.get("permissions", {}) if isinstance(existing, dict) else {}
    features = existing.get("features", {}) if isinstance(existing, dict) else {}
    return {
        "default_permissions": field(existing, "default_permissions"),
        "approval_policy": field(existing, "approval_policy"),
        "permission_profile": field(permissions, "default-allow-operations-v1"),
        "network_proxy": field(features, "network_proxy"),
    }

def refresh_snapshot(existing, desired, prior):
    """Retain the pre-managed value unless the user changed an owned field."""
    current = owned_snapshot(existing)
    managed_values = owned_snapshot(desired)
    result = dict(prior or current)
    for key, state in current.items():
        if state != managed_values[key]:
            result[key] = state
    return result

def restore_field(container, key, state):
    if state.get("present"): container[key] = state.get("value")
    else: container.pop(key, None)

def rollback(existing, prior=None):
    result = remove_fragments(existing)
    if not isinstance(result, dict): return result
    permissions = result.get("permissions")
    if not isinstance(permissions, dict): permissions = {}; result["permissions"] = permissions
    features = result.get("features")
    if not isinstance(features, dict): features = {}; result["features"] = features
    if prior:
        restore_field(result, "default_permissions", prior["default_permissions"])
        restore_field(result, "approval_policy", prior["approval_policy"])
        restore_field(permissions, "default-allow-operations-v1", prior["permission_profile"])
        restore_field(features, "network_proxy", prior["network_proxy"])
    else:
        if result.get("default_permissions") == "default-allow-operations-v1": result["default_permissions"] = "default"
        permissions.pop("default-allow-operations-v1", None)
    if not permissions: result.pop("permissions", None)
    if not features: result.pop("features", None)
    return result

def atomic_write(path: Path, output: str) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(output); handle.flush(); os.fsync(handle.fileno())
        os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR); os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)

def backup(target: Path) -> None:
    if not target.exists() and not target.is_symlink(): return
    stamp = time.strftime("%Y%m%d%H%M%S")
    candidate = target.with_name(f"{target.name}.backup.{stamp}")
    suffix = 0
    while candidate.exists():
        suffix += 1; candidate = target.with_name(f"{target.name}.backup.{stamp}.{suffix}")
    shutil.copy2(target, candidate, follow_symlinks=True); os.chmod(candidate, 0o600)
    backups = sorted(target.parent.glob(f"{target.name}.backup.*"), key=lambda path: path.stat().st_mtime, reverse=True)
    for stale in backups[3:]: stale.unlink()

def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--format", choices=("json", "toml"), required=True)
    parser.add_argument("--target", required=True); parser.add_argument("--source"); parser.add_argument("--remove-fragments", action="store_true")
    args = parser.parse_args(); target = Path(args.target).expanduser(); source = Path(args.source) if args.source else None
    if not args.remove_fragments and source is None: parser.error("--source is required unless --remove-fragments is used")
    target.parent.mkdir(parents=True, exist_ok=True); backup(target)
    state_path = target.with_name(f"{target.name}.harness-state.json")
    if args.format == "json":
        if target.exists(): existing = json.loads(target.read_text())
        else: existing = {}
        desired = json.loads(source.read_text()) if source else {}
        prior = json.loads(state_path.read_text()) if args.remove_fragments and state_path.exists() else None
        output = json.dumps(rollback(existing, prior) if args.remove_fragments else merge(existing, desired), indent=2, sort_keys=True) + "\n"
    else:
        try:
            import tomli_w
        except ImportError:  # Developer shells commonly expose the compatible `toml` writer.
            import toml as tomli_w
        if target.exists():
            with target.open("rb") as handle: existing = tomllib.load(handle)
        else: existing = {}
        if source:
            with source.open("rb") as handle: desired = tomllib.load(handle)
        else: desired = {}
        prior = json.loads(state_path.read_text()) if args.remove_fragments and state_path.exists() else None
        output = tomli_w.dumps(rollback(existing, prior) if args.remove_fragments else merge(existing, desired))
    if not args.remove_fragments:
        prior = json.loads(state_path.read_text()) if state_path.exists() else None
        snapshot = refresh_snapshot(existing, desired, prior) if prior else owned_snapshot(existing)
        atomic_write(state_path, json.dumps(snapshot, indent=2, sort_keys=True) + "\n")
    atomic_write(target, output)
    if args.remove_fragments and state_path.exists(): state_path.unlink()
    return 0

if __name__ == "__main__": raise SystemExit(main())
