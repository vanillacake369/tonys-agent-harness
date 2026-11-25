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


def entry(root, path):
    doc = path.read_text(encoding="utf-8")
    parts = doc.split("---", 2)
    require(len(parts) == 3 and parts[0] == "")
    meta = yaml_read(parts[1])
    name = meta["name"]
    kind = meta["metadata"]["kind"]
    require(isinstance(name, str) and len(name) <= 64 and re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name))
    require(kind == path.relative_to(root).parts[0])
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
        elif len(sys.argv) == 3 and sys.argv[1] == "catalog":
            catalog_check(Path(sys.argv[2]))
        else:
            raise ValueError("unknown metadata command")
    except (ValueError, TypeError, KeyError, AttributeError, OSError, yaml.YAMLError):
        sys.exit("INVALID_METADATA")
