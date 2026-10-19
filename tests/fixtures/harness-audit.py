"""Read-only repository audit; fixtures live only in a temporary directory.

Run: python3 tests/fixtures/harness-audit.py
Exit 1 means a spec expectation failed. Commands in payloads are never executed.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
GOV = ROOT / "runtime/governance"
rows = []


def check(name, command, expected, payload=None):
    start = time.monotonic()
    result = subprocess.run(command, input=payload, text=True, capture_output=True, cwd=ROOT)
    passed = expected(result)
    rows.append(passed)
    print(json.dumps({"check": name, "pass": passed, "exit_code": result.returncode,
                      "duration_ms": round((time.monotonic()-start)*1000),
                      "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}))


def blocked(result):
    return result.returncode == 2


with tempfile.TemporaryDirectory(prefix="harness-audit-") as directory:
    tmp = Path(directory)
    check("malformed hook payload must block", ["bash", str(GOV / "path-guard.sh")], blocked, "{")
    check("quoted sensitive path must block", ["bash", str(GOV / "path-guard.sh")], blocked,
          json.dumps({"tool_name": "Bash", "tool_input": {"command": 'cat ".env"'}}))
    check("project MCP policy must permit declared research", ["bash", str(GOV / "mcp-allowlist-gate.sh"),
          "tests/fixtures/project-policy.json", "context7", "researcher", "skl-pre-research-ljh"], lambda r: r.returncode == 0)
    evidence = tmp / "evidence.json"
    evidence.write_text(json.dumps({"status":"DONE", "requirements":[{"id":"FR-001","result":"pass"}],
        "commands":[{"command":"not-executed","exit_code":0,"duration_ms":1}],
        "changed_files":["a"],"diff_summary":"unverified","unresolved_errors":[],"commit":"abc"}))
    check("missing actual test result must block", ["bash", str(GOV / "evidence-gate.sh"), str(evidence)], blocked)
    retry = ["bash", str(GOV / "retry-budget.sh"), "record", str(tmp / "retry.json"), "task"]
    for attempt in range(3):
        check(f"retry failure {attempt+1}", retry + ["fail", "same-cause"],
              lambda r, attempt=attempt: r.returncode == (2 if attempt == 2 else 0))
    check("blocked retry must not become DONE on success record", retry + ["success", "same-cause"], blocked)
    check("daily decoded content over 40 lines must block", ["bash", str(GOV / "memory-lifecycle.sh"),
          "write", str(tmp / "memory"), "project", "daily", "entry", json.dumps({"text":"\n".join(["line"]*41)})], blocked)
    check("parent namespace must block", ["bash", str(GOV / "memory-lifecycle.sh"), "write",
          str(tmp / "isolated" / "memory"), "..", "session", "entry", '{"fact":"synthetic"}'], blocked)
    trace = tmp / "trace.tsv"
    trace.write_text("requirement_id\tstatus\tdesign\tcode\ttest\tverification\nFR-X\tverified\tmissing-design\tmissing-code\tmissing-test\tmissing-proof\n")
    check("verified traceability must reject nonexistent artifacts", ["bash", "runtime/orchestrator/traceability-gate.sh", str(trace)], blocked)
    check("missing policy signals must block", ["bash", "runtime/orchestrator/decision.sh"],
          lambda r: r.returncode == 0 and json.loads(r.stdout)["selected_action"] == "BLOCKED",
          json.dumps({"decision_id":"audit", "request":"synthetic task", "risk_level":"low", "uncertainty_level":"low",
                      "llm_judgment":{"recommended_action":"AUTO_EXECUTE"}}))

print(json.dumps({"total":len(rows),"passed":sum(rows),"failed":len(rows)-sum(rows)}))
raise SystemExit(0 if all(rows) else 1)
