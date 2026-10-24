#!/usr/bin/env python3
"""Execution gate with provider-neutral default-allow profile."""
from __future__ import annotations
import argparse, hashlib, json, os, pwd, subprocess, sys
from pathlib import Path
from operation_policy import PROFILE, SUPPORTED_PROVIDERS, classify

def _legacy_action(command: str) -> str | None:
    lowered = command.lower()
    for executable, verbs in {"git": ("push",), "kubectl": ("apply", "delete", "patch", "edit"), "terraform": ("apply", "destroy", "import"), "tofu": ("apply", "destroy", "import"), "pulumi": ("up", "destroy", "import"), "helm": ("install", "upgrade", "uninstall", "rollback")}.items():
        if executable in lowered and any(verb in lowered for verb in verbs): return f"{executable}-mutation"
    return None

def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--provider", default="legacy"); parser.add_argument("--profile", default="legacy")
    parser.add_argument("--managed-fragment", default="")
    args = parser.parse_args()
    try: payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        print("execution gate blocked: invalid hook payload", file=sys.stderr); return 2
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        print("execution gate blocked: tool_input required", file=sys.stderr); return 2
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip(): return 0
    if args.profile == PROFILE:
        if args.provider not in SUPPORTED_PROVIDERS:
            print("execution gate blocked: unsupported provider porter", file=sys.stderr); return 2
        decision = classify(command)
        if decision.decision == "ALLOW": return 0
        digest = hashlib.sha256(command.encode()).hexdigest()
        feedback = Path(__file__).with_name("policy-feedback.py")
        try:
            result = subprocess.run([sys.executable, str(feedback), "--provider", args.provider, "--family", decision.family, "--reason", decision.reason_code, "--hash", digest], input=command, text=True, capture_output=True, timeout=2, check=False)
            message = result.stderr.rstrip()
        except (OSError, subprocess.TimeoutExpired): message = ""
        print(message or f"execution gate blocked [{decision.reason_code}]: {command}\n이 작업은 직접 검토가 필요합니다. 필요하다면 사용자가 실행한 뒤 결과를 알려주세요.", file=sys.stderr)
        return 2
    action = _legacy_action(command)
    if action is None: return 0
    repo = Path(payload.get("cwd") or os.getcwd()).resolve(); environment = os.environ.get("AGENT_TARGET_ENVIRONMENT", "unknown")
    canonical = json.dumps({"action": action, "command": command, "environment": environment, "repo": str(repo)}, sort_keys=True, separators=(",", ":"))
    request_digest = hashlib.sha256(canonical.encode()).hexdigest(); receipt = os.environ.get("AGENT_APPROVAL_RECEIPT", "")
    if not receipt or environment == "unknown":
        print(f"execution gate blocked: scoped approval required action={action} digest={request_digest}", file=sys.stderr); return 2
    gate = Path(__file__).with_name("approval-gate.sh"); trusted = os.environ.copy()
    trusted["AGENT_APPROVAL_PUBLIC_KEY"] = str(Path(pwd.getpwuid(os.getuid()).pw_dir) / ".config/agents/trust/approval-public.pem")
    return subprocess.run(["bash", str(gate), "--repo", str(repo), "--receipt", receipt, "--digest", request_digest, "--action", action, "--environment", environment], env=trusted, check=False).returncode

if __name__ == "__main__": raise SystemExit(main())
