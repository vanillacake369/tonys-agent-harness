import copy
import json
from pathlib import Path
import unittest

from agent_harness.domain.permissions import decide


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


if __name__ == "__main__":
    unittest.main()
