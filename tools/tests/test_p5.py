"""P5 evidence anti-spoofing and explicit incomplete-device coverage."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout

spec = importlib.util.spec_from_file_location("verify_p5", Path(__file__).parents[1] / "verify_p5.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
LENGTHS = {"StarterPlayer.StarterPlayerScripts.GameClient.Runtime": 100}
CLI = {"suite": "T-P5", "environment": "PureLuau", "seed": 12345, "status": "PASS", "failures": [],
       "cases": [{"id": prefix + "fixture", "expected": "true", "actual": "true", "tick": 0, "status": "PASS"}
                 for prefix in ("tinput-", "net-", "tview-")]}


def fixture():
    raw = copy.deepcopy(CLI)
    raw["environment"] = "StudioServer"
    client = copy.deepcopy(CLI)
    client["environment"] = "StudioClient"
    layouts = []
    for width, height in sorted(gate.SIZES):
        layouts.append({"width": width, "height": height, "safeArea": {"width": width, "height": height},
                        "portraitHint": height > width,
                        "buttons": {name: {"x": 8 + i % 3 * 56, "y": 8 + i // 3 * 56,
                                            "width": 48, "height": 48} for i, name in enumerate(gate.BUTTONS)}})
    return {"schema": "p5-studio-evidence/1", "studio_id": "instance:x", "gameId": 10771015944,
            "sourceLengths": dict(LENGTHS), "rawStudioSuite": raw, "rawClientSuite": client,
            "studioSuite": {"suite": "T-P5", "environment": "StudioServer", "cases": 3, "status": "PASS", "failures": []},
            "pcInput": {"status": "PASS", "beforeX": 1, "afterX": 3, "releaseX": 3, "stoppedX": 4,
                        "stationaryXAfterWait": 4, "castAccepted": True, "castManaBefore": 10000,
                        "castManaAfter": 0, "guiSummonAccepted": True, "foodBefore": 30000, "foodAfter": 10000,
                        "focusNeutral": True, "neutralWithinSeconds": 0.2},
            "device": {"status": "PASS", "layouts": layouts, "screenshots": ["artifacts/P5/studio/pc.png"]},
            "render": {"status": "PASS", "digestBefore": "digest", "digestAfter": "digest",
                       "missingAssetFallback": True, "cleanup": True, "cameraRestored": True},
            "touch": {"status": "BLOCKED", "reason": "No MCP multi-touch injection; actual hardware not run"},
            "teardown": {"rigStopped": True, "playtestEnded": True}}


class StudioTests(unittest.TestCase):
    def audit(self, evidence):
        return gate.audit_studio(evidence, 3, LENGTHS, CLI)

    def test_explicit_touch_gap_remains_blocked(self):
        checks = self.audit(fixture())
        self.assertEqual([c["id"] for c in checks if c["status"] == "BLOCKED"], ["touch"])

    def test_real_touch_proof_can_pass(self):
        for source in ("PhysicalDevice", "EngineMultiTouchInput"):
            e = fixture()
            e["touch"] = {"status": "PASS", "source": source, "independentPointerIds": 2,
                          "simultaneousMoveAndCast": True, "cancelNeutral": True}
            self.assertTrue(all(c["status"] == "PASS" for c in self.audit(e)))

    def test_missing_runtime_groups_blocked(self):
        for key in ("pcInput", "device", "render", "touch"):
            e = fixture()
            del e[key]
            self.assertTrue(any(c["id"] == key and c["status"] == "BLOCKED" for c in self.audit(e)))

    def test_client_suite_required_for_gui_proof(self):
        e = fixture()
        del e["rawClientSuite"]
        self.assertEqual(sum(c["status"] == "BLOCKED" for c in self.audit(e)), 4)

    def test_protocol_and_build_spoofs_fail(self):
        changes = [lambda e: e.update(schema="p4-studio-evidence/1"), lambda e: e.update(studio_id=""),
                   lambda e: e.update(gameId=True), lambda e: e.update(gameId=1),
                   lambda e: e.update(sourceLengths={}), lambda e: e["sourceLengths"].update({next(iter(LENGTHS)): 101}),
                   lambda e: e["studioSuite"].update(cases=True), lambda e: e["studioSuite"].update(cases=4),
                   lambda e: e["studioSuite"].update(environment="StudioClient"),
                   lambda e: e["studioSuite"].update(failures=["hidden"]),
                   lambda e: e["rawStudioSuite"].update(seed=1),
                   lambda e: e["rawStudioSuite"].update(suite="T-P4"),
                   lambda e: e["rawStudioSuite"]["cases"].reverse(),
                   lambda e: e["rawStudioSuite"]["cases"][0].update(actual="false"),
                   lambda e: e["rawClientSuite"].update(environment="StudioServer"),
                   lambda e: e["rawClientSuite"]["cases"][0].update(id="swapped"),
                   lambda e: e["teardown"].update(rigStopped=1)]
        self.assert_mutations_fail(changes)
        for count in (True, 0, -1, 3.0):
            with self.subTest(count=count), self.assertRaises(ValueError):
                gate.audit_studio(fixture(), count, LENGTHS, CLI)

    def assert_mutations_fail(self, changes):
        for index, mutate in enumerate(changes):
            with self.subTest(mutation=index):
                e = fixture()
                mutate(e)
                with self.assertRaises(ValueError):
                    self.audit(e)

    def test_pc_invalid_observations_fail(self):
        values = {"beforeX": True, "afterX": 1, "stoppedX": 7, "stationaryXAfterWait": 4.01,
                  "castAccepted": 1, "castManaAfter": 1, "guiSummonAccepted": False,
                  "foodAfter": 30000, "foodBefore": float("inf"), "focusNeutral": 1,
                  "neutralWithinSeconds": 0.51, "releaseX": float("nan")}
        self.assert_mutations_fail([lambda e, k=k, v=v: e["pcInput"].update({k: v}) for k, v in values.items()])

    def test_device_invalid_observations_fail(self):
        self.assert_mutations_fail([
            lambda e: e["device"].update(screenshots=[]), lambda e: e["device"].update(screenshots=[False]),
            lambda e: e["device"]["layouts"].pop(),
            lambda e: e["device"]["layouts"].append(copy.deepcopy(e["device"]["layouts"][0])),
            lambda e: e["device"]["layouts"][0].update(width=True),
            lambda e: e["device"]["layouts"][0].update(portraitHint=False),
            lambda e: e["device"]["layouts"][0]["safeArea"].update(width=float("inf")),
            lambda e: e["device"]["layouts"][0]["buttons"]["Left"].update(width=47),
            lambda e: e["device"]["layouts"][0]["buttons"]["Left"].update(x=-1),
            lambda e: e["device"]["layouts"][0]["buttons"]["Right"].update(x=63),
            lambda e: e["device"]["layouts"][0]["buttons"].pop("Cast"),
        ])

    def test_render_invalid_observations_fail(self):
        self.assert_mutations_fail([lambda e, k=k, v=v: e["render"].update({k: v}) for k, v in
                                   {"digestBefore": "", "digestAfter": "different", "cleanup": 1,
                                    "cameraRestored": False, "missingAssetFallback": False}.items()])

    def test_touch_synthetic_pass_rejected(self):
        for source, ids in (("PureLuau", 2), ("InjectedRouter", 2), ("PhysicalDevice", True),
                            ("EngineMultiTouchInput", 1), ("PhysicalDevice", 2.0)):
            e = fixture()
            e["touch"] = {"status": "PASS", "source": source, "independentPointerIds": ids,
                          "simultaneousMoveAndCast": True, "cancelNeutral": True}
            with self.subTest(source=source, ids=ids), self.assertRaises(ValueError):
                self.audit(e)
        for key in ("simultaneousMoveAndCast", "cancelNeutral"):
            e = fixture()
            e["touch"] = {"status": "PASS", "source": "PhysicalDevice", "independentPointerIds": 2,
                          "simultaneousMoveAndCast": True, "cancelNeutral": True, key: 1}
            with self.assertRaises(ValueError):
                self.audit(e)

    def test_failed_or_malformed_groups_not_blocked(self):
        for name in ("pcInput", "device", "render", "touch"):
            for group in (False, [], {"status": "FAIL"}, {"status": "BLOCKED", "reason": ""}):
                e = fixture()
                e[name] = group
                with self.subTest(name=name, group=group), self.assertRaises(ValueError):
                    self.audit(e)


class OutputTests(unittest.TestCase):
    def run_gate(self, code=0, malformed=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data/balance").mkdir(parents=True)
            (root / "data/balance/mvp-proto-001.json").write_text('{"balanceHash":"balance"}')
            results = [SimpleNamespace(stdout="" if malformed else json.dumps(CLI), stderr="", returncode=code),
                       SimpleNamespace(stdout="git-build\n", stderr="", returncode=0)]
            with patch.object(gate, "ROOT", root), patch.object(gate.subprocess, "run", side_effect=results), \
                    patch("sys.argv", ["verify_p5.py"]), redirect_stdout(io.StringIO()):
                result = gate.main()
            out = next((root / "artifacts/P5").iterdir())
            for name in ("unit", "input", "network", "view", "environment", "report"):
                self.assertTrue((out / (name + ".json")).exists())
            env = json.loads((out / "environment.json").read_text())
            self.assertEqual(env["buildId"], "git-build")
            self.assertEqual(env["balanceHash"], "balance")
            return result, json.loads((out / "report.json").read_text())["status"]

    def test_missing_evidence_blocked(self):
        self.assertEqual(self.run_gate(), (2, "BLOCKED"))

    def test_cli_nonzero_precedes_blocked(self):
        self.assertEqual(self.run_gate(1), (1, "FAIL"))

    def test_missing_cli_clean_failure(self):
        self.assertEqual(self.run_gate(malformed=True), (1, "FAIL"))


if __name__ == "__main__":
    unittest.main()
