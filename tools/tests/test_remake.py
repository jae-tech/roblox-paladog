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

    def test_shadow_campaign_quest_contract(self):
        import json
        design = json.loads((build_remake.ROOT / "data/remake/design.json").read_text(encoding="utf-8"))
        db = build_remake.parse(load_sources())
        quests = build_remake.quests(db, design, "shadow")
        catalog = build_remake.catalog(db, design)
        self.assertEqual(len(quests), 120)
        self.assertEqual(len(catalog["stagesShadow"]), 120)
        self.assertEqual([sum(q[i]["gold"] for q in quests) for i in range(3)],
                         [90000, 78000, 136500])
        items = [q[2]["item"] for q in quests if q[2]["item"]["num"] > 0]
        self.assertEqual(len(items), 30)
        self.assertEqual({i["category"] for i in items}, {"sword", "amulet"})
        for stage, meta in enumerate(catalog["stagesShadow"], 1):
            mode = {0: "Boss", 3: "Jump", 6: "Horse", 9: "Dungeon"}.get(stage % 12, "Normal")
            self.assertEqual(meta["mode"], mode)
            self.assertEqual(meta["quests"], quests[stage - 1])
            if mode == "Jump":
                self.assertEqual(meta["quests"][0]["type"], 19)
                self.assertEqual(meta["quests"][2]["type"], 18)
                self.assertEqual(meta["quests"][2]["a"], db["jump"][(stage - 3) // 12]["s21"])

    def test_shadow_replacements_are_separate_from_light(self):
        db = build_remake.parse(load_sources())
        self.assertEqual(len(db["darkReplaced"]), 21)
        for row in db["darkReplaced"]:
            self.assertIs(build_remake.shadow_row(db, row["stage"]), row)
        self.assertIs(build_remake.shadow_row(db, 3), db["jump"][0])
        self.assertIs(build_remake.shadow_row(db, 6), db["darkWagon"][0])
        self.assertIs(build_remake.shadow_row(db, 9), db["dungeon"][0])


if __name__ == "__main__":
    unittest.main()
