#!/usr/bin/env python3
"""Compare routing descriptions with synthetic requests in isolated Codex sessions."""

import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


CASES = {
    "design": ("Compare two module boundaries and show the migration tradeoffs. No code changes.", ["design"]),
    "review": ("Review PR #42 at its recorded head. Report findings without posting.", ["pr-review"]),
    "rca": ("Production latency rose after a release. Gather evidence and narrow the cause.", ["rca"]),
    "verify": ("Run the acceptance checks for a finished migration and report what passed.", ["verification"]),
    "git": ("Get HEAD, the last commit and dirty state for one tracked file.", ["git-evidence"]),
    "review-thread": ("Assess and respond to the existing reviewer thread on PR #42.", ["review-threads"]),
    "architecture-arena": ("Use arena to compare independent design alternatives. Parallel evaluation is approved.",
                           ["arena"]),
    "casual": ("Explain in one paragraph what a Git branch is.", []),
    "closed-incident": ("The outage is over. Summarize the timeline and lessons with owners.", ["retrospective"]),
    "plan-only": ("Outline and compare options for restructuring capability declarations.", ["design"]),
}
BEFORE = {
    "design": "Architecture and module-boundary choices with repository evidence and alternative designs.",
    "architect": "Sketch types, declarations and module structure before code.",
    "pr-review": "Coordinate static PR review with pinned revisions, adversarial evidence and report validation.",
    "rca": "Guide evidence-driven root-cause analysis for failures and incidents.",
    "verification": "Verify an implementation, migration or local environment against criteria.",
    "git-evidence": "Collect fixed revision and tracked path Git evidence.",
    "review-threads": "Work with existing PR review threads.",
    "retrospective": "Review an incident, its timeline and follow-up actions.",
}
AFTER = BEFORE | {
    "design": "Use for recommendations and comparing architecture options without modifying code.",
    "architect": "Use for types/signatures that will be implemented after the design decision is settled.",
    "pr-review": "Use for a new static PR review and report. Existing thread requests use review-threads.",
    "rca": "Use for an active diagnosis. Closed incident summaries use retrospective.",
    "arena": "Use only when independent alternatives and parallel evaluation are explicitly requested and allowed.",
}


def run(catalog, model, cases, root):
    definitions = {
        cid: {"type": "array", "items": {"type": "string", "enum": sorted(catalog)}} for cid in cases
    }
    schema = {"type": "object", "properties": definitions, "required": list(cases), "additionalProperties": False}
    spec = root / "result-schema.json"
    spec.write_text(json.dumps(schema))
    prompts = {cid: content for cid, (content, _) in cases.items()}
    prompt = (
        "Classify these synthetic requests. Select the routes genuinely needed for each request, "
        "using an empty array for a simple direct response. Use only the supplied catalog and do not call tools.\n"
        f"Catalog: {json.dumps(catalog)}\nRequests: {json.dumps(prompts)}"
    )
    start = time.perf_counter()
    command = [
        "codex", "-a", "never", "exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check",
        "-s", "read-only", "--json", "-c", 'model_reasoning_effort="low"',
        "--output-schema", str(spec),
    ]
    if model:
        command += ["-m", model]
    command += ["-"]
    result = subprocess.run(command, cwd=root, input=prompt, capture_output=True, text=True, timeout=90)
    events = [json.loads(line) for line in result.stdout.splitlines()]
    if result.returncode != 0:
        error = next((e.get("message", "") for e in events if e.get("type") == "error"), "")
        raise SystemExit("Codex evaluation failed" + (f": {error[:280]}" if error else ""))
    usages = [event["usage"] for event in events if event.get("type") == "turn.completed"]
    if len(usages) != 1:
        raise ValueError("missing turn usage")
    usage = usages[0]
    items = [e["item"] for e in events if e.get("type") == "item.completed"]
    answer = json.loads([i["text"] for i in items if i.get("type") == "agent_message"][-1])
    correct, extra = 0, 0
    for cid, (_, expected) in cases.items():
        assigned = answer[cid]
        correct += sorted(assigned) == sorted(expected)
        extra += sum(route not in expected for route in assigned) + len(assigned) - len(set(assigned))
    tool_calls = sum(i.get("type") in {"command_execution", "mcp_tool_call", "web_search"} for i in items)
    return {"correct": correct, "extra_routes": extra, "tool_calls": tool_calls,
            "input_tokens": usage["input_tokens"], "output_tokens": usage["output_tokens"],
            "seconds": round(time.perf_counter() - start, 2), "routes": answer}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", help="Codex model ID. Defaults to the CLI default.")
    parser.add_argument("--repeats", type=int, default=2, choices=range(1, 6))
    args = parser.parse_args()
    results = {"before": [], "after": []}
    with tempfile.TemporaryDirectory(prefix="harness-routing-fixture-") as directory:
        for _ in range(args.repeats):
            for label, catalog in ("before", BEFORE), ("after", AFTER):
                item = run(catalog, args.model, CASES, Path(directory))
                results[label].append(item)
                print(label, json.dumps(item, sort_keys=True), flush=True)
    for label, items in results.items():
        fields = ("correct", "extra_routes", "tool_calls", "input_tokens", "output_tokens", "seconds")
        print(label, "median", json.dumps({k: statistics.median(row[k] for row in items) for k in fields}))
    print("cases per run", len(CASES), "model", args.model or "CLI default")


if __name__ == "__main__":
    main()
