from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_remake  # noqa: E402
from balance_lib import load_sources  # noqa: E402


class RemakeDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import json
        design = json.loads((build_remake.ROOT / "data/remake/design.json").read_text(encoding="utf-8"))
        cls.files = build_remake.outputs(load_sources(), design)

    def test_committed_outputs_match_regeneration(self):
        for path, text in self.files.items():
            self.assertEqual((build_remake.ROOT / path).read_text(encoding="utf-8"), text, path)

    def test_release_tree_has_no_research_names(self):
        for path in (build_remake.OUT_SERVER, build_remake.OUT_CATALOG):
            text = self.files[path].lower()
            for word in ("좀비", "아군(", "팔라독", "다크독", "냠냠", "paladog", "darkdog", "research ="):
                self.assertFalse(word in text, f"{path}: {word}")

    def test_golden_rejects_drift(self):
        db = build_remake.parse(load_sources())
        db["units"][4]["levels"]["hp"][0] = 4000  # N5/N6 swap undone
        with self.assertRaises(build_remake.DataError):
            build_remake.golden(db)


if __name__ == "__main__":
    unittest.main()
