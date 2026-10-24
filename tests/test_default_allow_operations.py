import importlib.util, json, os, subprocess, sys, tempfile, tomllib, unittest
from pathlib import Path
from agent_harness.domain.config import normalized
from agent_harness.egress.providers import target_files
from agent_harness.ingress.manifest import validate_policy

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "runtime/governance/operation_policy.py"
GATE = ROOT / "runtime/governance/execution-gate.py"
SYNC = ROOT / "runtime/governance/managed-config-sync.py"
PREFLIGHT = ROOT / "runtime/governance/policy-preflight.py"
PATH_GUARD = ROOT / "runtime/governance/path-guard.sh"

def load_policy():
    spec = importlib.util.spec_from_file_location("operation_policy", POLICY_PATH)
    module = importlib.util.module_from_spec(spec); sys.modules[spec.name] = module
    spec.loader.exec_module(module); return module

class DefaultAllowOperationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.policy = load_policy()

    def assert_decision(self, expected, *commands):
        for command in commands:
            with self.subTest(command=command): self.assertEqual(self.policy.classify(command).decision, expected)

    def test_git_matrix(self):
        self.assert_decision("ALLOW", "git push", "git push origin topic", "git clean -fd", "git reset --hard")
        self.assert_decision("DENY", "git push --force origin main", "git push --force-with-lease=main origin main", "git -C /tmp/repo push --force origin main", "git push --mirror origin", "git push origin +main", "git push origin :main")
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git reset --hard"}})
        self.assertEqual(subprocess.run(["bash", str(PATH_GUARD)], input=payload, text=True).returncode, 0)

    def test_database_matrix(self):
        self.assert_decision("ALLOW", "psql -F ',' -c 'SELECT 1'", "psql db -c 'SELECT * FROM users'", "mysql -e 'START TRANSACTION'", "mongosh --eval 'db.users.find({})'", "redis-cli GET key", "python app.py")
        self.assert_decision("DENY", "psql db -c 'UPDATE users SET x=1'", "mariadb -e 'DROP TABLE x'", "sqlite3 db .read migration.sql", "sqlcmd -iupdate.sql", "cat migration.sql | psql db", "mongosh --eval 'db.users.updateOne({}, {})'", "redis-cli SET key value", "redis-cli CONFIG SET maxmemory 1gb")

    def test_container_matrix(self):
        self.assert_decision("ALLOW", "docker build .", "podman pull image", "docker run image", "docker start api", "docker compose up", "docker compose up --build")
        self.assert_decision("DENY", "docker rm api", "docker --context prod rm api", "docker -H unix:///tmp/docker.sock rm api", "podman exec api sh", "docker cp file api:/tmp/file", "docker volume rm data", "docker container stop api", "docker container exec api sh", "docker image push image", "docker compose up --scale=3", "docker compose -f compose.yml down")

    def test_kubernetes_matrix(self):
        self.assert_decision("ALLOW", "kubectl get pods", "kubectl create deployment api --image=x", "kubectl run api --image=x", "kubectl port-forward pod/api 8080", "kustomize edit set image api=x", "kubeadm upgrade plan")
        self.assert_decision("DENY", "kubectl apply -f x.yaml", "kubectl --context prod delete pod api", "kubectl create secret generic x", "kubectl exec api -- sh", "kustomize build . | kubectl apply -f -", "kubeadm init", "kubeadm --config cluster.yml reset", "kubeadm --config cluster.yml phase preflight", "kubeadm token create")

    def test_infrastructure_exception_matrix(self):
        self.assert_decision("ALLOW", "terraform apply", "tofu apply", "pulumi up", "helm upgrade --install api chart", "nixos-rebuild switch", "darwin-rebuild switch", "home-manager switch")
        self.assert_decision("DENY", "terraform destroy", "terraform -chdir=infra destroy", "tofu state rm x", "pulumi destroy", "pulumi --cwd infra destroy", "pulumi --logflow destroy", "helm uninstall api", "helm --namespace prod uninstall api", "helm upgrade api chart", "rm -fr /", "rm --recursive --force /")

    def test_unknown_wrapped_and_parse_failures_default_allow(self):
        self.assert_decision("ALLOW", "g=git; $g push --force origin main", "curl -X DELETE https://example.invalid", "python -c 'client.delete()'", "echo 'unterminated")

    def run_gate(self, command, provider="codex", env=None):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}}
        return subprocess.run([sys.executable, str(GATE), "--provider", provider, "--profile", "default-allow-operations-v1"], input=json.dumps(payload), text=True, capture_output=True, env=env)

    def test_all_supported_provider_porters_share_decisions(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ | {"AGENT_POLICY_STATE_DIR": tmp, "AGENT_NOTIFY_HOOK": str(Path(tmp) / "absent")}
            for provider in self.policy.SUPPORTED_PROVIDERS:
                self.assertEqual(self.run_gate("kubectl get pods", provider, env).returncode, 0)
                denied = self.run_gate("kubectl delete pod api", provider, env)
                self.assertEqual(denied.returncode, 2); self.assertIn("kubernetes_resource_mutation", denied.stderr)

    def test_feedback_is_private_and_deduplicated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); count = root / "count"
            notifier = root / "notify.sh"; notifier.write_text(f"#!/bin/sh\necho x >> '{count}'\n"); notifier.chmod(0o700)
            env = os.environ | {"AGENT_POLICY_STATE_DIR": tmp, "AGENT_NOTIFY_HOOK": str(notifier), "AGENT_SESSION_ID": "s1"}
            command = "psql db -c 'DELETE FROM secret_table'"
            for _ in range(2): self.assertEqual(self.run_gate(command, env=env).returncode, 2)
            events = (root / "operation-denials.jsonl").read_text()
            self.assertNotIn(command, events); self.assertNotIn("secret_table", events)
            self.assertEqual(len(count.read_text().splitlines()), 1)

    def test_manifest_and_provider_exports_use_shared_profile(self):
        data = {"schema_version": 1, "preset": "regulated", "providers": {p: True for p in ("codex", "claude", "gemini", "kiro")}, "operations": {"profile": "default-allow-operations-v1"}}
        validate_policy(data); config = normalized(data); files = target_files(config, b"guide")
        codex = tomllib.loads(files["codex/config.toml"].decode())
        self.assertEqual(codex["default_permissions"], "default-allow-operations-v1")
        capabilities = json.loads(files["capabilities.json"])
        self.assertTrue(all(item["operation_policy"]["activation"] == "PENDING_PREFLIGHT" for item in capabilities.values()))
        for provider, path in {"claude": "claude/settings.json", "gemini": "gemini/settings.json", "kiro": "kiro/hooks/engineering-governance.json"}.items():
            self.assertIn(f"--provider {provider} --profile default-allow-operations-v1", files[path].decode())
        for path in ("codex/config.toml", "claude/settings.json", "gemini/settings.json", "kiro/hooks/engineering-governance.json"):
            self.assertIn("~/.nix-profile/bin/python3", files[path].decode())

    def test_generated_native_hook_shapes_pass_structural_preflight(self):
        data = {"schema_version": 1, "preset": "regulated", "providers": {p: True for p in ("codex", "claude", "gemini", "kiro")}, "operations": {"profile": "default-allow-operations-v1"}}
        files = target_files(normalized(data), b"guide")
        paths = {"codex": "codex/config.toml", "claude": "claude/settings.json", "gemini": "gemini/settings.json", "kiro": "kiro/hooks/engineering-governance.json"}
        with tempfile.TemporaryDirectory() as tmp:
            for provider, generated_path in paths.items():
                config = Path(tmp) / Path(generated_path).name; config.write_bytes(files[generated_path])
                status = Path(tmp) / f"{provider}.status.json"
                env = os.environ | {"AGENT_POLICY_CONFIG": str(config), "AGENT_NOTIFY_HOOK": str(Path(tmp) / "absent")}
                result = subprocess.run([sys.executable, str(PREFLIGHT), "--provider", provider, "--status-file", str(status)], env=env, capture_output=True)
                self.assertEqual(result.returncode, 0, (provider, result.stderr)); self.assertEqual(json.loads(status.read_text())["status"], "ENFORCED")

    def test_managed_json_fragment_preserves_native_settings_and_repairs_hook(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); target = root / "settings.json"; source = root / "desired.json"
            target.write_text(json.dumps({"model": "provider-choice", "permissions": {"user-custom": {}}, "features": {"web_search": True}, "hooks": {"BeforeTool": [{"command": "user-hook"}, {"command": "bash ~/.config/agents/governance/old.sh"}]}}))
            source.write_text(json.dumps({"model": "harness-choice", "permissions": {"default-allow-operations-v1": {}}, "features": {"network_proxy": True}, "hooks": {"BeforeTool": [{"command": "bash ~/.config/agents/governance/pre-tool-gate.sh --provider gemini --managed-fragment harness-operation-policy-v1"}]}}))
            for _ in range(5):
                subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--source", str(source)], check=True)
            merged = json.loads(target.read_text())
            self.assertEqual(merged["model"], "provider-choice")
            self.assertEqual(set(merged["permissions"]), {"user-custom", "default-allow-operations-v1"})
            self.assertEqual(merged["features"], {"web_search": True, "network_proxy": True})
            commands = [item["command"] for item in merged["hooks"]["BeforeTool"]]
            self.assertEqual(commands, ["user-hook", "bash ~/.config/agents/governance/old.sh", "bash ~/.config/agents/governance/pre-tool-gate.sh --provider gemini --managed-fragment harness-operation-policy-v1"])
            self.assertLessEqual(len(list(root.glob("settings.json.backup.*"))), 3)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_managed_kiro_hook_list_preserves_user_entries_and_repairs_by_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); target = root / "hooks.json"; source = root / "desired.json"
            target.write_text(json.dumps({"hooks": [{"name": "user-hook", "command": "custom"}, {"name": "harness-operation-policy-v1", "command": "tampered"}]}))
            desired = {"hooks": [{"name": "harness-operation-policy-v1", "command": "gate --managed-fragment harness-operation-policy-v1"}]}
            source.write_text(json.dumps(desired))
            subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--source", str(source)], check=True)
            self.assertEqual(json.loads(target.read_text())["hooks"], [{"name": "user-hook", "command": "custom"}, desired["hooks"][0]])

    def test_managed_sync_backs_up_but_does_not_replace_malformed_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); target = root / "settings.json"; source = root / "desired.json"
            target.write_text("{malformed"); source.write_text("{}")
            result = subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--source", str(source)], capture_output=True)
            self.assertNotEqual(result.returncode, 0); self.assertEqual(target.read_text(), "{malformed")
            self.assertEqual(len(list(root.glob("settings.json.backup.*"))), 1)

    def test_managed_fragment_rollback_removes_only_owned_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"; source = Path(tmp) / "desired.json"
            target.write_text(json.dumps({"model": "provider", "default_permissions": "user-profile", "approval_policy": "never", "permissions": {"user": {}}, "features": {"network_proxy": False, "web_search": True}, "hooks": {"BeforeTool": [{"command": "user"}]}}))
            source.write_text(json.dumps({"default_permissions": "default-allow-operations-v1", "approval_policy": "never", "permissions": {"default-allow-operations-v1": {"network": True}}, "features": {"network_proxy": True}, "hooks": {"BeforeTool": [{"command": "gate --managed-fragment harness-operation-policy-v1"}]}}))
            subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--source", str(source)], check=True)
            subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--remove-fragments"], check=True)
            rolled_back = json.loads(target.read_text())
            self.assertEqual(rolled_back["hooks"]["BeforeTool"], [{"command": "user"}])
            self.assertEqual(rolled_back["default_permissions"], "user-profile")
            self.assertEqual(rolled_back["approval_policy"], "never")
            self.assertEqual(rolled_back["features"], {"network_proxy": False, "web_search": True})
            self.assertEqual(rolled_back["permissions"], {"user": {}}); self.assertEqual(rolled_back["model"], "provider")
            self.assertFalse(target.with_name("settings.json.harness-state.json").exists())

    def test_managed_snapshot_tracks_user_owned_field_edits_between_activations(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"; source = Path(tmp) / "desired.json"
            target.write_text(json.dumps({"default_permissions": "first-user-profile"}))
            source.write_text(json.dumps({"default_permissions": "default-allow-operations-v1", "hooks": {"BeforeTool": [{"command": "gate --managed-fragment harness-operation-policy-v1"}]}}))
            subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--source", str(source)], check=True)
            active = json.loads(target.read_text()); active["default_permissions"] = "new-user-profile"
            target.write_text(json.dumps(active))
            subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--source", str(source)], check=True)
            subprocess.run([sys.executable, str(SYNC), "--format", "json", "--target", str(target), "--remove-fragments"], check=True)
            self.assertEqual(json.loads(target.read_text())["default_permissions"], "new-user-profile")

    def test_managed_codex_toml_preserves_native_settings_and_rolls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"; source = Path(tmp) / "desired.toml"
            target.write_text('model = "user-model"\ndefault_permissions = "user-profile"\n[features]\nweb_search = true\n')
            source.write_text('default_permissions = "default-allow-operations-v1"\n[features]\nnetwork_proxy = true\n[permissions.default-allow-operations-v1]\nnetwork = true\n')
            subprocess.run([sys.executable, str(SYNC), "--format", "toml", "--target", str(target), "--source", str(source)], check=True)
            active = tomllib.loads(target.read_text())
            self.assertEqual(active["model"], "user-model"); self.assertTrue(active["features"]["web_search"])
            self.assertEqual(active["default_permissions"], "default-allow-operations-v1")
            subprocess.run([sys.executable, str(SYNC), "--format", "toml", "--target", str(target), "--remove-fragments"], check=True)
            restored = tomllib.loads(target.read_text())
            self.assertEqual(restored["default_permissions"], "user-profile")
            self.assertEqual(restored["features"], {"web_search": True}); self.assertNotIn("permissions", restored)

    def test_preflight_reports_enforced_and_stops_on_missing_managed_hook(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); config = root / "settings.json"; status = root / "status.json"
            env = os.environ | {"AGENT_POLICY_CONFIG": str(config), "AGENT_NOTIFY_HOOK": str(root / "absent")}
            valid = {"hooks": {
                "SessionStart": [{"hooks": [{"command": "policy-preflight.py --provider claude --managed-fragment harness-policy-preflight-v1"}]}],
                "PreToolUse": [
                    {"matcher": "Bash", "hooks": [{"command": "pre-tool-gate.sh --provider claude --profile default-allow-operations-v1 --managed-fragment harness-operation-policy-v1"}]},
                    {"matcher": "Read|Write|Edit|NotebookEdit", "hooks": [{"command": "path-guard.sh --managed-fragment harness-path-invariants-v1"}]},
                ],
            }}
            config.write_text(json.dumps(valid))
            ok = subprocess.run([sys.executable, str(PREFLIGHT), "--provider", "claude", "--status-file", str(status)], env=env)
            self.assertEqual(ok.returncode, 0); self.assertEqual(json.loads(status.read_text())["status"], "ENFORCED")
            config.write_text('{"note":"default-allow-operations-v1","hooks":[]}')
            failed = subprocess.run([sys.executable, str(PREFLIGHT), "--provider", "claude", "--status-file", str(status)], env=env, capture_output=True)
            self.assertEqual(failed.returncode, 2)
            signatures = "policy-preflight.py --provider claude --managed-fragment harness-policy-preflight-v1 pre-tool-gate.sh --provider claude --profile default-allow-operations-v1 --managed-fragment harness-operation-policy-v1"
            config.write_text(json.dumps({"note": signatures, "hooks": []}))
            false_positive = subprocess.run([sys.executable, str(PREFLIGHT), "--provider", "claude", "--status-file", str(status)], env=env, capture_output=True)
            self.assertEqual(false_positive.returncode, 2)
            valid["hooks"]["PreToolUse"][1]["matcher"] = "Read"
            config.write_text(json.dumps(valid))
            wrong_matcher = subprocess.run([sys.executable, str(PREFLIGHT), "--provider", "claude", "--status-file", str(status)], env=env, capture_output=True)
            self.assertEqual(wrong_matcher.returncode, 2)

if __name__ == "__main__": unittest.main()
