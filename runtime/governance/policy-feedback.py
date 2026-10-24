#!/usr/bin/env python3
"""Privacy-safe denial telemetry and best-effort notification."""
from __future__ import annotations
import argparse, json, os, subprocess, sys, time
from pathlib import Path

def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("provider", "family", "reason", "hash"):
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args(); command = sys.stdin.read()
    state_root = Path(os.environ.get("AGENT_POLICY_STATE_DIR", Path.home() / ".local/state/agent-harness"))
    state_root.mkdir(parents=True, exist_ok=True); os.chmod(state_root, 0o700)
    now = int(time.time()); session = os.environ.get("AGENT_SESSION_ID", "unknown")
    event = {"timestamp": now, "provider": args.provider, "family": args.family, "reason_id": args.reason, "command_hash": args.hash}
    telemetry = state_root / "operation-denials.jsonl"
    with telemetry.open("a", encoding="utf-8") as handle: handle.write(json.dumps(event, sort_keys=True) + "\n")
    os.chmod(telemetry, 0o600)
    dedupe = state_root / "notification-dedupe.json"; key = f"{session}:{args.hash}:{args.reason}"
    try: entries = json.loads(dedupe.read_text())
    except (OSError, json.JSONDecodeError): entries = {}
    should_notify = now - int(entries.get(key, 0)) >= 60
    entries = {item: stamp for item, stamp in entries.items() if now - int(stamp) < 60}
    if should_notify:
        entries[key] = now
        notifier = Path(os.environ.get("AGENT_NOTIFY_HOOK", Path.home() / ".config/agents/hooks/agent-notify.sh"))
        if notifier.is_file() and os.access(notifier, os.X_OK):
            try:
                subprocess.run([str(notifier), f"blocked:{args.family}:{args.reason}"], timeout=1, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            except (OSError, subprocess.TimeoutExpired): pass
    dedupe.write_text(json.dumps(entries, sort_keys=True)); os.chmod(dedupe, 0o600)
    print(f"execution gate blocked [{args.reason}]: {command}\n이 작업은 직접 검토가 필요합니다. 필요하다면 사용자가 실행한 뒤 결과를 알려주세요.", file=sys.stderr)
    return 0

if __name__ == "__main__": raise SystemExit(main())
