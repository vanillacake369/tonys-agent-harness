#!/usr/bin/env bash
# Validate a declarative, human-guided DAG. Never executes its nodes.
set -euo pipefail

manifest=${1:?usage: validate-dag-contract.sh DAG_YAML SCHEMA_JSON}
schema=${2:?usage: validate-dag-contract.sh DAG_YAML SCHEMA_JSON REPO_ROOT}
root=${3:?usage: validate-dag-contract.sh DAG_YAML SCHEMA_JSON REPO_ROOT}
fail() {
    printf 'INVALID_DAG:%s\n' "$1" >&2
    exit 2
}
test -f "$manifest" && test ! -L "$manifest" || fail MANIFEST_PATH
test -f "$schema" && test ! -L "$schema" || fail SCHEMA_PATH

json=$(mktemp)
trap 'rm -f "$json"' EXIT
python3 "$(dirname "$0")/metadata-validate.py" yaml < "$manifest" > "$json" || fail YAML_PARSE

python3 - "$json" "$schema" "$root" <<'PY'
import json
import re
import sys
from pathlib import Path


def fail(reason):
    raise ValueError(reason)


def check(value, rule, location="dag"):
    # The checked-in schema intentionally uses this small JSON Schema subset.
    supported = {"$schema", "title", "type", "const", "enum", "pattern",
                 "minLength", "minItems", "uniqueItems", "required",
                 "additionalProperties", "properties", "items"}
    if set(rule) - supported:
        fail(f"UNSUPPORTED_SCHEMA_AT_{location}")
    kinds = rule.get("type", [])
    if isinstance(kinds, str):
        kinds = [kinds]
    matches = {
        "object": lambda x: isinstance(x, dict),
        "array": lambda x: isinstance(x, list),
        "string": lambda x: isinstance(x, str),
        "integer": lambda x: isinstance(x, int) and not isinstance(x, bool),
        "null": lambda x: x is None,
    }
    if kinds and (any(kind not in matches for kind in kinds) or
                  not any(matches[kind](value) for kind in kinds)):
        fail(f"TYPE_AT_{location}")
    if "const" in rule and (type(value) is not type(rule["const"]) or value != rule["const"]):
        fail(f"CONST_AT_{location}")
    if "enum" in rule and value not in rule["enum"]:
        fail(f"ENUM_AT_{location}")
    if isinstance(value, str):
        if len(value) < rule.get("minLength", 0):
            fail(f"EMPTY_AT_{location}")
        if "pattern" in rule and re.search(rule["pattern"], value) is None:
            fail(f"PATTERN_AT_{location}")
    if isinstance(value, list):
        if len(value) < rule.get("minItems", 0):
            fail(f"EMPTY_AT_{location}")
        if rule.get("uniqueItems") and len(value) != len(set(map(json.dumps, value))):
            fail(f"DUPLICATE_AT_{location}")
        if "items" in rule:
            for index, item in enumerate(value):
                check(item, rule["items"], f"{location}_{index}")
    if isinstance(value, dict):
        for key in rule.get("required", []):
            if key not in value:
                fail(f"MISSING_{key}_AT_{location}")
        properties = rule.get("properties", {})
        if rule.get("additionalProperties") is False and set(value) - set(properties):
            fail(f"EXTRA_FIELD_AT_{location}")
        for key, field in value.items():
            if key in properties:
                check(field, properties[key], f"{location}_{key}")


def validate(dag, schema, repository_root):
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        fail("SCHEMA_VERSION")
    check(dag, schema)
    if dag["source"] != f"capability/dag/dag-{dag['id']}/SKILL.md":
        fail("SOURCE_MAPPING")
    root = repository_root.resolve()
    source = root / dag["source"]
    if not source.is_file() or source.is_symlink():
        fail("SOURCE_UNAVAILABLE")
    statuses = set(schema["properties"]["terminals"]["items"]["enum"])
    if set(dag["terminals"]) != statuses:
        fail("TERMINAL_SET")
    nodes = {node["id"]: node for node in dag["nodes"]}
    if len(nodes) != len(dag["nodes"]):
        fail("DUPLICATE_NODE")
    if dag["entry"] not in nodes:
        fail("MISSING_ENTRY")
    if nodes[dag["entry"]]["depends_on"]:
        fail("ENTRY_HAS_DEPENDENCY")
    if any(not node["depends_on"] for node in dag["nodes"] if node["id"] != dag["entry"]):
        fail("ORPHAN_ROOT")

    for node in dag["nodes"]:
        node_id = node["id"]
        for dependency in node["depends_on"]:
            if dependency not in nodes:
                fail(f"UNKNOWN_DEPENDENCY_{node_id}")
            if nodes[dependency]["on_success"] != node_id:
                fail(f"UNLINKED_DEPENDENCY_{node_id}")
        if node["on_success"] not in nodes and node["on_success"] not in statuses:
            fail(f"UNKNOWN_SUCCESS_{node_id}")
        if node["on_failure"] not in statuses or node["on_failure"] in {"VERIFIED", "NEEDS_APPROVAL"}:
            fail(f"UNKNOWN_FAILURE_{node_id}")
        if node["on_timeout"] not in statuses or node["on_timeout"] in {"VERIFIED", "NEEDS_APPROVAL"}:
            fail(f"UNKNOWN_TIMEOUT_{node_id}")
        if node["approval"] == "none" and node["on_missing_approval"] is not None:
            fail(f"UNNEEDED_APPROVAL_BRANCH_{node_id}")
        if node["approval"] != "none" and node["on_missing_approval"] != "NEEDS_APPROVAL":
            fail(f"MISSING_APPROVAL_BRANCH_{node_id}")
        if node["side_effect"] == "mutation":
            if node["approval"] != "required":
                fail(f"UNGATED_MUTATION_{node_id}")
            if not isinstance(node["compensation"], str) or not node["compensation"].strip():
                fail(f"MISSING_COMPENSATION_{node_id}")
        elif node["compensation"] is not None:
            fail(f"UNEXPECTED_COMPENSATION_{node_id}")

    visiting = set()
    visited = set()

    def visit(node_id):
        if node_id in visiting:
            fail("CYCLE")
        if node_id in visited:
            return
        visiting.add(node_id)
        for dependency in nodes[node_id]["depends_on"]:
            visit(dependency)
        visiting.remove(node_id)
        visited.add(node_id)

    for node_id in nodes:
        visit(node_id)
    reached = set()
    current = dag["entry"]
    while current in nodes and current not in reached:
        reached.add(current)
        current = nodes[current]["on_success"]
    if reached != set(nodes):
        fail("UNREACHABLE_NODE")
    if current != "VERIFIED":
        fail("UNVERIFIED_SUCCESS_PATH")


try:
    data_file = Path(sys.argv[1])
    schema_file = Path(sys.argv[2])
    with data_file.open(encoding="utf-8") as handle:
        dag = json.load(handle)
    with schema_file.open(encoding="utf-8") as handle:
        schema = json.load(handle)
    validate(dag, schema, Path(sys.argv[3]))
except (OSError, ValueError, KeyError, TypeError, re.error) as error:
    print(f"INVALID_DAG:{error}", file=sys.stderr)
    sys.exit(2)
print(f"DAG_CONTRACT=PASS ({dag['id']})")
PY
