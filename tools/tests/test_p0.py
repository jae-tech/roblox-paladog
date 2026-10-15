import json
import subprocess
import sys
from unittest.mock import patch
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("verify_p0", Path(__file__).parents[1] / "verify_p0.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ProductionIsolationTests(unittest.TestCase):
    def audit(self, body):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "place.rbxlx"
            path.write_text("<roblox>" + body + "</roblox>")
            return gate.audit_production(path)

    def test_empty_production(self):
        self.assertTrue(self.audit('<Item class="Folder"><Properties><string name="Name">Environment</string></Properties></Item>'))

    def test_harness_rejected(self):
        with self.assertRaises(ValueError):
            self.audit('<Item class="Folder"><Properties><string name="Name">TestSupport</string></Properties></Item>')

    def test_remote_rejected(self):
        with self.assertRaises(ValueError):
            self.audit('<Item class="RemoteEvent"/>')

    def test_source_dependency_rejected(self):
        with self.assertRaises(ValueError):
            self.audit('<ProtectedString name="Source">require(game.ServerScriptService.TestSupport)</ProtectedString>')


class ProjectContractTests(unittest.TestCase):
    def setUp(self):
        self.production = json.loads((gate.ROOT / "default.project.json").read_text())
        self.test = json.loads((gate.ROOT / "test.project.json").read_text())

    def test_matching_trees(self):
        self.assertTrue(gate.audit_projects(self.production, self.test))

    def test_renamed_fixture_path_rejected(self):
        self.production["tree"]["ReplicatedStorage"]["Clock"] = {"$path": "tests/fixtures/FakeClock.luau"}
        with self.assertRaises(ValueError):
            gate.audit_projects(self.production, self.test)

    def test_divergent_test_tree_rejected(self):
        self.test["tree"]["ServerScriptService"]["GameServer"]["$path"] = "src/other-server"
        with self.assertRaises(ValueError):
            gate.audit_projects(self.production, self.test)

    def test_missing_rojo_stays_blocked(self):
        original = subprocess.run
        def run(argv, **kwargs):
            if argv[0] == "rojo":
                raise FileNotFoundError("regression: missing rojo")
            if "unittest" in argv:
                return subprocess.CompletedProcess(argv, 0, "outer regression suite owns this check", "")
            return original(argv, **kwargs)
        with patch.object(sys, "argv", ["verify_p0.py", "--local-only"]), patch.object(gate.subprocess, "run", side_effect=run):
            self.assertEqual(gate.main(), 2)


class StudioEvidenceTests(unittest.TestCase):
    MARKER = "lantern-p0-foundation-v1"

    def setUp(self):
        self.lengths = {"ReplicatedStorage.Shared.BootstrapInfo": 170}
        case = {"id": "c", "expected": "1", "actual": "1", "tick": 0, "status": "PASS"}
        failed = {"id": "intentional-failure", "expected": "1", "actual": "2", "tick": 0, "status": "FAIL"}
        self.evidence = {
            "schema": "p0-studio-evidence/1", "studio_id": "instance:test", "gameId": 10771015944,
            "testBuildMarker": True, "sourceLengths": dict(self.lengths),
            "boot": {"server": {"ready": True, "marker": self.MARKER}, "client": {"ready": True, "marker": self.MARKER}},
            "studioVersion": "0.743", "characterAutoLoads": False, "playerCharacters": ["nil"], "environmentChildren": 0,
            "harness": {
                "authorizedUniverseAttr": 10771015944,
                "normal": {"environment": "StudioServer", "status": "PASS", "failures": [], "cases": [case]},
                "intentional": {"environment": "StudioServer", "status": "FAIL", "failures": ["intentional-failure"],
                                "cases": [case, failed]},
                "unsupportedSuite": {"ok": False},
            },
            "clientHarness": {"ok": True, "result": {"ready": True, "marker": self.MARKER}, "gameId": 10771015944,
                              "character": "nil"},
            "guardRejectionUnapproved": {"gameId": 0, "server": "requires Studio, test build marker, and approved universe",
                                         "client": "universe not approved"},
            "productionRuntimeRequire": {"status": "WAIVED", "decidedBy": "user", "basis": "static audit"},
        }

    def audit(self):
        return gate.audit_studio_evidence(self.evidence, self.lengths)

    def test_valid_evidence(self):
        self.assertTrue(self.audit())

    def test_unpublished_universe_rejected(self):
        self.evidence["gameId"] = 0
        with self.assertRaises(ValueError):
            self.audit()

    def test_unapproved_universe_rejected(self):
        self.evidence["gameId"] = 123
        with self.assertRaises(ValueError):
            self.audit()

    def test_stale_build_rejected(self):
        self.evidence["sourceLengths"]["ReplicatedStorage.Shared.BootstrapInfo"] = 171
        with self.assertRaises(ValueError):
            self.audit()

    def test_wrong_marker_rejected(self):
        self.evidence["boot"]["client"]["marker"] = "old"
        with self.assertRaises(ValueError):
            self.audit()

    def test_character_spawn_rejected(self):
        self.evidence["playerCharacters"] = ["Model"]
        with self.assertRaises(ValueError):
            self.audit()

    def test_failing_normal_suite_rejected(self):
        self.evidence["harness"]["normal"]["status"] = "FAIL"
        with self.assertRaises(ValueError):
            self.audit()

    def test_swallowed_intentional_failure_rejected(self):
        self.evidence["harness"]["intentional"]["status"] = "PASS"
        with self.assertRaises(ValueError):
            self.audit()

    def test_direct_suite_run_rejected(self):
        self.evidence["harness"]["normal"]["environment"] = "StudioServer-direct"
        with self.assertRaises(ValueError):
            self.audit()

    def assert_rejected(self, mutate):
        mutate(self.evidence)
        with self.assertRaises((ValueError, KeyError, TypeError)):
            self.audit()

    def test_no_player_rejected(self):
        self.assert_rejected(lambda e: e.update(playerCharacters=[]))

    def test_failing_case_under_pass_status_rejected(self):
        self.assert_rejected(lambda e: e["harness"]["normal"]["cases"][0].update(status="FAIL"))

    def test_extra_intentional_failure_rejected(self):
        self.assert_rejected(lambda e: e["harness"]["intentional"]["cases"][0].update(status="FAIL"))

    def test_unbacked_production_pass_rejected(self):
        self.assert_rejected(lambda e: e.update(productionRuntimeRequire={"status": "PASS"}))

    def test_undecided_waiver_rejected(self):
        self.assert_rejected(lambda e: e["productionRuntimeRequire"].pop("decidedBy"))

    def test_missing_studio_version_rejected(self):
        self.assert_rejected(lambda e: e.pop("studioVersion"))

    def test_client_other_universe_rejected(self):
        self.assert_rejected(lambda e: e["clientHarness"].update(gameId=1))

    def test_unauthorized_server_rejected(self):
        self.assert_rejected(lambda e: e["harness"].update(authorizedUniverseAttr=None))

    def test_missing_guard_control_rejected(self):
        self.assert_rejected(lambda e: e.pop("guardRejectionUnapproved"))

    def test_nonempty_environment_rejected(self):
        self.assert_rejected(lambda e: e.update(environmentChildren=1))

    def test_sourcemap_lengths_match_local_files(self):
        sourcemap = {"name": "Root", "children": [{"name": "ReplicatedStorage", "children": [
            {"name": "Shared", "children": [{"name": "BootstrapInfo", "filePaths": ["src/shared/BootstrapInfo.luau"]}]}]}]}
        expected = len((gate.ROOT / "src/shared/BootstrapInfo.luau").read_bytes())
        self.assertEqual(gate.sourcemap_lengths(sourcemap), {"ReplicatedStorage.Shared.BootstrapInfo": expected})


if __name__ == "__main__":
    unittest.main()
