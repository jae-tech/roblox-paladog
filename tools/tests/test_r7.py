import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_r7 as gate  # noqa: E402


class StudioEvidenceTests(unittest.TestCase):
    def setUp(self):
        case = {"id": "c", "expected": "1", "actual": "1", "tick": 0, "status": "PASS"}
        self.cli = {"T-R1": {"cases": [case]}, "T-R4": {"cases": [case]}}
        self.lengths = {"ServerScriptService.GameServer.Runtime": 10}
        scenario = {"status": "PASS", "input": "real", "steps": ["click"], "runtimeErrors": 0}
        self.evidence = {
            "schema": "r7-studio-evidence/1", "studio_id": "instance:test", "gameId": 10771015944,
            "sourceLengths": dict(self.lengths),
            "suites": {
                "T-R1": {"environment": "StudioServer", "status": "PASS", "failures": [], "count": 1,
                         "hash": gate.case_hash([dict(case, tick=9)])},
                "T-R4": {"environment": "StudioClient", "status": "PASS", "failures": [], "count": 1,
                         "hash": gate.case_hash([case])},
            },
            "load": {"ticks": 18000, "p50": 5, "p95": 7, "p99": 8, "max": 12, "status": "PASS", "failures": [], "count": 43},
            "play": {name: dict(scenario) for name in gate.PLAY_SCENARIOS},
            "teardown": {"playtestStopped": True},
        }

    def test_valid_evidence_passes(self):
        self.assertTrue(gate.audit_studio(self.evidence, self.cli, self.lengths))

    def reject(self, mutate):
        evidence = copy.deepcopy(self.evidence)
        mutate(evidence)
        with self.assertRaises(ValueError):
            gate.audit_studio(evidence, self.cli, self.lengths)

    def test_rejects_weak_evidence(self):
        self.reject(lambda e: e.update(gameId=1))
        self.reject(lambda e: e["sourceLengths"].update({"x": 1}))
        self.reject(lambda e: e["suites"].pop("T-R4"))
        self.reject(lambda e: e["suites"]["T-R1"].update(hash="00000000"))
        self.reject(lambda e: e["suites"]["T-R1"].update(count=2))
        self.reject(lambda e: e["suites"]["T-R4"].update(environment="StudioServer"))
        self.reject(lambda e: e["load"].update(ticks=900))
        self.reject(lambda e: e["load"].update(p95=20))
        self.reject(lambda e: e["load"].update(status="FAIL"))
        self.reject(lambda e: e["play"]["survival"].update(input="module"))
        self.reject(lambda e: e["play"]["shadow"].update(runtimeErrors=2))
        self.reject(lambda e: e["teardown"].update(playtestStopped=False))

    def test_hash_ignores_ticks_but_not_order(self):
        a = {"id": "a", "expected": "1", "actual": "1", "status": "PASS", "tick": 1}
        b = {"id": "b", "expected": "1", "actual": "1", "status": "PASS", "tick": 2}
        self.assertEqual(gate.case_hash([a, b]), gate.case_hash([dict(a, tick=5), b]))
        self.assertNotEqual(gate.case_hash([a, b]), gate.case_hash([b, a]))
        self.assertEqual("811c9dc5", gate.case_hash([]))


if __name__ == "__main__":
    unittest.main()
