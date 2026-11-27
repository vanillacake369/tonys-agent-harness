"""Compare Nix structural metrics at a Git ref and in the working tree."""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

METRICS = ("files", "loc", "nloc", "lambdas", "ifs", "asserts", "boolean_ops", "decisions")


def run(command, *, cwd=None, source=None):
    return subprocess.run(
        command,
        cwd=cwd,
        input=source,
        capture_output=True,
        check=False,
    )


def git(root, *args):
    result = run(["git", *args], cwd=root)
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args[:2])} failed (exit {result.returncode})")
    return result.stdout


def selected(path, scopes):
    return any(scope == "." or path == scope or path.startswith(scope + "/") for scope in scopes)


def file_names(root, scopes, ref=None):
    if ref is None:
        raw = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    else:
        raw = git(root, "ls-tree", "-r", "-z", "--name-only", ref)
    names = (name.decode("utf-8") for name in raw.split(b"\0") if name)
    return sorted(name for name in names if name.endswith(".nix") and selected(name, scopes))


def source_at(root, path, ref=None):
    if ref is not None:
        return git(root, "show", f"{ref}:{path}")
    file_path = root / path
    if file_path.is_symlink():
        raise RuntimeError(f"symlink source is not supported: {path}")
    return file_path.read_bytes()


def skip_string(expression, start):
    cursor = start + 1
    while cursor < len(expression):
        if expression[cursor] == "\\":
            cursor += 2
        elif expression[cursor] == '"':
            return cursor + 1
        else:
            cursor += 1
    raise RuntimeError("unterminated string in parser output")


def read_word(expression, start):
    cursor = start
    while cursor < len(expression) and (expression[cursor].isalnum() or expression[cursor] in "_-'"):
        cursor += 1
    return expression[start:cursor], cursor


def record_word(word, stack, result, active_ifs):
    if word == "if" and stack and stack[-1][1]:
        result["ifs"] += 1
        stack[-1][0] = True
        active_ifs += 1
        result["max_if_depth"] = max(result["max_if_depth"], active_ifs)
    if word == "assert":
        result["asserts"] += 1
    return active_ifs


def expression_metrics(expression):
    # Nix 자체 파서의 정규화된 표현에서 문자열을 건너뛰고 제어 토큰만 센다.
    # 이 값은 CCN이 아니라 명시적으로 정의한 구조 지표다.
    result = {"lambdas": 0, "ifs": 0, "asserts": 0, "boolean_ops": 0, "max_if_depth": 0}
    stack = []
    active_ifs = 0
    cursor = 0
    while cursor < len(expression):
        char = expression[cursor]
        if char.isspace():
            cursor += 1
            continue
        if char == '"':
            cursor = skip_string(expression, cursor)
            continue
        if char == "(":
            stack.append([False, True])
            cursor += 1
            continue
        if char == ")":
            if not stack:
                raise RuntimeError("unbalanced parser output")
            active_ifs -= int(stack.pop()[0])
            cursor += 1
            continue
        if expression.startswith(("&&", "||", "->"), cursor):
            result["boolean_ops"] += 1
            cursor += 2
        elif char == ":":
            result["lambdas"] += 1
            cursor += 1
        elif char.isalpha() or char == "_":
            word, cursor = read_word(expression, cursor)
            active_ifs = record_word(word, stack, result, active_ifs)
        else:
            cursor += 1
        if stack:
            stack[-1][1] = False
    if stack:
        raise RuntimeError("unbalanced parser output")
    result["decisions"] = result["ifs"] + result["asserts"] + result["boolean_ops"]
    return result


def measure_file(path, source):
    parsed = run(["nix-instantiate", "--parse", "-"], source=source)
    if parsed.returncode:
        raise RuntimeError(f"Nix parse failed for {path} (exit {parsed.returncode})")
    lines = source.splitlines()
    metrics = expression_metrics(parsed.stdout.decode("utf-8"))
    metrics["loc"] = len(lines)
    metrics["nloc"] = sum(bool(line.strip()) and not line.lstrip().startswith(b"#") for line in lines)
    return metrics


def summarize(files):
    total = {name: 0 for name in METRICS}
    total["files"] = len(files)
    total["max_if_depth"] = 0
    for item in files.values():
        for name in METRICS[1:]:
            total[name] += item[name]
        total["max_if_depth"] = max(total["max_if_depth"], item["max_if_depth"])
    return total


def snapshot(root, scopes, ref=None):
    names = file_names(root, scopes, ref)
    files = {}
    for name in names:
        if ref is None and not (root / name).exists():
            continue
        files[name] = measure_file(name, source_at(root, name, ref))
    return {"summary": summarize(files), "files": files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True, help="Git checkout containing Nix source")
    parser.add_argument("--base", help="Git ref to compare with the current working tree")
    parser.add_argument("--paths", nargs="+", default=["."], help="Relative files or directories; default: all")
    args = parser.parse_args()

    if shutil.which("nix-instantiate") is None:
        parser.error("nix-instantiate is required; no metrics were produced")
    root = args.repo.resolve()
    if git(root, "rev-parse", "--show-toplevel").decode().strip() != str(root):
        parser.error("--repo must be the checkout root")
    scopes = [str(Path(path)) for path in args.paths]
    if any(path.startswith("/") or ".." in Path(path).parts for path in scopes):
        parser.error("--paths must stay inside the checkout")

    revision = git(root, "rev-parse", "HEAD").decode().strip()
    report = {
        "parser": run(["nix-instantiate", "--version"]).stdout.decode().strip(),
        "revision": revision,
        "scopes": scopes,
        "metric_contract": "decisions = if + assert + (&&, ||, ->); max_if_depth is nested if depth; not CCN",
    }
    if args.base:
        base = git(root, "rev-parse", args.base).decode().strip()
        report["base_revision"] = base
        report["before"] = snapshot(root, scopes, base)
    report["after"] = snapshot(root, scopes)
    if report["after"]["summary"]["files"] == 0 and (
        not args.base or report["before"]["summary"]["files"] == 0
    ):
        raise RuntimeError("no Nix files matched --paths in either source")
    if args.base:
        report["delta"] = {
            name: report["after"]["summary"][name] - report["before"]["summary"][name]
            for name in (*METRICS, "max_if_depth")
        }
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, UnicodeError) as exc:
        print(f"nix-complexity: {exc}", file=sys.stderr)
        sys.exit(2)
