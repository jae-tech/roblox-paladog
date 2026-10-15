"""P4 evidence rejects stale builds, spoofed summaries, leaks and missing runtime proof."""
import copy
import importlib.util
import io
import json
import tempfile
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("verify_p4", Path(__file__).parents[1] / "verify_p4.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

LENGTHS = {"ServerScriptService.GameServer.Simulation.World": 100}
RAW = {"suite": "T-P4", "environment": "StudioServer", "seed": 12345, "status": "PASS",
       "cases": [{"id": "thero02-release", "expected": "4", "actual": "4", "tick": 4, "status": "PASS"}],
       "failures": []}
CLI = {**copy.deepcopy(RAW), "environment": "PureLuau"}
GOOD = {
    "schema": "p4-studio-evidence/1", "studio_id": "instance:x", "gameId": 10771015944,
    "sourceLengths": dict(LENGTHS),
    "studioSuite": {"suite": "T-P4", "environment": "StudioServer", "status": "PASS", "cases": 1, "failures": []},
    "rawStudioSuite": RAW,
    "liveMatch": {"cast": "Accepted", "manaBeforeCast": 10000, "manaAfterCast": 0,
                  "castAcceptedTick": 10, "castReleaseTick": 14, "projectileHitTick": 18,
                  "targetHpBefore": 300, "targetHpAfter": 200, "heroXFirst": 0.3, "heroXLater": 5.4,
                  "ticksFirst": 10, "ticksLater": 50, "snapshotKeys": ["entityId", "x", "hp"],
                  "snapshotProjectileKeys": ["projectileId", "x"],
                  "snapshotHeroActionKeys": ["kind", "releaseTick"], "renderInstancesCreated": 0},
    "teardown": {"rigStopped": True, "playtestEnded": True},
}


class StudioEvidenceTests(unittest.TestCase):
    def test_good(self):
        self.assertTrue(gate.audit_studio(copy.deepcopy(GOOD), 1, LENGTHS, CLI))

    def test_weakened_evidence_fails(self):
        mutations = [
            lambda e: e.update(schema="p3-studio-evidence/1"),
            lambda e: e.update(studio_id=""),
            lambda e: e.update(gameId=0),
            lambda e: e.update(gameId=True),
            lambda e: e.update(gameId=99999999),
            lambda e: e["sourceLengths"].update({next(iter(LENGTHS)): 99}),
            lambda e: e["studioSuite"].update(suite="T-P3"),
            lambda e: e["studioSuite"].update(environment="PureLuau"),
            lambda e: e["studioSuite"].update(cases=True),
            lambda e: e["studioSuite"].update(cases=0),
            lambda e: e["studioSuite"].update(cases=2),
            lambda e: e["studioSuite"].update(failures=["failed"]),
            lambda e: e["rawStudioSuite"].update(cases=[]),
            lambda e: e["rawStudioSuite"].update(suite="T-P3"),
            lambda e: e["rawStudioSuite"].update(seed=42),
            lambda e: e["rawStudioSuite"]["cases"][0].update(id="unrelated-assertion"),
            lambda e: e["rawStudioSuite"]["cases"][0].update(tick=5),
            lambda e: e["rawStudioSuite"]["cases"][0].update(actual="5"),
            lambda e: e["rawStudioSuite"]["cases"][0].update(status="FAIL"),
            lambda e: e["rawStudioSuite"]["cases"][0].pop("actual"),
            lambda e: e["rawStudioSuite"].update(failures=["hidden failure"]),
            lambda e: e["liveMatch"].update(cast="Rejected"),
            lambda e: e["liveMatch"].update(manaAfterCast=1),
            lambda e: e["liveMatch"].update(castReleaseTick=13),
            lambda e: e["liveMatch"].update(projectileHitTick=13),
            lambda e: e["liveMatch"].update(projectileHitTick=14),
            lambda e: e["liveMatch"].update(targetHpAfter=201),
            lambda e: e["liveMatch"].update(heroXLater=0.3),
            lambda e: e["liveMatch"].update(ticksLater=10),
            lambda e: e["liveMatch"].update(castAcceptedTick=True),
            lambda e: e["liveMatch"].update(heroXLater=float("nan")),
            lambda e: e["liveMatch"].update(targetHpBefore=float("inf")),
            lambda e: e["liveMatch"]["snapshotKeys"].append("attackPower"),
            lambda e: e["liveMatch"]["snapshotProjectileKeys"].append("damage"),
            lambda e: e["liveMatch"]["snapshotProjectileKeys"].append("hitEntityIds"),
            lambda e: e["liveMatch"]["snapshotHeroActionKeys"].append("reservedProjectileSlot"),
            lambda e: e["liveMatch"].update(snapshotProjectileKeys=[]),
            lambda e: e["liveMatch"].update(renderInstancesCreated=1),
            lambda e: e["liveMatch"].update(renderInstancesCreated=False),
            lambda e: e["teardown"].update(playtestEnded=False),
            lambda e: e["teardown"].update(rigStopped=1),
            lambda e: e.update(teardown={}),
        ]
        for i, mutate in enumerate(mutations):
            with self.subTest(mutation=i):
                evidence = copy.deepcopy(GOOD)
                mutate(evidence)
                with self.assertRaises((ValueError, KeyError)):
                    gate.audit_studio(evidence, 1, LENGTHS, CLI)

    def test_invalid_cli_count(self):
        for count in (True, False, 0, -1, 1.0, "1"):
            with self.subTest(count=count), self.assertRaises(ValueError):
                gate.audit_studio(copy.deepcopy(GOOD), count, LENGTHS, CLI)

    def test_raw_cli_report(self):
        report = copy.deepcopy(RAW)
        report["environment"] = "PureLuau"
        self.assertEqual(gate.audit_report(report, "PureLuau"), 1)
        report["cases"][0]["actual"] = "spoofed"
        with self.assertRaises(ValueError):
            gate.audit_report(report, "PureLuau")

    def test_repeated_studio_cases_reject_fresh_distinct_cli_cases(self):
        cli = copy.deepcopy(CLI)
        cli["cases"].append({**copy.deepcopy(cli["cases"][0]), "id": "tprojectile01-hit"})
        evidence = copy.deepcopy(GOOD)
        evidence["studioSuite"]["cases"] = 2
        evidence["rawStudioSuite"]["cases"] *= 2
        with self.assertRaises(ValueError):
            gate.audit_studio(evidence, 2, LENGTHS, cli)

    def test_no_empty_source_build(self):
        evidence = copy.deepcopy(GOOD)
        evidence["sourceLengths"] = {}
        with self.assertRaises(ValueError):
            gate.audit_studio(evidence, 1, {}, CLI)


class GateOutputTests(unittest.TestCase):
    def run_gate(self, cli_status):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data/balance").mkdir(parents=True)
            (root / "data/balance/mvp-proto-001.json").write_text('{"balanceHash":"actual-balance-hash"}')
            raw = copy.deepcopy(RAW)
            raw["environment"] = "PureLuau"
            raw["cases"].append({"id": "tprojectile01-hit", "expected": "1", "actual": "1",
                                 "tick": 4, "status": "PASS"})
            results = [SimpleNamespace(stdout=json.dumps(raw), stderr="", returncode=cli_status),
                       SimpleNamespace(stdout="actual-git-build\n", stderr="", returncode=0)]
            with patch.object(gate, "ROOT", root), patch.object(gate.subprocess, "run", side_effect=results), \
                    patch("sys.argv", ["verify_p4.py"]), redirect_stdout(io.StringIO()):
                code = gate.main()
            out = next((root / "artifacts/P4").iterdir())
            report = json.loads((out / "report.json").read_text())
            if cli_status == 0:
                for name in ("unit.json", "projectile.json", "cast.json", "unit.log", "environment.json"):
                    self.assertTrue((out / name).is_file(), name)
                environment = json.loads((out / "environment.json").read_text())
                self.assertEqual(environment["buildId"], "actual-git-build")
                self.assertEqual(environment["balanceHash"], "actual-balance-hash")
                self.assertEqual(environment["seed"], 12345)
            return code, report["status"]

    def test_missing_studio_is_blocked(self):
        self.assertEqual(self.run_gate(0), (2, "BLOCKED"))

    def test_cli_failure_takes_precedence_over_missing_studio(self):
        self.assertEqual(self.run_gate(1), (1, "FAIL"))


if __name__ == "__main__":
    unittest.main()
