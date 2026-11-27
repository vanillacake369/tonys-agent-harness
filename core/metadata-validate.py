#!/usr/bin/env python3
"""Trusted static YAML and v2.1 catalog validation; never execute bundle code."""
import json
import re
import sys
from pathlib import Path

import yaml


class UniqueLoader(yaml.SafeLoader):
    pass


# 중복 키를 허용하면 검증과 실제 소비자가 다른 선언을 읽을 수 있다.
def unique_mapping(loader, node):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node)
        if not isinstance(key, str) or key in result:
            raise ValueError("invalid or duplicate YAML key")
        result[key] = loader.construct_object(value_node)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def yaml_read(text):
    return yaml.load(text, Loader=UniqueLoader)


def require(condition):
    if not condition:
        raise ValueError("invalid catalog metadata")


def skill_structure(root, bundle):
    try:
        doc = (root / "SKILL.md").read_bytes().decode("utf-8")
        first, _, rest = doc.partition("\n")
        header, fence, body = rest.partition("\n---\n")
        require(first == "---" and fence)
        require(any(line != "---" and line.strip() for line in body.split("\n")))
        data = yaml_read(header)
        json.dumps(data, allow_nan=False)
        require(isinstance(data, dict) and data.get("name") == root.name)
        require(len(root.name) <= 64 and re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", root.name))
        require(nonblank_text(data.get("description"), limit=1024))
        for key, limit in (("compatibility", 500), ("license", None), ("allowed-tools", None)):
            require(key not in data or nonblank_text(data[key], limit))
        if "metadata" in data:
            meta = data["metadata"]
            require(isinstance(meta, dict) and all(isinstance(value, str) for value in meta.values()))
    except (OSError, ValueError, TypeError, yaml.YAMLError):
        sys.exit("INVALID_SKILL")
    try:
        skill_links(root, bundle)
    except (OSError, ValueError, RuntimeError):
        sys.exit("INVALID_RESOURCE")


def nonblank_text(value, limit):
    return isinstance(value, str) and bool(value.strip()) and (limit is None or len(value) <= limit)


def skill_links(root, bundle):
    root = root.resolve(strict=True)
    policy = None
    if bundle:
        bundle = Path(bundle).resolve(strict=True)
        require(len(root.relative_to(bundle).parts) >= 2)
        policy_file = bundle / "POLICY.md"
        if policy_file.is_file() and not policy_file.is_symlink():
            policy = policy_file
    pattern = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
    for markdown in root.rglob("*.md"):
        if not markdown.is_file():
            continue
        for target in pattern.findall(markdown.read_text(encoding="utf-8", errors="replace")):
            if target.startswith(("https://", "http://", "mailto:", "#")):
                continue
            require(not target.startswith("/") and not any(c in target for c in ": %\\\n\r"))
            link = (markdown.parent / target.split("#", 1)[0]).resolve(strict=True)
            require(link == root or root in link.parents or link == policy)


def import_name(path, original, imported):
    doc = path.read_bytes().decode("utf-8")
    require(doc.startswith("---\n"))
    _, divider, content = doc.partition("\n")
    metadata, fence, body = content.partition("\n---\n")
    require(divider and fence and yaml_read(metadata)["name"] == original)
    node = yaml.compose(metadata, Loader=UniqueLoader)
    key, value = next((k, v) for k, v in node.value if k.value == "name")
    require(isinstance(value, yaml.ScalarNode) and value.start_mark.index >= key.end_mark.index)
    candidate = metadata[:value.start_mark.index] + imported + metadata[value.end_mark.index:]
    before = yaml_read(metadata)
    before["name"] = imported
    require(yaml_read(candidate) == before)
    path.write_bytes(("---\n" + candidate + fence + body).encode("utf-8"))


def entry(root, path, standalone=False):
    doc = path.read_text(encoding="utf-8")
    parts = doc.split("---", 2)
    require(len(parts) == 3 and parts[0] == "")
    meta = yaml_read(parts[1])
    name = meta["name"]
    kind = meta["metadata"]["kind"]
    require(isinstance(name, str) and len(name) <= 64 and re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name))
    expected_kind = "skill" if standalone else path.relative_to(root).parts[0]
    require(kind == expected_kind)
    if standalone:
        behavior = meta["metadata"]["behavior"]
        require(isinstance(behavior, str) and behavior.strip())
    require(name == (path.stem if kind == "agent" else path.parent.name))
    require(isinstance(meta["description"], str) and 0 < len(meta["description"]) <= 1024)
    interface = meta["metadata"]
    if kind != "agent":
        interface = yaml_read((path.parent / "agents/openai.yaml").read_text())["interface"]
        require("$" + name in interface["default_prompt"])
    display = interface["display_name"]
    short = interface["short_description"]
    require(display.startswith(kind.title() + " / ") and 25 <= len(short) <= 64)
    require("# " + display in doc.splitlines())
    return name, dict(kind=kind, path=path.relative_to(root).as_posix(), description=meta["description"],
                      display_name=display, short_description=short)


def catalog_check(root):
    actual = json.loads((root / "catalog.json").read_text())
    paths = sorted(root.glob("*/*/SKILL.md")) + sorted(root.glob("agent/*.md"))
    expected = {}
    for path in paths:
        name, item = entry(root, path)
        require(name not in expected)
        expected[name] = item
    require(actual["capabilities"] == expected)
    aliases = actual["aliases"]
    require(isinstance(aliases, dict))
    for alias, target in aliases.items():
        require(alias not in expected and target in expected)
    print(f"Catalog verified: {len(expected)} capabilities")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["yaml"]:
            json.dump(yaml_read(sys.stdin.read()), sys.stdout, allow_nan=False)
        elif len(sys.argv) == 4 and sys.argv[1] == "skill-structure":
            skill_structure(Path(sys.argv[2]), sys.argv[3])
        elif len(sys.argv) == 5 and sys.argv[1] == "import-name":
            import_name(Path(sys.argv[2]), sys.argv[3], sys.argv[4])
        elif len(sys.argv) == 3 and sys.argv[1] == "skill":
            root = Path(sys.argv[2])
            entry(root, root / "SKILL.md", standalone=True)
        elif len(sys.argv) == 3 and sys.argv[1] == "catalog":
            catalog_check(Path(sys.argv[2]))
        else:
            raise ValueError("unknown metadata command")
    except (ValueError, TypeError, KeyError, AttributeError, OSError, yaml.YAMLError):
        sys.exit("INVALID_METADATA")
