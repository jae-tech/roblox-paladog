"""verify_p2 isolation-evidence validator: real evidence passes, each weakened field fails."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("verify_p2", Path(__file__).parents[1] / "verify_p2.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

LENGTHS = {"ReplicatedStorage.Shared.Protocol": 100}
GOOD = {
    "sourceLengths": dict(LENGTHS),
    "schema": "p2-isolation-evidence/1", "studio_id": "instance:x", "gameId": 10771015944,
    "studioSuite": {"suite": "T-P2", "environment": "StudioServer", "status": "PASS", "cases": 99, "failures": []},
    "clients": {
        "attacker": {"userId": -1, "matchId": "a", "bootstrap": {"status": "Ready", "storage": "Mock/InMemory"},
                     "snapshots": 10, "foreignSnapshots": 0,
                     "messages": ["client1-attack-001:Rejected:NotOwner", "client1-attack-002:Rejected:InvalidPayload",
                                  "client1-attack-003:Rejected:InvalidPayload",
                                  "client1-attack-004:Rejected:InvalidPayload"]},
        "victim": {"userId": -2, "matchId": "b", "bootstrap": {"status": "Ready", "storage": "Mock/InMemory"},
                   "snapshots": 10, "foreignSnapshots": 0, "messages": ["client2-start-0001:Committed"]},
    },
    "serverAfterAttack": {"victim": {"pendingSeqs": [], "axis": 0, "revision": 1}},
    "flood": {"sent": 1000, "attackerAdmitted": 20, "attackerReplies": 20, "dropped": 980, "victimDuringFlood": "Pending"},
    "teardown": {"rigStopped": True, "remotesRemoved": True, "playtestEnded": True},
}


class IsolationEvidenceTests(unittest.TestCase):
    def test_good(self):
        self.assertTrue(gate.audit_isolation(copy.deepcopy(GOOD), 99, LENGTHS))

    def test_weakened_evidence_fails(self):
        mutations = [
            lambda e: e.update(gameId=0),
            lambda e: e["sourceLengths"].update({"ReplicatedStorage.Shared.Protocol": 101}),
            lambda e: e["studioSuite"].update(cases=98),
            lambda e: e["clients"]["victim"].update(matchId="a"),
            lambda e: e["clients"]["victim"].update(foreignSnapshots=1),
            lambda e: e["clients"]["attacker"]["bootstrap"].update(storage="DataStore"),
            lambda e: e["clients"]["attacker"]["messages"].remove("client1-attack-001:Rejected:NotOwner"),
            lambda e: e["clients"]["victim"]["messages"].append("client1-summon-001:Pending"),
            lambda e: e["serverAfterAttack"]["victim"].update(pendingSeqs=[50]),
            lambda e: e["flood"].update(attackerAdmitted=21),
            lambda e: e["flood"].update(victimDuringFlood="Rejected"),
            lambda e: e["teardown"].update(playtestEnded=False),
        ]
        for mutate in mutations:
            evidence = copy.deepcopy(GOOD)
            mutate(evidence)
            with self.assertRaises((ValueError, KeyError)):
                gate.audit_isolation(evidence, 99, LENGTHS)


if __name__ == "__main__":
    unittest.main()
