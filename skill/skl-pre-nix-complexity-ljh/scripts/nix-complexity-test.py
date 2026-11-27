"""Focused synthetic checks for the Nix complexity reporter."""

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("nix-complexity.py")
SPEC = importlib.util.spec_from_file_location("nix_complexity", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def git(root, *args):
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)


class ComplexityTest(unittest.TestCase):
    def test_counts_syntax_and_ignores_string_contents(self):
        expression = '(x: (if x then (if x && true then "if && assert" else 1) else assert x; 0))'
        result = MODULE.expression_metrics(expression)
        self.assertEqual(result["lambdas"], 1)
        self.assertEqual(result["ifs"], 2)
        self.assertEqual(result["asserts"], 1)
        self.assertEqual(result["boolean_ops"], 1)
        self.assertEqual(result["decisions"], 4)
        self.assertEqual(result["max_if_depth"], 2)

    @unittest.skipUnless(shutil.which("nix-instantiate"), "Nix parser unavailable")
    def test_compares_git_ref_with_worktree_and_fails_on_bad_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            git(root, "init", "-q")
            (root / "one.nix").write_text('x: if x then "if &&" else 0\n')
            git(root, "add", "one.nix")
            git(root, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "base")
            (root / "one.nix").write_text('x: if x && true then 1 else 0\n')
            (root / "two.nix").write_text('x: assert x; x\n')

            command = [sys.executable, str(SCRIPT), "--repo", str(root), "--base", "HEAD"]
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            report = json.loads(result.stdout)
            self.assertEqual(report["before"]["summary"]["files"], 1)
            self.assertEqual(report["after"]["summary"]["files"], 2)
            self.assertEqual(report["before"]["summary"]["decisions"], 1)
            self.assertEqual(report["after"]["summary"]["decisions"], 3)

            (root / "two.nix").write_text("x: if then\n")
            bad = subprocess.run(command, check=False, capture_output=True, text=True)
            self.assertEqual(bad.returncode, 2)
            self.assertEqual(bad.stdout, "")
            self.assertIn("Nix parse failed for two.nix", bad.stderr)


if __name__ == "__main__":
    unittest.main()
