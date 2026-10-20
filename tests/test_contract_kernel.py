import copy
import json
from pathlib import Path
import tempfile
import unittest

from agent_harness.domain.permissions import decide
from agent_harness.domain.config import HarnessError
from agent_harness.egress.kernel import compare_decisions
from agent_harness.cli import parser


FIXTURE = Path(__file__).parent / "fixtures/contract-kernel/decision-v2.json"


def merge(target, patch):
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = copy.deepcopy(value)


class ContractKernelFixtureConformanceTests(unittest.TestCase):
    def test_python_reference_matches_frozen_v2_fixture(self):
        fixture = json.loads(FIXTURE.read_text())
        for case in fixture["cases"]:
            with self.subTest(case=case["name"]):
                request = copy.deepcopy(fixture["base"])
                merge(request, case["patch"])
                if "grant_patch" in case:
                    merge(request["grants"][0], case["grant_patch"])
                actual = decide(request)
                self.assertEqual(
                    {key: actual[key] for key in ("decision", "reason_code", "grant_id")},
                    case["expected"],
                )
                self.assertEqual(actual["contract_version"], 2)
                self.assertEqual(actual["policy_revision"], request["policy_revision"])
                self.assertEqual(actual["mode"], "python-reference")
                self.assertFalse(actual["authoritative"])

    def test_runtime_comparison_observes_parity_without_authority(self):
        fixture = json.loads(FIXTURE.read_text())
        expected = decide(fixture["base"])
        with tempfile.TemporaryDirectory() as raw:
            kernel = Path(raw) / "kernel"
            kernel.write_text(
                "#!/bin/sh\n"
                "cat >/dev/null\n"
                f"printf '%s\\n' '{json.dumps({**expected, 'mode': 'shadow'})}'\n"
            )
            kernel.chmod(0o755)
            result = compare_decisions(fixture["base"], kernel)

        self.assertEqual(result["status"], "IN_SYNC")
        self.assertFalse(result["authoritative"])
        self.assertEqual(result["differences"], [])
        self.assertEqual(result["python_reference"]["mode"], "python-reference")
        self.assertEqual(result["rust_shadow"]["mode"], "shadow")

    def test_runtime_comparison_reports_drift_without_selecting_a_winner(self):
        fixture = json.loads(FIXTURE.read_text())
        drifted = {
            **decide(fixture["base"]),
            "mode": "shadow",
            "decision": "DENY",
            "reason_code": "simulated_drift",
            "grant_id": None,
        }
        with tempfile.TemporaryDirectory() as raw:
            kernel = Path(raw) / "kernel"
            kernel.write_text(
                "#!/bin/sh\n"
                "cat >/dev/null\n"
                f"printf '%s\\n' '{json.dumps(drifted)}'\n"
            )
            kernel.chmod(0o755)
            result = compare_decisions(fixture["base"], kernel)

        self.assertEqual(result["status"], "DRIFTED")
        self.assertFalse(result["authoritative"])
        self.assertEqual(result["differences"], ["decision", "grant_id", "reason_code"])
        self.assertNotIn("selected_decision", result)

    def test_compare_decision_cli_uses_an_explicit_kernel_port(self):
        fixture = json.loads(FIXTURE.read_text())
        expected = {**decide(fixture["base"]), "mode": "shadow"}
        with tempfile.TemporaryDirectory() as raw:
            request_path = Path(raw) / "request.json"
            request_path.write_text(json.dumps(fixture["base"]))
            kernel = Path(raw) / "kernel"
            kernel.write_text(
                "#!/bin/sh\n"
                "cat >/dev/null\n"
                f"printf '%s\\n' '{json.dumps(expected)}'\n"
            )
            kernel.chmod(0o755)
            args = parser().parse_args([
                "compare-decision", "--request", str(request_path), "--kernel", str(kernel)
            ])
            result = args.handler(args)

        self.assertEqual(result["status"], "IN_SYNC")
        self.assertFalse(result["authoritative"])

    def test_runtime_comparison_rejects_malformed_typed_ingress(self):
        fixture = json.loads(FIXTURE.read_text())
        cases = []
        null_grants = copy.deepcopy(fixture["base"])
        null_grants["grants"] = None
        cases.append(null_grants)
        wrong_time = copy.deepcopy(fixture["base"])
        wrong_time["now"] = "100"
        cases.append(wrong_time)
        unknown_status = copy.deepcopy(fixture["base"])
        unknown_status["enforcement"]["status"] = "UNKNOWN"
        cases.append(unknown_status)
        object_status = copy.deepcopy(fixture["base"])
        object_status["enforcement"]["status"] = {}
        cases.append(object_status)
        array_status = copy.deepcopy(fixture["base"])
        array_status["enforcement"]["status"] = []
        cases.append(array_status)
        invalid_operation = copy.deepcopy(fixture["base"])
        invalid_operation["grants"][0]["allowed_operations"] = [{}]
        cases.append(invalid_operation)
        oversized_time = copy.deepcopy(fixture["base"])
        oversized_time["now"] = 2**64
        cases.append(oversized_time)
        for request in cases:
            with self.subTest(request=request), self.assertRaises(HarnessError):
                compare_decisions(request, Path("/kernel-must-not-run"))

    def test_runtime_comparison_rejects_invalid_shadow_envelopes(self):
        fixture = json.loads(FIXTURE.read_text())
        invalid = {**decide(fixture["base"]), "mode": "shadow", "authoritative": True}
        with tempfile.TemporaryDirectory() as raw:
            kernel = Path(raw) / "kernel"
            kernel.write_text(
                "#!/bin/sh\n"
                "cat >/dev/null\n"
                f"printf '%s\\n' '{json.dumps(invalid)}'\n"
            )
            kernel.chmod(0o755)
            with self.assertRaises(HarnessError):
                compare_decisions(fixture["base"], kernel)


if __name__ == "__main__":
    unittest.main()
