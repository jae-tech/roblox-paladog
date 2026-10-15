"""T-DATA golden tests (docs/TEST_PLAN.md §4) for the P1 reference/balance pipeline."""
import copy
from decimal import Decimal
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import balance_lib as lib  # noqa: E402

SOURCES = lib.load_sources()
OVERLAY_BYTES = lib.overlay_bytes()
OVERLAY = lib.load_overlay()
RECORDS = lib.import_reference(SOURCES).items
NORMALIZED = {(n["canonicalId"], n["field"]): n for n in lib.normalize(RECORDS)}
BALANCE, PROVENANCE, DIFF = lib.build_balance(list(NORMALIZED.values()), OVERLAY)


def with_lines(alias, edit):
    sources = copy.deepcopy(SOURCES)
    sources[alias]["lines"] = edit(list(sources[alias]["lines"]))
    return sources


def replace_line(prefix, transform):
    def edit(lines):
        index = next(i for i, line in enumerate(lines) if line.startswith(prefix))
        lines[index] = transform(lines[index])
        return lines
    return edit


class TData01LevelReplacesBase(unittest.TestCase):
    def test_level_row_replaces_base_hp(self):
        base = RECORDS["db.allyBase:#1:iMaxHP"]
        self.assertEqual((base["rawValue"], base["status"]), (300, "unused"))
        self.assertEqual(NORMALIZED[("vanguard", "levels[1].maxHp")]["value"], 100)
        self.assertEqual(BALANCE["units"]["vanguard"]["levels"][0]["maxHp"], 100)
        self.assertNotIn(BALANCE["units"]["vanguard"]["levels"][0]["maxHp"], (300, 400))


class TData02NamespaceJoin(unittest.TestCase):
    def test_tables_keep_separate_namespaces(self):
        self.assertEqual(RECORDS["db.allyBase:#1:iMana_"]["dbRow"], 207)
        self.assertEqual(RECORDS["db.enemyBase:#10:iMaxHP"]["dbRow"], 225)
        self.assertNotIn("db.enemyBase:#1:iMaxHP", RECORDS)  # A2 #1 never joins A4 by '#'
        stage_enemy = int(RECORDS["stage.campaign:#0:iEU01"]["rawValue"])
        self.assertEqual(stage_enemy, 1)
        self.assertEqual(lib.stage_enemy_db_row(stage_enemy), RECORDS["db.enemyBase:#10:iMaxHP"]["dbRow"])
        self.assertEqual(lib.stage_enemy_db_row(21), 225)
        self.assertIsNone(lib.stage_enemy_db_row(0))


class TData03LevelAliases(unittest.TestCase):
    def setUp(self):
        self.records = lib.Records()
        lib.import_level_table(self.records, SOURCES["EA"], range(1, 10))
        self.items = self.records.items

    def test_n5_is_turtle_and_n6_is_monkey_by_position(self):
        n5 = self.items["db.unitLevel:N=5;L1:iNewHP"]
        self.assertEqual((n5["rawValue"], n5["dbRow"], n5["note"]), (4000, 454, "logicalUnit=6"))
        self.assertEqual(self.items["db.unitLevel:N=5;L1:iNewAP"]["rawValue"], 0)
        n6 = self.items["db.unitLevel:N=6;L1:iNewHP"]
        self.assertEqual((n6["rawValue"], n6["dbRow"], n6["note"]), (320, 434, "logicalUnit=5"))
        self.assertEqual(self.items["db.unitLevel:N=6;L1:iNewAP"]["rawValue"], 60)

    def test_irregular_rhino_l8_kept(self):
        self.assertEqual(self.items["db.unitLevel:N=7;L8:iNewAP"]["rawValue"], 172)


class TData04Units(unittest.TestCase):
    def test_conversions(self):
        self.assertEqual(lib.px_to_stud(200), 20)
        self.assertEqual(lib.px_to_stud(30), 3)
        self.assertEqual(Decimal(3) / 30, Decimal("0.1"))
        self.assertEqual(lib.TRANSFORMS["frame30-to-ticks-ceil-v1"](3), 2)
        self.assertEqual(lib.tenth_regen_to_milli_per_sec(Decimal("0.2")), 2000)
        self.assertEqual(BALANCE["resources"]["foodRegenMilliPerSec"], 2000)
        self.assertEqual(lib.seconds_to_ticks(Decimal("2.67")), 54)


class TData05StageSemantics(unittest.TestCase):
    def test_reference_stage_rules(self):
        widths = [int(RECORDS[f"stage.campaign:#2:iEU0{n}P"]["rawValue"]) for n in (1, 2, 3)]
        self.assertEqual(widths, [15, 30, 100])
        self.assertEqual(lib.segment_widths(widths), [15, 30, 55])
        self.assertEqual(lib.special_every(int(RECORDS["stage.campaign:#0:iEU05P"]["rawValue"])), 20)
        low, high = (RECORDS[f"stage.campaign:#0:{f}"]["rawValue"] for f in ("iCSp11", "iCSp12"))
        self.assertEqual(lib.interval_range(low, high), (Decimal("5"), Decimal("5.9")))

    def test_mvp_weights_are_new_not_reference(self):
        self.assertEqual(PROVENANCE["s01.choices"]["kind"], "decision")
        self.assertEqual(sum(c["weight"] for c in BALANCE["stages"]["s03"]["choices"]), 100)


class TData06UnusedFields(unittest.TestCase):
    def test_contextual_and_unused_never_reach_runtime(self):
        cases = {"stage.campaign:#0:iCrRwd": 500, "stage.campaign:#0:iCrSec": 203, "db.common:#353:iMvSpd": 2}
        used = {i for p in PROVENANCE.values() for i in p.get("sourceIds", [])}
        for record_id, raw in cases.items():
            self.assertEqual((RECORDS[record_id]["rawValue"], RECORDS[record_id]["status"]), (raw, "unused"))
            self.assertNotIn(record_id, used)
        self.assertEqual(PROVENANCE["s01.winGold"]["kind"], "decision")


class TData07Quarantine(unittest.TestCase):
    def test_u01_conflict_is_quarantined(self):
        self.assertEqual(RECORDS["code.mace:#9:effect"]["status"], "conflicted")
        records = copy.deepcopy(RECORDS)
        records["db.allyBase:#1:iMvSpd"].update(conflictId="U01", status="conflicted")
        with self.assertRaisesRegex(lib.DataError, "quarantined"):
            lib.normalize(records)

    def test_empty_required_cell_fails(self):
        sources = with_lines("EA", replace_line("| 1 | 아군(쥐) 레벨1 |", lambda l: l.replace("| 300 |", "|  |")))
        with self.assertRaisesRegex(lib.DataError, "required value missing"):
            lib.import_reference(sources)

    def test_duplicate_selected_id_fails(self):
        sources = with_lines("EA", replace_line("| 11 | 적군(해골)", lambda l: l.replace("| 11 |", "| 10 |", 1)))
        with self.assertRaisesRegex(lib.DataError, "missing or quarantined"):
            lib.import_reference(sources)
        records = lib.Records()
        records.add(SOURCES["EA"], "x", 1, "ns", "#1", "f", 1, "u")
        with self.assertRaisesRegex(lib.DataError, "duplicate"):
            records.add(SOURCES["EA"], "x", 1, "ns", "#1", "f", 1, "u")

    def test_header_change_fails(self):
        sources = with_lines("EA", replace_line("| # | 이름 | HP | 이동속도 | 전투거리 |",
                                                lambda l: l.replace("| HP |", "| 체력 |", 1)))
        with self.assertRaisesRegex(lib.DataError, "header signature"):
            lib.import_reference(sources)

    def test_column_count_change_fails(self):
        sources = with_lines("EA", replace_line("| 2 | 아군(토끼)", lambda l: l + " 9 |"))
        with self.assertRaisesRegex(lib.DataError, "cells, expected"):
            lib.import_reference(sources)

    def test_source_hash_change_blocks_import(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "tools").mkdir()
            for path in lib.DOCS.values():
                shutil.copyfile(lib.ROOT / path, root / path)
            shutil.copyfile(lib.ROOT / "tools/reference-hashes.json", root / "tools/reference-hashes.json")
            with open(root / lib.DOCS["EA"], "a") as stream:
                stream.write("\n")
            with self.assertRaisesRegex(lib.DataError, "source changed"):
                lib.load_sources(root)

    def test_escaped_pipe_and_empty_cell(self):
        self.assertEqual(lib.split_row("| a | x \\| y |  |"), ["a", "x | y", ""])

    def test_overlay_rules(self):
        cases = [
            lambda o: o["values"].append({"canonicalId": "vanguard", "decisionId": "MVP-NOPE", "fields": {"x": 1}}),
            lambda o: o["values"].append({"canonicalId": "vanguard", "decisionId": "MVP-UNIT-01",
                                          "fields": {"moveSpeed": 9}}),
            lambda o: o["overrides"].append({"canonicalId": "vanguard", "field": "attack.kind", "value": 1,
                                             "decisionId": "MVP-UNIT-01"}),
            lambda o: o["decisions"]["MVP-UNIT-01"].update(reason=""),
        ]
        for mutate in cases:
            overlay = copy.deepcopy(OVERLAY)
            mutate(overlay)
            with self.assertRaises(lib.DataError):
                lib.build_balance(list(NORMALIZED.values()), overlay)

    def test_validator_rejects_bad_balance(self):
        bad = copy.deepcopy(BALANCE)
        bad["stages"]["s02"]["choices"][0]["weight"] = Decimal(60)
        bad["units"]["slinger"]["attack"]["projectileId"] = "missing_bolt"
        bad["units"]["bulwark"]["levels"][0]["purchaseCostGold"] = Decimal(5)
        errors = lib.validate(bad, PROVENANCE, RECORDS)
        self.assertTrue(any("weights" in e for e in errors))
        self.assertTrue(any("projectile" in e for e in errors))
        self.assertTrue(any("free" in e for e in errors))


class TData08Determinism(unittest.TestCase):
    def test_regeneration_is_byte_identical(self):
        first = lib.outputs(SOURCES, OVERLAY_BYTES)
        second = lib.outputs(lib.load_sources(), lib.overlay_bytes())
        self.assertEqual(first, second)

    def test_mvp_counts(self):
        self.assertEqual((len(BALANCE["units"]), len(BALANCE["enemies"]), len(BALANCE["stages"])), (3, 3, 3))
        self.assertEqual(BALANCE["hero"]["id"], "wayfinder")
        self.assertEqual(sum(len(u["levels"]) for u in BALANCE["units"].values()), 15)
        manifest = json.loads(lib.reference_outputs(SOURCES)[2]["data/reference/manifest.json"])
        self.assertEqual(manifest["counts"]["referenceLevelRows"], 60)

    def test_overlay_diff_is_reported(self):
        fields = {(c, f) for c, f, *_ in DIFF}
        self.assertIn(("wayfinder", "hitRadius"), fields)
        self.assertIn(("vanguard", "levels[2].purchaseCostGold"), fields)

    def test_catalog_has_no_server_config(self):
        catalog = lib.public_catalog(BALANCE, OVERLAY)
        text = json.dumps(lib.to_json(catalog))
        for secret in ("maxHp", "attackPower", "killGold", "sourceIds", "dbRow", "paladog"):
            self.assertNotIn(secret, text)


class ReviewRegressions(unittest.TestCase):
    """Holes found in review: schema, ranges, catalog allowlist, duplicates, stage empties."""

    def errors_after(self, mutate):
        bad = copy.deepcopy(BALANCE)
        mutate(bad)
        return lib.validate(bad, PROVENANCE, RECORDS)

    def test_schema_rejects_renamed_and_unknown_fields(self):
        def rename(b):
            b["stages"]["s01"]["timeLimitTick"] = b["stages"]["s01"].pop("timeLimitTicks")
        self.assertTrue(any("missing ['timeLimitTicks']" in e for e in self.errors_after(rename)))
        self.assertTrue(any("unknown ['hp']" in e for e in self.errors_after(
            lambda b: b["enemies"]["brute"]["stats"].update(hp=Decimal(1)))))

    def test_ranges_apply_to_every_definition(self):
        cases = [lambda b: b["enemies"]["scrapper"]["attack"].update(windupTicks=Decimal(0)),
                 lambda b: b["skills"]["pulse"].update(recoveryTicks=Decimal(0)),
                 lambda b: b["projectiles"]["enemy_bolt"].update(ttlTicks=Decimal(0)),
                 lambda b: b["stages"]["s02"].update(timeLimitTicks=Decimal(0)),
                 lambda b: b["hero"].update(baseMaxHp=Decimal(0))]
        for mutate in cases:
            self.assertTrue(any("must be > 0" in e for e in self.errors_after(mutate)))

    def test_catalog_is_allowlisted(self):
        catalog = lib.public_catalog(BALANCE, OVERLAY)
        self.assertEqual(set(catalog["units"]["vanguard"]), {"displayName", "description", "presentationId",
                                                             "foodCost", "summonCooldownTicks", "upgradeCostGold"})
        self.assertEqual(set(catalog["stages"]["s01"]), {"displayName", "description", "prerequisiteId"})
        self.assertEqual(set(catalog["traits"]["focus"]), {"displayName", "description", "maxPoints"})
        self.assertEqual(set(catalog["skills"]["pulse"]), {"displayName", "description", "manaCost", "cooldownTicks"})
        overlay = copy.deepcopy(OVERLAY)
        overlay["catalog"]["units"]["vanguard"]["maxHp"] = 100
        with self.assertRaisesRegex(lib.DataError, "fields must be exactly"):
            lib.public_catalog(BALANCE, overlay)

    def test_trait_text_follows_balance(self):
        self.assertEqual(lib.public_catalog(BALANCE, OVERLAY)["traits"]["provisions"]["description"],
                         "다음 전투부터 식량 재생 +0.25/초")
        changed = copy.deepcopy(BALANCE)
        changed["progression"]["traits"]["vitality"]["heroMaxHpPerPoint"] = Decimal(500)
        self.assertIn("+500", lib.public_catalog(changed, OVERLAY)["traits"]["vitality"]["description"])

    def test_duplicate_overlay_target_fails(self):
        overlay = copy.deepcopy(OVERLAY)
        overlay["overrides"].append({"canonicalId": "wayfinder", "field": "hitRadius", "value": 9,
                                     "decisionId": "MVP-HERO-01"})
        with self.assertRaisesRegex(lib.DataError, "targeted twice"):
            lib.build_balance(list(NORMALIZED.values()), overlay)

    def test_empty_required_stage_cell_fails(self):
        sources = with_lines("EA", replace_line("| 0 | 챕터1-1 (1) |", lambda l: l.replace("| 3000 |", "|  |", 1)))
        with self.assertRaisesRegex(lib.DataError, "required value missing"):
            lib.import_reference(sources)


class DataModelsTableGolden(unittest.TestCase):
    """DATA_MODELS §3 values typed in independently; generation must reproduce them exactly."""

    def test_units(self):
        expected = {"vanguard": (10000, 20, 3, 3.5, 1.2, (3, 7, 66), [100, 105, 110, 115, 120], [20, 21, 22, 23, 24],
                                 [0, 25, 50, 75, 100]),
                    "slinger": (20000, 40, 2.2, 20, 1.2, (5, 7, 100), [100, 105, 110, 115, 120], [40, 42, 44, 46, 48],
                                [0, 50, 100, 150, 200]),
                    "bulwark": (30000, 80, 2.3, 5, 1.6, (7, 9, 40), [1200, 1260, 1320, 1380, 1440],
                                [40, 42, 44, 46, 48], [0, 100, 200, 300, 400])}
        for unit_id, (food, summon, speed, rng, radius, timing, hp, ap, cost) in expected.items():
            u = BALANCE["units"][unit_id]
            a = u["attack"]
            self.assertEqual((u["foodCostMilli"], u["summonCooldownTicks"], u["moveSpeed"], u["attackRange"],
                              u["hitRadius"]), (food, summon, Decimal(str(speed)), Decimal(str(rng)),
                                                Decimal(str(radius))), unit_id)
            self.assertEqual((a["windupTicks"], a["recoveryTicks"], a["cooldownTicks"]), timing, unit_id)
            self.assertEqual([lv["maxHp"] for lv in u["levels"]], hp)
            self.assertEqual([lv["attackPower"] for lv in u["levels"]], ap)
            self.assertEqual([lv["purchaseCostGold"] for lv in u["levels"]], cost)

    def test_enemies(self):
        expected = {"scrapper": (130, 20, 3, 2, 1.2, (5, 5, 30), 18, 12),
                    "spitter": (80, 30, 2, 10, 1.2, (9, 5, 54), 20, 13),
                    "brute": (830, 330, 1.9, 5, 1.5, (6, 8, 40), 45, 19)}
        for enemy_id, (hp, ap, speed, rng, radius, timing, gold, xp) in expected.items():
            e = BALANCE["enemies"][enemy_id]
            s, a = e["stats"], e["attack"]
            self.assertEqual((s["maxHp"], s["attackPower"], s["moveSpeed"], s["attackRange"], s["hitRadius"]),
                             (hp, ap, Decimal(str(speed)), Decimal(str(rng)), Decimal(str(radius))), enemy_id)
            self.assertEqual((a["windupTicks"], a["recoveryTicks"], a["cooldownTicks"]), timing, enemy_id)
            self.assertEqual((e["killGold"], e["killXp"]), (gold, xp), enemy_id)

    def test_hero_resources_skill_projectiles(self):
        h, r, p = BALANCE["hero"], BALANCE["resources"], BALANCE["skills"]["pulse"]
        self.assertEqual((h["baseMaxHp"], h["moveSpeed"], h["hitRadius"], h["supportRadius"],
                          h["supportDamageNumerator"]), (2000, 6, Decimal("1.5"), Decimal("7.5"), 110))
        self.assertEqual((r["foodMaxMilli"], r["manaMaxMilli"], r["foodRegenMilliPerSec"],
                          r["manaRegenMilliPerSec"], r["foodStartMilli"], r["manaStartMilli"]),
                         (40000, 100000, 2000, 2000, 0, 0))
        self.assertEqual((p["damage"], p["manaCostMilli"], p["cooldownTicks"], p["windupTicks"], p["recoveryTicks"]),
                         (100, 10000, 30, 4, 6))
        bolts = {"pulse_bolt": (25, "0.3", 20, 25, 1), "ally_bolt": (60, "0.2", 40, 120, 1),
                 "enemy_bolt": (15, "0.2", 60, 45, 1)}
        for bolt_id, (speed, radius, ttl, distance, pierce) in bolts.items():
            b = BALANCE["projectiles"][bolt_id]
            self.assertEqual((b["speed"], b["radius"], b["ttlTicks"], b["maxDistance"], b["pierce"]),
                             (speed, Decimal(radius), ttl, distance, pierce), bolt_id)

    def test_stages(self):
        common = {"length": Decimal("102.4"), "heroStartX": 10, "allySpawnX": 0, "enemySpawnX": Decimal("102.4"),
                  "coreX": Decimal("90.4"), "coreHitRadius": Decimal("2.5"), "advanceLimitX": Decimal("86.4"),
                  "timeLimitTicks": 12000, "firstWinGold": 100}
        expected = {"s01": (None, 600, (100, 120), (40, 60), 3, {"scrapper": 100}, (100, 60)),
                    "s02": ("s01", 900, (80, 100), (30, 50), 5, {"scrapper": 70, "spitter": 30}, (150, 100)),
                    "s03": ("s02", 1400, (70, 90), (20, 40), 6, {"scrapper": 50, "spitter": 30, "brute": 20},
                            (220, 160))}
        for stage_id, (prereq, core, slow, fast, block, weights, win) in expected.items():
            s = BALANCE["stages"][stage_id]
            for key, value in common.items():
                self.assertEqual(s[key], value, f"{stage_id}.{key}")
            self.assertEqual((s.get("prerequisiteId"), s["coreMaxHp"], (s["slowMinTicks"], s["slowMaxTicks"]),
                              (s["fastMinTicks"], s["fastMaxTicks"]), s["blockCount"],
                              {c["enemyId"]: c["weight"] for c in s["choices"]}, (s["winGold"], s["winXp"])),
                             (prereq, core, slow, fast, block, weights, win), stage_id)


class TAsset(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((lib.ROOT / "data/assets/asset-manifest.json").read_text(encoding="utf-8"))

    def test_repository_passes(self):
        self.assertEqual(lib.asset_audit(BALANCE, self.manifest, *lib.release_and_repo_files()), [])

    def test_failures(self):
        missing = copy.deepcopy(self.manifest)
        missing["entries"].pop()
        self.assertTrue(lib.asset_audit(BALANCE, missing, [], []))
        invented = copy.deepcopy(self.manifest)
        invented["entries"][0]["assetId"] = "rbxassetid://1"
        self.assertTrue(any("assetId set before upload" in e for e in lib.asset_audit(BALANCE, invented, [], [])))
        self.assertTrue(lib.asset_audit(BALANCE, self.manifest, ["src/shared/hero.png"], []))
        self.assertTrue(lib.asset_audit(BALANCE, self.manifest, [], ["reference/game.apk"]))


if __name__ == "__main__":
    unittest.main()
