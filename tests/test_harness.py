import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "harness.py"


def run_cli(*args, cwd=None):
    return subprocess.run(
        [sys.executable, str(CLI), *args], cwd=cwd, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


class HarnessTests(unittest.TestCase):
    def test_cli_is_a_thin_entrypoint_over_explicit_architecture_boundaries(self):
        entrypoint = CLI.read_text()
        self.assertLess(len(entrypoint.splitlines()), 20)
        self.assertIn("from agent_harness.cli import main", entrypoint)

        expected_modules = {
            "agent_harness/domain/config.py",
            "agent_harness/ingress/manifest.py",
            "agent_harness/control_plane/reconcile.py",
            "agent_harness/egress/providers.py",
            "agent_harness/cli.py",
        }
        self.assertEqual(
            {str(path.relative_to(ROOT)) for path in (ROOT / "agent_harness").rglob("*.py") if path.name != "__init__.py"},
            expected_modules,
        )

    def test_python_normalization_matches_the_shared_contract_fixture(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw)
            shutil.copy(ROOT / "tests/fixtures/agent-harness.toml", project / "agent-harness.toml")
            (project / "AGENTS.md").write_text("fixture\n")
            result = run_cli("normalize", "--project", str(project))
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = json.loads((ROOT / "tests/fixtures/normalized-config.json").read_text())
            self.assertEqual(json.loads(result.stdout), expected)
    def test_normalized_config_is_the_complete_adapter_input(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            guides = Path(raw) / "team-guidelines"
            guides.mkdir()
            self.assertEqual(run_cli("init", "--project", str(project), "--preset", "infra-devops").returncode, 0)
            manifest = project / "agent-harness.toml"
            manifest.write_text(
                manifest.read_text()
                .replace('enabled = false', 'enabled = true')
                .replace('source = ""', f'source = {json.dumps(str(guides))}')
            )
            result = run_cli("normalize", "--project", str(project))
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads(result.stdout)
            self.assertEqual(config["project"]["spec_root"], ".codex")
            self.assertEqual(config["project"]["guides"]["source"], str(guides))
            self.assertEqual(config["workflow"]["public_commands"], [
                "cmd-mid-work-ljh", "cmd-mid-comment-ljh", "cmd-post-blog-ljh",
                "cmd-post-handoff-ljh", "cmd-post-ship-ljh", "cmd-post-commit-ljh",
            ])
            self.assertEqual(config["permissions"]["secret_access"], "deny")
            self.assertIn("approval", config)
            self.assertIn("verification", config)

    def test_reconcile_guides_creates_only_the_configured_symlink(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            guides = Path(raw) / "team-guidelines"
            guides.mkdir()
            (guides / "common.md").write_text("grows independently\n")
            self.assertEqual(run_cli("init", "--project", str(project)).returncode, 0)
            manifest = project / "agent-harness.toml"
            manifest.write_text(
                manifest.read_text()
                .replace('enabled = false', 'enabled = true')
                .replace('source = ""', f'source = {json.dumps(str(guides))}')
            )
            result = run_cli("reconcile-guides", "--project", str(project))
            self.assertEqual(result.returncode, 0, result.stderr)
            link = project / ".agent-context/team-guides"
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.resolve(), guides.resolve())
            self.assertEqual((link / "common.md").read_text(), "grows independently\n")
            link.unlink()
            link.parent.mkdir(exist_ok=True)
            link.write_text("user-owned\n")
            refused = run_cli("reconcile-guides", "--project", str(project))
            self.assertEqual(refused.returncode, 2)
            self.assertEqual(link.read_text(), "user-owned\n")

    def test_reconcile_guides_reads_immutable_source_and_writes_only_to_workspace(self):
        with tempfile.TemporaryDirectory() as raw:
            source = Path(raw) / "source"
            workspace = Path(raw) / "workspace"
            guides = Path(raw) / "team-guidelines"
            guides.mkdir()
            workspace.mkdir()
            self.assertEqual(run_cli("init", "--project", str(source)).returncode, 0)
            manifest = source / "agent-harness.toml"
            manifest.write_text(
                manifest.read_text()
                .replace('enabled = false', 'enabled = true')
                .replace('source = ""', f'source = {json.dumps(str(guides))}')
            )
            source.chmod(0o555)
            try:
                result = run_cli(
                    "reconcile-guides",
                    "--project", str(source),
                    "--workspace", str(workspace),
                )
            finally:
                source.chmod(0o755)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((source / ".agent-context").exists())
            self.assertEqual((workspace / ".agent-context/team-guides").resolve(), guides.resolve())

    def test_approval_trust_path_is_external_and_fingerprint_bound(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            project.mkdir()
            trust = Path(raw) / "approval-public.pem"
            private = Path(raw) / "approval-private.pem"
            subprocess.run(["openssl", "genrsa", "-out", str(private), "2048"], check=True, capture_output=True)
            subprocess.run(["openssl", "pkey", "-in", str(private), "-pubout", "-out", str(trust)], check=True, capture_output=True)
            fingerprint = hashlib.sha256(trust.read_bytes()).hexdigest()
            self.assertEqual(run_cli("init", "--project", str(project)).returncode, 0)
            manifest = project / "agent-harness.toml"
            manifest.write_text(
                manifest.read_text()
                .replace('public_key_path = ""', f'public_key_path = {json.dumps(str(trust))}')
                .replace('expected_fingerprint = ""', f'expected_fingerprint = "{fingerprint}"')
            )
            planned = run_cli("plan", "--project", str(project))
            self.assertEqual(planned.returncode, 0, planned.stderr)
            self.assertEqual(json.loads(planned.stdout)["approval_trust_status"], "PROVISIONED")
            manifest.write_text(manifest.read_text().replace(fingerprint, "0" * 64))
            mismatch = run_cli("plan", "--project", str(project))
            self.assertEqual(mismatch.returncode, 2)
            trust_inside = project / "public.pem"
            trust_inside.write_text("inside\n")
            manifest.write_text(
                manifest.read_text()
                .replace(str(trust), str(trust_inside))
                .replace("0" * 64, hashlib.sha256(trust_inside.read_bytes()).hexdigest())
            )
            inside = run_cli("plan", "--project", str(project))
            self.assertEqual(inside.returncode, 2)
            self.assertIn("outside", inside.stderr)
            manifest.write_text(
                manifest.read_text()
                .replace(str(trust_inside), str(private))
                .replace(hashlib.sha256(trust_inside.read_bytes()).hexdigest(), hashlib.sha256(private.read_bytes()).hexdigest())
            )
            private_result = run_cli("plan", "--project", str(project))
            self.assertEqual(private_result.returncode, 2)
            self.assertIn("public key", private_result.stderr)

    def test_init_creates_manifest_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw)
            first = run_cli("init", "--project", str(project), "--preset", "infra-devops")
            self.assertEqual(first.returncode, 0, first.stderr)
            manifest = project / "agent-harness.toml"
            parsed = tomllib.loads(manifest.read_text())
            self.assertEqual(parsed["schema_version"], 1)
            self.assertEqual(parsed["preset"], "infra-devops")
            self.assertTrue((project / "AGENTS.md").is_file())
            original = manifest.read_text()
            second = run_cli("init", "--project", str(project), "--preset", "minimal")
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(manifest.read_text(), original)

    def test_policy_weakening_fails_closed(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw)
            project.mkdir(exist_ok=True)
            (project / "agent-harness.toml").write_text(
                'schema_version=1\npreset="minimal"\n[permissions]\nsecret_access="allow"\n'
            )
            result = run_cli("plan", "--project", str(project))
            self.assertEqual(result.returncode, 2)
            self.assertIn("secret_access", result.stderr)

    def test_init_preserves_existing_instruction_and_rejects_instruction_escape(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            project.mkdir()
            instruction = project / "AGENTS.md"
            instruction.write_text("project-owned\n")
            created = run_cli("init", "--project", str(project))
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertEqual(instruction.read_text(), "project-owned\n")
            manifest = project / "agent-harness.toml"
            manifest.write_text(manifest.read_text().replace('instruction = "AGENTS.md"', 'instruction = "../outside.md"'))
            escaped = run_cli("plan", "--project", str(project))
            self.assertEqual(escaped.returncode, 2)
            self.assertIn("inside the project", escaped.stderr)

    def test_plan_is_pure_and_export_is_deterministic(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            self.assertEqual(run_cli("init", "--project", str(project)).returncode, 0)
            plan = run_cli("plan", "--project", str(project), "--output", str(output))
            self.assertEqual(plan.returncode, 0, plan.stderr)
            self.assertFalse(output.exists())
            payload = json.loads(plan.stdout)
            self.assertEqual(payload["status"], "READY")
            first = run_cli("export", "--project", str(project), "--output", str(output))
            self.assertEqual(first.returncode, 0, first.stderr)
            snapshot = {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
            second = run_cli("export", "--project", str(project), "--output", str(output))
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(snapshot, {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()})

    def test_plan_reports_desired_and_observed_reconciliation_status(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            self.assertEqual(run_cli("init", "--project", str(project)).returncode, 0)
            before = json.loads(run_cli("plan", "--project", str(project), "--output", str(output)).stdout)
            self.assertEqual(before["reconciliation_status"], "NOT_APPLIED")
            self.assertIsNone(before["observed_digest"])
            self.assertTrue(all(value == "STATICALLY_VERIFIED" for value in before["provider_status"].values()))
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            after = json.loads(run_cli("plan", "--project", str(project), "--output", str(output)).stdout)
            self.assertEqual(after["reconciliation_status"], "IN_SYNC")
            self.assertEqual(after["desired_digest"], after["observed_digest"])

    def test_verify_detects_tampered_output(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            run_cli("init", "--project", str(project))
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            self.assertEqual(run_cli("verify", "--project", str(project), "--output", str(output)).returncode, 0)
            target = next(p for p in output.rglob("*") if p.is_file() and p.name != "manifest.json")
            target.write_text(target.read_text() + "\ntampered\n")
            self.assertEqual(run_cli("verify", "--project", str(project), "--output", str(output)).returncode, 2)

    def test_default_output_is_scoped_below_selected_project(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            elsewhere = Path(raw) / "elsewhere"
            elsewhere.mkdir()
            self.assertEqual(run_cli("init", "--project", str(project)).returncode, 0)
            result = run_cli("export", "--project", str(project), cwd=elsewhere)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((project / "build/agent-harness/manifest.json").is_file())
            self.assertFalse((elsewhere / "build/agent-harness").exists())

    def test_verify_rejects_unexpected_generated_file(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            run_cli("init", "--project", str(project))
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            (output / "codex/unmanaged.toml").write_text("unsafe = true\n")
            result = run_cli("verify", "--project", str(project), "--output", str(output))
            self.assertEqual(result.returncode, 2)
            self.assertIn("unexpected", result.stderr)

    def test_export_projects_skills_and_commands_to_every_selected_provider(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            self.assertEqual(run_cli("init", "--project", str(project), "--preset", "regulated").returncode, 0)
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            expected = {
                "codex": ("skills/skl-pre-prd-ljh/SKILL.md", "skills/workflow-cmd-mid-work-ljh/SKILL.md"),
                "claude": ("skills/skl-pre-prd-ljh/SKILL.md", "commands/cmd-mid-work-ljh.md"),
                "gemini": ("skills/skl-pre-prd-ljh/SKILL.md", "commands/cmd-mid-work-ljh.md"),
                "kiro": ("skills/skl-pre-prd-ljh/SKILL.md", "workflows/cmd-mid-work-ljh.md"),
            }
            for provider, relative_paths in expected.items():
                self.assertEqual(
                    (output / provider / "AGENTS.md").read_bytes(),
                    (project / "AGENTS.md").read_bytes(),
                )
                for relative in relative_paths:
                    self.assertTrue((output / provider / relative).is_file(), f"missing {provider}/{relative}")

    def test_instruction_change_invalidates_export_and_provider_gate_detects_drift(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            self.assertEqual(run_cli("init", "--project", str(project), "--preset", "regulated").returncode, 0)
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            gate = output / "runtime/governance/provider-instructions-gate.sh"
            passed = subprocess.run(["bash", str(gate), str(output)], text=True, capture_output=True)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            (output / "kiro/AGENTS.md").write_text("drift\n")
            drift = subprocess.run(["bash", str(gate), str(output)], text=True, capture_output=True)
            self.assertEqual(drift.returncode, 2)
            (project / "AGENTS.md").write_text("changed project contract\n")
            stale = run_cli("verify", "--project", str(project), "--output", str(output))
            self.assertEqual(stale.returncode, 2)
            self.assertIn("stale", stale.stderr)

    def test_export_refuses_unmanaged_output(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "existing"
            output.mkdir()
            (output / "user-file").write_text("preserve")
            run_cli("init", "--project", str(project))
            result = run_cli("export", "--project", str(project), "--output", str(output))
            self.assertEqual(result.returncode, 2)
            self.assertEqual((output / "user-file").read_text(), "preserve")

    def test_export_refuses_output_with_unrelated_manifest(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "existing"
            output.mkdir()
            (output / "manifest.json").write_text('{"schema_version": 1}\n')
            (output / "user-file").write_text("preserve")
            run_cli("init", "--project", str(project))
            result = run_cli("export", "--project", str(project), "--output", str(output))
            self.assertEqual(result.returncode, 2)
            self.assertEqual((output / "user-file").read_text(), "preserve")

    def test_reexport_refuses_unmanaged_file_inside_owned_output(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            run_cli("init", "--project", str(project))
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            (output / "user-file").write_text("preserve")
            result = run_cli("export", "--project", str(project), "--output", str(output))
            self.assertEqual(result.returncode, 2)
            self.assertEqual((output / "user-file").read_text(), "preserve")

    def test_export_preserves_unrelated_predictable_backup_directory(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            unrelated = Path(raw) / ".generated.previous"
            unrelated.mkdir()
            (unrelated / "user-file").write_text("preserve")
            run_cli("init", "--project", str(project))
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            self.assertEqual((unrelated / "user-file").read_text(), "preserve")

    def test_unknown_schema_version_fails_closed(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw)
            project.mkdir(exist_ok=True)
            (project / "agent-harness.toml").write_text('schema_version=2\npreset="minimal"\n')
            result = run_cli("plan", "--project", str(project))
            self.assertEqual(result.returncode, 2)
            self.assertIn("schema_version", result.stderr)

    def test_export_contains_mandatory_enforcement_and_complete_skill_resources(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            run_cli("init", "--project", str(project), "--preset", "regulated")
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            self.assertTrue((output / "runtime/governance/path-guard.sh").is_file())
            codex = (output / "codex/config.toml").read_text()
            self.assertIn('"**/.env*" = "deny"', codex)
            claude = json.loads((output / "claude/settings.json").read_text())
            self.assertIn("PreToolUse", claude["hooks"])
            self.assertIn("SessionStart", claude["hooks"])
            mcp_hooks = [entry for entry in claude["hooks"]["PreToolUse"] if entry.get("matcher") == "mcp__.*"]
            self.assertEqual(len(mcp_hooks), 1)
            self.assertIn("mcp-hook.sh", mcp_hooks[0]["hooks"][0]["command"])
            reviewer = (output / "claude/agents/independent-reviewer.md").read_text()
            self.assertIn("tools: Read, Grep, Glob", reviewer)
            self.assertIn("disallowedTools: Write, Edit, NotebookEdit, Bash", reviewer)
            codex_text = (output / "codex/config.toml").read_text()
            self.assertIn("[[hooks.SessionStart]]", codex_text)
            gemini = json.loads((output / "gemini/settings.json").read_text())
            self.assertIn("BeforeAgent", gemini["hooks"])
            self.assertIn("AfterTool", gemini["hooks"])
            self.assertIn("retry-hook.sh post", gemini["hooks"]["AfterTool"][0]["hooks"][0]["command"])
            self.assertIn("read_file", gemini["hooks"]["BeforeTool"][0]["matcher"])
            kiro_hooks = json.loads((output / "kiro/hooks/engineering-governance.json").read_text())
            self.assertTrue(any(hook["trigger"] == "AgentSpawn" for hook in kiro_hooks["hooks"]))
            self.assertTrue(any(hook["trigger"] == "PostToolUse" and "retry-hook.sh post" in hook["command"] for hook in kiro_hooks["hooks"]))
            self.assertTrue((output / "codex/skills/a2a-workflow/references/routing.md").is_file())
            self.assertTrue((output / "kiro/skills/a2a-workflow/scripts/verify.sh").is_file())
            path_guard = output / "runtime/governance/path-guard.sh"
            self.assertTrue(os.access(path_guard, os.X_OK))
            probe = subprocess.run(
                [str(path_guard)], input='{"tool_name":"Bash","tool_input":{"command":"echo ok"}}',
                text=True, capture_output=True,
            )
            self.assertEqual(probe.returncode, 0, probe.stderr)
            notebook = subprocess.run(
                [str(path_guard)], input='{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"notes.ipynb"}}',
                text=True, capture_output=True,
            )
            self.assertEqual(notebook.returncode, 0, notebook.stderr)
            self.assertFalse(any("__pycache__" in path.parts or path.suffix == ".pyc" for path in output.rglob("*")))

    def test_verified_approval_transition_unblocks_only_approval_request(self):
        transition = ROOT / "runtime/orchestrator/approval-transition.sh"
        approval = {"status": "approved", "scope_digest": "scope", "verification": "external-receipt"}
        requested = {"decision": {"selected_action": "HUMAN_APPROVAL"}, "human_approval": approval}
        result = subprocess.run(["bash", str(transition)], input=json.dumps(requested), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["decision"]["selected_action"], "AUTO_EXECUTE")
        blocked = {"decision": {"selected_action": "BLOCKED"}, "human_approval": approval}
        result = subprocess.run(["bash", str(transition)], input=json.dumps(blocked), text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)

    def test_execution_gate_requires_scoped_approval_for_push(self):
        gate = ROOT / "runtime/governance/execution-gate.py"
        payload = {"tool_name": "Bash", "tool_input": {"command": "git push origin main"}}
        result = subprocess.run([sys.executable, str(gate)], input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("approval", result.stderr.lower())
        safe = {"tool_name": "Bash", "tool_input": {"command": "git status --short"}}
        result = subprocess.run([sys.executable, str(gate)], input=json.dumps(safe), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in (
            "git -C /tmp/repo push origin main",
            "kubectl --context production apply -f deployment.yaml",
            "terraform -chdir=infra apply",
            'bash -c "git push origin main"',
            "git status & terraform apply",
            "git status\nterraform apply",
            "git commit -m change",
        ):
            with self.subTest(command=command):
                payload = {"tool_name": "Bash", "tool_input": {"command": command}}
                result = subprocess.run([sys.executable, str(gate)], input=json.dumps(payload), text=True, capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn("approval", result.stderr.lower())

    def test_stricter_retry_limit_is_exported_to_provider_hooks(self):
        with tempfile.TemporaryDirectory() as raw:
            project = Path(raw) / "project"
            output = Path(raw) / "generated"
            run_cli("init", "--project", str(project), "--preset", "regulated")
            manifest = project / "agent-harness.toml"
            manifest.write_text(manifest.read_text().replace("retry_max = 3", "retry_max = 1"))
            self.assertEqual(run_cli("export", "--project", str(project), "--output", str(output)).returncode, 0)
            self.assertIn("retry-hook.sh failure 1", (output / "claude/settings.json").read_text())
            self.assertIn("retry-hook.sh post 1", (output / "gemini/settings.json").read_text())
            self.assertIn("retry-hook.sh post 1", (output / "kiro/hooks/engineering-governance.json").read_text())

    def test_verification_inventory_covers_baseline_to_head(self):
        with tempfile.TemporaryDirectory() as raw:
            repo = Path(raw) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Harness Test"], cwd=repo, check=True)
            (repo / "base.txt").write_text("base\n")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "base"], cwd=repo, check=True)
            baseline = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            (repo / "tests").mkdir()
            (repo / "tests/test_removed.py").write_text("def test_x(): assert True\n")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "test"], cwd=repo, check=True)
            (repo / "impl.py").write_text("VALUE = 1\n")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "impl"], cwd=repo, check=True)
            evidence = Path(raw) / "evidence.json"
            recorder = ROOT / "runtime/governance/record-verification.py"
            result = subprocess.run([
                sys.executable, str(recorder), "--repo", str(repo), "--output", str(evidence),
                "--baseline", baseline, "--requirement", "FR-TEST", "--", sys.executable, "-c", "print('ok')",
            ], text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            payload = json.loads(evidence.read_text())
            self.assertEqual(payload["status"], "REVIEW_REQUIRED")
            self.assertIn("tests/test_removed.py", payload["test_changes_requiring_review"])

    def test_exact_public_asset_inventory(self):
        skills = {p.parent.name for p in (ROOT / "assets/skills").glob("*/SKILL.md") if p.parent.name.startswith("skl-")}
        commands = {p.stem for p in (ROOT / "assets/commands").glob("cmd-*.md")}
        self.assertEqual(skills, {
            "skl-pre-prd-ljh", "skl-pre-research-ljh", "skl-pre-adr-ljh",
            "skl-mid-impl-ljh", "skl-mid-review-ljh", "skl-mid-perf-ljh",
            "skl-post-blog-ljh", "skl-post-docs-ljh", "skl-post-ship-ljh",
        })
        self.assertEqual(commands, {
            "cmd-mid-work-ljh", "cmd-mid-comment-ljh", "cmd-post-blog-ljh",
            "cmd-post-handoff-ljh", "cmd-post-ship-ljh", "cmd-post-commit-ljh",
        })

    def test_all_presets_plan(self):
        for preset in ("minimal", "application", "infra-devops", "regulated"):
            with self.subTest(preset=preset), tempfile.TemporaryDirectory() as raw:
                project = Path(raw)
                self.assertEqual(run_cli("init", "--project", str(project), "--preset", preset).returncode, 0)
                result = run_cli("plan", "--project", str(project))
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
