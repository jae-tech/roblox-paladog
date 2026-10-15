"""verify_p3 Studio-evidence validator: good evidence passes, each weakened field fails."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("verify_p3", Path(__file__).parents[1] / "verify_p3.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

LENGTHS = {"ServerScriptService.GameServer.Simulation.World": 100}
GOOD = {
    "schema": "p3-studio-evidence/1", "studio_id": "instance:x", "gameId": 10771015944, "sourceLengths": dict(LENGTHS),
    "studioSuite": {"suite": "T-P3", "environment": "StudioServer", "status": "PASS", "cases": 88, "failures": []},
    "liveMatch": {"summon": "Accepted", "foodBeforeSummon": 12000, "foodAfterSummon": 2000, "allyXFirst": 0.3,
                  "allyXLater": 5.4, "ticksFirst": 10, "ticksLater": 50, "snapshotKeys": ["entityId", "x", "hp"],
                  "renderInstancesCreated": 0},
    "teardown": {"rigStopped": True, "playtestEnded": True},
}


class StudioEvidenceTests(unittest.TestCase):
    def test_good(self):
        self.assertTrue(gate.audit_studio(copy.deepcopy(GOOD), 88, LENGTHS))

    def test_weakened_evidence_fails(self):
        mutations = [
            lambda e: e.update(gameId=0),
            lambda e: e["sourceLengths"].update({"ServerScriptService.GameServer.Simulation.World": 99}),
            lambda e: e["studioSuite"].update(cases=87),
            lambda e: e["studioSuite"].update(status="FAIL"),
            lambda e: e["liveMatch"].update(summon="Rejected"),
            lambda e: e["liveMatch"].update(foodAfterSummon=12000),
            lambda e: e["liveMatch"].update(allyXLater=0.3),
            lambda e: e["liveMatch"]["snapshotKeys"].append("attackPower"),
            lambda e: e["liveMatch"].update(renderInstancesCreated=3),
            lambda e: e["teardown"].update(playtestEnded=False),
        ]
        for mutate in mutations:
            evidence = copy.deepcopy(GOOD)
            mutate(evidence)
            with self.assertRaises((ValueError, KeyError)):
                gate.audit_studio(evidence, 88, LENGTHS)


if __name__ == "__main__":
    unittest.main()
