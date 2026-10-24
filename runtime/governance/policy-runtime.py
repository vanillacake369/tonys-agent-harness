#!/usr/bin/env python3
"""Single authoritative v2 operation-policy runtime."""
from __future__ import annotations

import argparse
import contextlib
from dataclasses import asdict, dataclass
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time
import tomllib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from operation_policy import PROFILE, SUPPORTED_PROVIDERS, classify  # noqa: E402


SCHEMA_VERSION = 2
POLICY_REVISION = "default-allow-operations-v2"
FRAGMENTS = (
    "harness-operation-policy-v1",
    "harness-policy-preflight-v1",
    "harness-path-invariants-v1",
)
VALID_STATES = {"PENDING", "ENFORCED", "FAILED", "UNAVAILABLE", "UNSUPPORTED"}
PROVIDER_BINARIES = {"codex": "codex", "claude": "claude", "gemini": "gemini", "kiro": "kiro-cli"}
PORTER_RULES = {
    "codex": {"cli": re.compile(r"^codex-cli \d+\.\d+\.\d+(?:[-+][^\s]+)?$")},
    "claude": {"cli": re.compile(r"^(?:claude(?:-code)?\s+)?\d+\.\d+\.\d+(?:[-+][^\s]+)?(?: \(Claude Code\))?$")},
    "gemini": {"cli": re.compile(r"^(?:gemini(?:-cli)?\s+)?\d+\.\d+\.\d+(?:[-+][^\s]+)?$")},
    "kiro": {"cli": re.compile(r"^kiro-cli \d+\.\d+\.\d+(?:[-+][^\s]+)?$")},
}
SENSITIVE = re.compile(
    r"(^|[\s/])(?:\.env(?:[.\s/]|$)|secrets?(?:[\s/]|$)|credentials?(?:[\s/]|$)|\.ssh(?:[\s/]|$)|\.gnupg(?:[\s/]|$))|(?:private[_-]?key|id_rsa|\.(?:pem|key))(?:[\s/]|$)",
    re.I,
)


@dataclass(frozen=True)
class Observation:
    fingerprint: str
    runtime_identity: dict
    provider_version: str
    managed_fragment: object


@dataclass(frozen=True)
class RuntimeDecision:
    decision: str
    family: str
    reason_id: str
    sensitive: bool = False


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def runtime_identity(path: Path) -> dict:
    resolved = path.expanduser().resolve(strict=True)
    info = resolved.stat()
    if not stat.S_ISREG(info.st_mode) or not os.access(resolved, os.X_OK):
        raise OSError("provider executable unavailable")
    return {
        "path": str(resolved),
        "device": info.st_dev,
        "inode": info.st_ino,
        "size": info.st_size,
        "mtime_ns": info.st_mtime_ns,
    }


def _contains_fragment(value: object) -> bool:
    if isinstance(value, str):
        return any(fragment in value for fragment in FRAGMENTS)
    if isinstance(value, list):
        return any(_contains_fragment(item) for item in value)
    if isinstance(value, dict):
        return any(_contains_fragment(item) for item in value.values())
    return False


def _extract_managed(value: object) -> object:
    if isinstance(value, list):
        return [_extract_managed(item) for item in value if _contains_fragment(item)]
    if isinstance(value, dict):
        if (
            any(isinstance(item, str) and _contains_fragment(item) for item in value.values())
            or ("hooks" in value and isinstance(value["hooks"], list) and _contains_fragment(value["hooks"]))
        ):
            return value
        result = {}
        for key, item in value.items():
            if key == PROFILE or _contains_fragment(item):
                result[key] = _extract_managed(item)
        return result
    return value


def load_native(provider: str, config: Path) -> dict:
    if config.is_symlink():
        raise ValueError("native config symlink rejected")
    if provider == "codex":
        with config.open("rb") as handle:
            value = tomllib.load(handle)
    else:
        value = json.loads(config.read_text())
    if not isinstance(value, dict):
        raise ValueError("native config must be an object")
    return value


def _commands(entries: object, context: dict | None = None) -> list[tuple[dict, str]]:
    found: list[tuple[dict, str]] = []
    context = context or {}
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                effective = context | entry
                command = entry.get("command")
                if isinstance(command, str):
                    found.append((effective, command))
                found.extend(_commands(entry.get("hooks"), effective))
    return found


def validate_managed_structure(provider: str, native: dict) -> None:
    hooks = native.get("hooks")
    if not isinstance(hooks, dict) and provider != "kiro":
        raise ValueError("managed hook structure missing")
    if provider in {"codex", "claude"}:
        startup = _commands(hooks.get("SessionStart"))
        pretool = _commands(hooks.get("PreToolUse"))
        if not any("policy-runtime.py startup" in command and "harness-policy-preflight-v1" in command for _, command in startup):
            raise ValueError("managed startup hook missing")
        if not any(entry.get("matcher") == "Bash" and "policy-runtime.py pretool" in command and "harness-operation-policy-v1" in command for entry, command in pretool):
            raise ValueError("managed blocking hook missing")
        if provider == "claude" and not any(entry.get("matcher") == "Read|Write|Edit|NotebookEdit" and "policy-runtime.py pretool" in command and "harness-path-invariants-v1" in command for entry, command in pretool):
            raise ValueError("managed path hook missing")
    elif provider == "gemini":
        startup = _commands(hooks.get("BeforeAgent"))
        pretool = _commands(hooks.get("BeforeTool"))
        if not any("policy-runtime.py startup" in command and "harness-policy-preflight-v1" in command for _, command in startup):
            raise ValueError("managed startup hook missing")
        expected = "run_shell_command|read_file|write_file|replace|replace_in_file"
        if not any(entry.get("matcher") == expected and "policy-runtime.py pretool" in command and "harness-operation-policy-v1" in command for entry, command in pretool):
            raise ValueError("managed blocking hook missing")
    else:
        entries = native.get("hooks")
        if not isinstance(entries, list):
            raise ValueError("managed hook structure missing")
        def kiro_command(entry: dict) -> str:
            action = entry.get("action")
            return str(entry.get("command", action.get("command", "") if isinstance(action, dict) else ""))

        if not any(entry.get("trigger") == "AgentSpawn" and "policy-runtime.py startup" in kiro_command(entry) and entry.get("name") == "harness-policy-preflight-v1" for entry in entries if isinstance(entry, dict)):
            raise ValueError("managed startup hook missing")
        required = {
            (frozenset(("execute_bash", "execute_pwsh")), "harness-operation-policy-v1"),
            (frozenset(("fs_read", "fs_write", "fs_append", "str_replace", "delete_file")), "harness-path-invariants-v1"),
        }
        actual = set()
        for entry in entries:
            if not isinstance(entry, dict) or entry.get("trigger") != "PreToolUse" or "policy-runtime.py pretool" not in kiro_command(entry):
                continue
            matcher = str(entry.get("matcher", "")).strip("^$()")
            actual.add((frozenset(filter(None, matcher.split("|"))), entry.get("name")))
        if not required <= actual:
            raise ValueError("managed blocking hook missing")


def managed_fragment(provider: str, config: Path) -> object:
    native = load_native(provider, config)
    validate_managed_structure(provider, native)
    extracted = _extract_managed(native)
    if not _contains_fragment(extracted):
        raise ValueError("managed policy fragment missing")
    if provider == "codex" and native.get("default_permissions") != PROFILE:
        raise ValueError("managed permission profile missing")
    return extracted


def observe(provider: str, surface: str, config: Path, executable: Path, provider_version: str) -> Observation:
    identity = runtime_identity(executable)
    fragment = managed_fragment(provider, config)
    document = {
        "harness_revision": os.environ.get("AGENT_HARNESS_REVISION", "development"),
        "policy_revision": POLICY_REVISION,
        "provider": provider,
        "profile": PROFILE,
        "provider_version": provider_version,
        "surface": surface,
        "managed_fragment": fragment,
        "runtime_identity": identity,
    }
    return Observation(hashlib.sha256(canonical(document)).hexdigest(), identity, provider_version, fragment)


def toml_dump_for_test(value: dict) -> str:
    try:
        import tomli_w
    except ImportError:
        import toml as tomli_w
    return tomli_w.dumps(value)


def state_root() -> Path:
    root = Path(os.environ.get("AGENT_POLICY_STATE_DIR", Path.home() / ".local/state/agent-harness"))
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if root.is_symlink():
        raise OSError("state directory symlink rejected")
    os.chmod(root, 0o700)
    return root


def state_path(root: Path, provider: str, profile: str) -> Path:
    safe = re.sub(r"[^a-zA-Z0-9_.-]", "_", profile)
    return root / f"provider-{provider}-{safe}.json"


def atomic_write(path: Path, content: str) -> None:
    if path.exists() and path.is_symlink():
        raise OSError("state symlink rejected")
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_state(path: Path) -> dict | None:
    if not path.exists():
        return None
    if path.is_symlink() or path.stat().st_mode & 0o077:
        raise ValueError("unsafe state record")
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or value.get("schema_version") != SCHEMA_VERSION or value.get("status") not in VALID_STATES:
        raise ValueError("invalid state schema")
    return value


def write_state(path: Path, provider: str, surface: str, status: str, observation: Observation | None, now: int, reason: str | None = None, retry_after: int | None = None) -> dict:
    record = {
        "schema_version": SCHEMA_VERSION,
        "policy_revision": POLICY_REVISION,
        "provider": provider,
        "profile": PROFILE,
        "surface": surface,
        "status": status,
        "fingerprint": observation.fingerprint if observation else None,
        "provider_version": observation.provider_version if observation else None,
        "runtime_identity": observation.runtime_identity if observation else None,
        "checked_at": now,
        "failed_at": now if status == "FAILED" else None,
        "retry_after": retry_after,
        "reason_id": reason,
    }
    atomic_write(path, json.dumps(record, sort_keys=True) + "\n")
    return record


def observation_from_state(state: dict) -> Observation | None:
    if not state.get("fingerprint") or not state.get("runtime_identity") or not state.get("provider_version"):
        return None
    return Observation(state["fingerprint"], state["runtime_identity"], state["provider_version"], {})


@contextlib.contextmanager
def transition_lock(root: Path, provider: str, profile: str, timeout: float = 0.075):
    path = root / f".{provider}-{hashlib.sha256(profile.encode()).hexdigest()[:12]}.lock"
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    deadline = time.monotonic() + timeout
    acquired = False
    try:
        while time.monotonic() < deadline:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
                break
            except BlockingIOError:
                time.sleep(0.002)
        if not acquired:
            raise TimeoutError("activation transition lock timeout")
        yield
    finally:
        if acquired:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def normalize_payload(provider: str, payload: dict) -> tuple[str, str]:
    if not isinstance(payload, dict):
        raise ValueError("invalid hook payload")
    tool_name = payload.get("tool_name", payload.get("toolName", payload.get("name")))
    tool_input = payload.get("tool_input", payload.get("toolInput", payload.get("input")))
    if not isinstance(tool_name, str) or not isinstance(tool_input, dict):
        raise ValueError("invalid hook payload")
    command = tool_input.get("command", tool_input.get("cmd", ""))
    path = tool_input.get("file_path", tool_input.get("filePath", tool_input.get("path", tool_input.get("notebook_path", ""))))
    if command and not isinstance(command, str) or path and not isinstance(path, str):
        raise ValueError("invalid hook payload")
    return command, path


def privacy_tainted(command: str, path: str) -> bool:
    return bool(SENSITIVE.search(f"{command} {path}"))


def decide(command: str, path: str) -> RuntimeDecision:
    text = f"{command} {path}"
    if privacy_tainted(command, path):
        return RuntimeDecision("DENY", "filesystem", "sensitive_path", True)
    if path:
        return RuntimeDecision("ALLOW", "unclassified", "default_allow")
    result = classify(command)
    return RuntimeDecision(result.decision, result.family, result.reason_code)


def _feedback_lock(root: Path):
    return transition_lock(root, "feedback", PROFILE, timeout=0.075)


def feedback(root: Path, provider: str, surface: str, decision: RuntimeDecision, raw: str, tainted: bool, now: int, fingerprint: str | None = None) -> str:
    digest = hashlib.sha256(raw.encode()).hexdigest()
    event = {
        "timestamp": now,
        "provider": provider,
        "surface": surface,
        "family": decision.family,
        "reason_id": decision.reason_id,
        "policy_revision": POLICY_REVISION,
        "fingerprint": fingerprint,
        "command_hash": digest,
    }
    should_notify = False
    try:
        with _feedback_lock(root):
            telemetry = root / "operation-denials.jsonl"
            descriptor = os.open(telemetry, os.O_CREAT | os.O_WRONLY | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0), 0o600)
            try:
                os.write(descriptor, canonical(event) + b"\n")
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            os.chmod(telemetry, 0o600)
            dedupe = root / "notification-dedupe.json"
            try:
                entries = json.loads(dedupe.read_text()) if dedupe.exists() and not dedupe.is_symlink() else {}
                if not isinstance(entries, dict):
                    entries = {}
            except (OSError, json.JSONDecodeError):
                entries = {}
            session = os.environ.get("AGENT_SESSION_ID", "unknown")
            key = f"{session}:{digest}:{decision.reason_id}"
            should_notify = now - int(entries.get(key, 0)) >= 60
            entries = {key_: stamp for key_, stamp in entries.items() if isinstance(stamp, int) and now - stamp < 60}
            if should_notify:
                entries[key] = now
            atomic_write(dedupe, json.dumps(entries, sort_keys=True) + "\n")
    except (OSError, TimeoutError, ValueError, json.JSONDecodeError):
        # Feedback persistence is best-effort and must never weaken or replace DENY.
        should_notify = True
    if should_notify:
        notifier = Path(os.environ.get("AGENT_NOTIFY_HOOK", Path.home() / ".config/agents/hooks/agent-notify.sh"))
        if notifier.is_file() and os.access(notifier, os.X_OK):
            try:
                subprocess.run([str(notifier), f"blocked:{decision.family}:{decision.reason_id}"], timeout=0.02, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            except (OSError, subprocess.TimeoutExpired):
                pass
    detail = "[redacted]" if tainted or decision.sensitive else raw
    return f"operation policy blocked [{decision.reason_id}]: {detail}\n이 작업은 직접 검토가 필요합니다. 필요하다면 사용자가 실행한 뒤 결과를 알려주세요."


def default_config(provider: str) -> Path:
    return {
        "codex": Path.home() / ".codex/config.toml",
        "claude": Path.home() / ".claude/settings.json",
        "gemini": Path.home() / ".gemini/settings.json",
        "kiro": Path.home() / ".kiro/hooks/engineering-governance.json",
    }[provider]


def provider_executable(provider: str) -> Path:
    override = os.environ.get("AGENT_PROVIDER_EXECUTABLE")
    if override:
        return Path(override)
    from shutil import which
    value = which(PROVIDER_BINARIES[provider])
    if not value:
        raise OSError("provider executable unavailable")
    return Path(value)


def probe_version(executable: Path) -> str:
    completed = subprocess.run([str(executable), "--version"], text=True, capture_output=True, timeout=1, check=False)
    value = (completed.stdout or completed.stderr).splitlines()
    if completed.returncode != 0 or not value or not value[0].strip():
        raise OSError("provider version unavailable")
    return value[0].strip()[:200]


def validate_porter(provider: str, surface: str, version: str) -> None:
    pattern = PORTER_RULES.get(provider, {}).get(surface)
    if pattern is None or pattern.fullmatch(version) is None:
        raise ValueError("unsupported provider version or surface")


def _denied(root: Path, provider: str, surface: str, reason: str, raw: str, tainted: bool, now: int, family: str = "activation", fingerprint: str | None = None) -> int:
    message = feedback(root, provider, surface, RuntimeDecision("DENY", family, reason, tainted), raw, tainted, now, fingerprint)
    print(message, file=sys.stderr)
    return 2


def startup(args, root: Path, path: Path, config: Path, executable: Path | None, now: int) -> int:
    try:
        if executable is None:
            raise FileNotFoundError("provider executable unavailable")
        version = probe_version(executable)
        validate_porter(args.provider, args.surface, version)
    except FileNotFoundError:
        observation, status, reason = None, "UNAVAILABLE", "provider_unavailable"
    except (OSError, ValueError) as error:
        observation, status, reason = None, "UNSUPPORTED", "provider_unsupported"
    else:
        try:
            observation = observe(args.provider, args.surface, config, executable, version)
            status, reason = "PENDING", None
        except (OSError, ValueError, json.JSONDecodeError, tomllib.TOMLDecodeError):
            observation, status, reason = None, "FAILED", "activation_failed"
    try:
        with transition_lock(root, args.provider, args.profile):
            write_state(path, args.provider, args.surface, status, observation, now, reason, now + 5 if status == "FAILED" else None)
    except (OSError, TimeoutError):
        return _denied(root, args.provider, args.surface, "activation_lock_timeout", "startup", False, now)
    if status != "PENDING":
        feedback(root, args.provider, args.surface, RuntimeDecision("DENY", "activation", reason or "activation_failed"), "startup", False, now)
    return 0


def pretool(args, root: Path, path: Path, config: Path, executable: Path, now: int, payload: dict) -> int:
    try:
        command, file_path = normalize_payload(args.provider, payload)
    except ValueError:
        return _denied(root, args.provider, args.surface, "invalid_payload", "[invalid-payload]", True, now)
    raw = command or file_path
    tainted = privacy_tainted(command, file_path)
    try:
        state = read_state(path)
    except (OSError, ValueError, json.JSONDecodeError):
        state = None
    if not state or not state.get("provider_version") or not state.get("runtime_identity"):
        return _denied(root, args.provider, args.surface, "provider_unsupported", raw, tainted, now)
    try:
        validate_porter(args.provider, args.surface, state["provider_version"])
    except ValueError:
        try:
            with transition_lock(root, args.provider, args.profile):
                write_state(path, args.provider, args.surface, "UNSUPPORTED", None, now, "provider_unsupported")
        except (OSError, TimeoutError):
            return _denied(root, args.provider, args.surface, "activation_lock_timeout", raw, tainted, now)
        return _denied(root, args.provider, args.surface, "provider_unsupported", raw, tainted, now)
    try:
        observation = observe(args.provider, args.surface, config, executable, state["provider_version"])
    except (OSError, ValueError, json.JSONDecodeError, tomllib.TOMLDecodeError):
        observation = None
    if observation and state.get("status") == "ENFORCED" and state.get("fingerprint") == observation.fingerprint:
        decision = decide(command, file_path)
        if decision.decision == "ALLOW":
            return 0
        print(feedback(root, args.provider, args.surface, decision, raw, tainted, now, observation.fingerprint), file=sys.stderr)
        return 2
    if state.get("status") == "UNSUPPORTED" and observation and state.get("fingerprint") == observation.fingerprint:
        return _denied(root, args.provider, args.surface, "provider_unsupported", raw, tainted, now, fingerprint=observation.fingerprint)
    if state.get("status") == "FAILED" and now < int(state.get("retry_after") or 0) and (observation is None or state.get("fingerprint") == observation.fingerprint):
        return _denied(root, args.provider, args.surface, "activation_cooldown", raw, tainted, now, fingerprint=state.get("fingerprint"))
    try:
        with transition_lock(root, args.provider, args.profile):
            current = read_state(path)
            if not current or not current.get("provider_version"):
                return _denied(root, args.provider, args.surface, "provider_unsupported", raw, tainted, now)
            try:
                observation = observe(args.provider, args.surface, config, executable, current["provider_version"])
            except (OSError, ValueError, json.JSONDecodeError, tomllib.TOMLDecodeError):
                write_state(path, args.provider, args.surface, "FAILED", observation_from_state(current), now, "activation_failed", now + 5)
                return _denied(root, args.provider, args.surface, "activation_failed", raw, tainted, now, fingerprint=current.get("fingerprint"))
            if current.get("runtime_identity") != observation.runtime_identity:
                write_state(path, args.provider, args.surface, "UNSUPPORTED", observation, now, "provider_unsupported")
                return _denied(root, args.provider, args.surface, "provider_unsupported", raw, tainted, now, fingerprint=observation.fingerprint)
            if os.environ.get("AGENT_POLICY_FORCE_PREFLIGHT_FAILURE") == "1":
                write_state(path, args.provider, args.surface, "FAILED", observation, now, "activation_failed", now + 5)
                return _denied(root, args.provider, args.surface, "activation_failed", raw, tainted, now, fingerprint=observation.fingerprint)
            write_state(path, args.provider, args.surface, "ENFORCED", observation, now)
    except (OSError, TimeoutError):
        return _denied(root, args.provider, args.surface, "activation_lock_timeout", raw, tainted, now, fingerprint=observation.fingerprint if observation else state.get("fingerprint"))
    decision = decide(command, file_path)
    if decision.decision == "ALLOW":
        return 0
    print(feedback(root, args.provider, args.surface, decision, raw, tainted, now, observation.fingerprint), file=sys.stderr)
    return 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("startup", "pretool", "doctor"))
    parser.add_argument("--provider", required=True)
    parser.add_argument("--surface", required=True)
    parser.add_argument("--profile", default=PROFILE)
    parser.add_argument("--now", type=int)
    parser.add_argument("--managed-fragment", default="")
    args = parser.parse_args()
    if args.provider not in SUPPORTED_PROVIDERS:
        print("UNKNOWN_PROVIDER", file=sys.stderr)
        return 2
    now = args.now if args.now is not None else int(time.time())
    try:
        root = state_root()
        record = state_path(root, args.provider, args.profile)
        config = Path(os.environ.get("AGENT_POLICY_CONFIG", default_config(args.provider))).expanduser()
        try:
            executable = provider_executable(args.provider)
        except OSError:
            executable = None
    except OSError:
        print("operation policy blocked [state_unavailable]", file=sys.stderr)
        return 2
    if args.mode in {"startup", "doctor"}:
        return startup(args, root, record, config, executable, now)
    if executable is None:
        return _denied(root, args.provider, args.surface, "provider_unavailable", "[provider-unavailable]", True, now)
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        return _denied(root, args.provider, args.surface, "invalid_payload", "[invalid-payload]", True, now)
    return pretool(args, root, record, config, executable, now, payload)


if __name__ == "__main__":
    raise SystemExit(main())
