"""Remake data (docs/REMAKE_PLAN.md R0): research appendix tables -> data/remake/db.json + generated Luau.

Research names stay in data/remake/db.json only; generated Luau carries ids and the original names from
data/remake/design.json (ASSET_PIPELINE §114: no research character names in the release tree).
"""
import argparse
from decimal import Decimal
import json
import re
import subprocess
import sys

from balance_lib import ROOT, STYLUA, DataError, load_sources, luau_value, number, section, table, to_json, \
    write_or_check

GENERATOR = "remake-db-1"
OUT_JSON = "data/remake/db.json"
OUT_SERVER = "src/server/Config/Remake/Db.luau"
OUT_CATALOG = "src/shared/RemakeCatalog.luau"
MANAGED = ("src/server/Config/Remake",)

CHAR = ["#", "이름", "마나(iMana_)", "쿨타임(iCltm_)", "HP", "이동속도", "전투거리(iAtDst)", "맞는범위(iHtDst)",
        "공격대상(iTgDst)", "공격력", "공격딜레이", "스킬거리", "스킬데미지", "스킬발동률", "넉다운확률", "생성라인",
        "공격싱크F", "스킬싱크F"]
CHAR_KEYS = ["cost", "cooldown", "hp", "moveSpeed", "attackDist", "hitDist", "targetDist", "attackPower",
             "attackDelay", "skillDist", "skillDamage", "skillPercent", "knockPercent", "createLine", "attackFrame",
             "skillFrame"]
TOTEM = CHAR + ["생성위치(fBigSc)", "자동소멸초(fBigSt)"]
TOTEM_KEYS = CHAR_KEYS + ["spawnOffset", "lifetime"]
ENEMY = ["#", "이름", "HP", "이동속도", "전투거리", "타격범위", "공격대상", "공격력", "공격딜레이", "스킬거리*",
         "스킬데미지*", "스킬발동률", "넉다운확률", "보상골드", "보상EXP", "공격싱크F"]
ENEMY_KEYS = ["hp", "moveSpeed", "attackDist", "hitDist", "targetDist", "attackPower", "attackDelay", "skillDist",
              "skillDamage", "skillPercent", "knockPercent", "rewardGold", "rewardExp", "attackFrame"]
PROJ = ["#", "이름", "id", "오프셋X", "오프셋Y", "마나", "iMaxHP", "속도", "범위", "공격력", "스킬데미지", "발동률",
        "싱크F", "스테이지별계산"]
PROJ_KEYS = ["objectId", "offsetX", "offsetY", "mana", "pierce", "speed", "range", "attackPower", "skillDamage",
             "percent", "frame", "perStage"]
WEAPON = ["#", "이름", "값1 A", "값1 B", "값2 A", "값2 B", "값3 A", "값3 B", "값4 A", "값4 B"]
WEAPON_KEYS = ["a1", "b1", "a2", "b2", "manaA", "manaB", "priceBase", "priceMulti"]
GEAR = ["#", "이름", "효과 A(기본)", "효과 B(등급당)", "값4 A", "값4 B"]
GEAR_KEYS = ["a", "b", "priceBase", "priceMulti"]
LEVEL = ["N", "항목"] + [f"L{i}" for i in range(1, 21)]
STAGE_TAIL = ["전반min", "전반max", "분기점", "후반min", "후반max", "적본진HP", "U1", "P1", "U2", "P2", "U3", "P3",
              "U4", "P4", "U5", "P5", "클리어보상", "클리어시간", "시간2"]
STAGE_KEYS = ["s11", "s12", "unitCount", "s21", "s22", "castleHp", "u1", "p1", "u2", "p2", "u3", "p3", "u4", "p4",
              "u5", "p5", "clearReward", "clearSec", "clearSec2"]
STAGE = ["#", "스테이지"] + STAGE_TAIL
STAGE_VER = ["#", "fVer__", "스테이지"] + STAGE_TAIL
STAGE_HORSE = ["#", "목마공격력", "스테이지"] + STAGE_TAIL
# E04 §0-1: darkdog-only replacement stages use rows 220..240 in this order.
DARK_REPLACED = [1, 2, 4, 5, 7, 8, 10, 11, 36, 65, 67, 72, 82, 84, 108, 113, 115, 116, 118, 119, 120]
LEVEL_ROWS = {"비용": "cost", "HP": "hp", "AP": "ap"}


def values(row, header, keys, where, skip=2):
    cells = row["cells"]
    out = {}
    for name, key in zip(header[skip:], keys):
        value = number(cells[name], f"{where}:{row['line']}:{name}")
        if value is not None:
            out[key] = value
    return out


def r_key(row):
    return "#" if "#" in row["cells"] else "N"


def by_number(rows, where):
    """{# -> row}; duplicate # values are kept as a list in source order (A4 shares 99879)."""
    out = {}
    for row in rows:
        key = int(number(row["cells"][r_key(row)], where))
        out.setdefault(key, []).append(row)
    return out


def a6_records(source):
    start, end = section(source, ("A6.",))
    out = {}
    for line in source["lines"][start:end]:
        match = re.match(r"- \*\*#(\d+) [^*]+\*\*: (.*)$", line)
        if match:
            out[int(match.group(1))] = {k: Decimal(v) for k, v in re.findall(r"`(\w+)`=(-?[\d.]+)", match.group(2))}
    return out


def a1_multipliers(source):
    start, end = section(source, ("A1.",))
    text = "\n".join(source["lines"][start:end])
    found = dict(re.findall(r"`(fBigSc|fBigSt|fZmESt)`=([\d.]+)", text))
    if set(found) != {"fBigSc", "fBigSt", "fZmESt"}:
        raise DataError("A1 multipliers missing: " + repr(found))
    return {"bigScale": Decimal(found["fBigSc"]), "bigStat": Decimal(found["fBigSt"]),
            "enhancedStat": Decimal(found["fZmESt"])}


def parse(sources):
    ea = sources["EA"]
    db = {"sourceSha256": ea["sha256"], "generator": GENERATOR}

    a1 = by_number(table(ea, ("A1.",), CHAR), "A1")
    special = {0: "lightHero", 1: "wagon", 2: "shadowHero", 255: "castle", 256: "woodenHorse"}
    db["specials"] = {name: dict(values(a1[row][0], CHAR, CHAR_KEYS, "A1"), row=row) for row, name in special.items()}
    db["multipliers"] = a1_multipliers(ea)
    common = a6_records(ea)
    db["regen"] = {"light": common[4], "shadow": common[5]}
    db["shadowSkillValues"] = common[6]

    a2 = by_number(table(ea, ("A2.",), CHAR), "A2")
    db["units"] = [dict(values(a2[n][0], CHAR, CHAR_KEYS, "A2"), row=206 + n, research=a2[n][0]["cells"]["이름"])
                   for n in range(1, 10)]
    a3 = by_number(table(ea, ("A3.",), TOTEM), "A3")
    db["totems"] = [dict(values(a3[215 + n][0], TOTEM, TOTEM_KEYS, "A3"), row=215 + n,
                         research=a3[215 + n][0]["cells"]["이름"]) for n in range(1, 10)]

    a4 = by_number(table(ea, ("A4.",), ENEMY), "A4")
    db["enemies"] = [dict(values(a4[9 + n][0], ENEMY, ENEMY_KEYS, "A4"), row=224 + n,
                          research=a4[9 + n][0]["cells"]["이름"]) for n in range(1, 21)]
    db["bosses"] = [dict(values(a4[29 + n][0], ENEMY, ENEMY_KEYS, "A4"), row=244 + n,
                         research=a4[29 + n][0]["cells"]["이름"]) for n in range(1, 11)]
    shadow, dummy, flag = a4[99879]
    db["shadowBoss"] = dict(values(shadow, ENEMY, ENEMY_KEYS, "A4"), row=257, research=shadow["cells"]["이름"])

    a5 = by_number(table(ea, ("A5.",), PROJ), "A5")
    db["objects"] = {f"r{row}": dict(values(a5[row][0], PROJ, PROJ_KEYS, "A5"), research=a5[row][0]["cells"]["이름"])
                     for row in sorted(a5)}

    def gear(path, header, keys, first, count):
        rows = by_number(table(ea, path, header), str(path))
        return [dict(values(rows[first + i][0], header, keys, str(path)), row=first + i,
                     research=rows[first + i][0]["cells"]["이름"]) for i in range(count)]

    db["maces"] = gear(("A7.",), WEAPON, WEAPON_KEYS, 7, 11)
    db["swords"] = gear(("A8.",), WEAPON + ["사거리"], WEAPON_KEYS + ["range"], 47, 11)
    db["rings"] = gear(("A9.",), GEAR, GEAR_KEYS, 27, 10)
    db["amulets"] = gear(("A10.",), GEAR, GEAR_KEYS, 67, 10)
    db["helmets"] = gear(("A11.",), GEAR, GEAR_KEYS, 87, 10)
    db["armors"] = gear(("A11.",), GEAR, GEAR_KEYS, 107, 5)
    db["horses"] = gear(("A11.",), GEAR, GEAR_KEYS, 127, 5)
    db["darkHelmets"] = gear(("A12.",), GEAR, GEAR_KEYS, 147, 10)
    db["darkArmors"] = gear(("A12.",), GEAR, GEAR_KEYS, 167, 5)
    db["darkFeet"] = gear(("A12.",), GEAR, GEAR_KEYS, 187, 5)

    def levels(label, swap):
        rows = table(ea, ("A13.", label), LEVEL)
        out = {}
        for row in rows:
            n = int(number(row["cells"]["N"], "A13"))
            field = LEVEL_ROWS[row["cells"]["항목"]]
            out.setdefault(n, {})[field] = [number(row["cells"][f"L{i}"], f"A13:{row['line']}") for i in range(1, 21)]
        # D-UNIT-56: A13 unit labels N5/N6 are purchase order; code position 5 = monkey, 6 = turtle.
        order = [1, 2, 3, 4, 6, 5, 7, 8, 9] if swap else list(range(1, 10))
        return [out[n] for n in order]

    for unit, level in zip(db["units"], levels("유닛", True)):
        unit["levels"] = level
    for totem, level in zip(db["totems"], levels("토템", False)):
        totem["levels"] = level

    def stages(path, header, first, count, ver_key=None):
        rows = by_number(table(ea, path, header), str(path))
        skip = 3 if ver_key else 2
        out = []
        for row in range(first, first + count):
            entry = dict(values(rows[row][0], header, STAGE_KEYS, str(path), skip), row=row,
                         research=rows[row][0]["cells"]["스테이지"])
            if ver_key:
                ver = number(rows[row][0]["cells"][header[1]], str(path))
                if ver is not None:
                    entry[ver_key] = ver
            out.append(entry)
        return out

    db["campaign"] = stages(("A14.", "캠페인"), STAGE, 0, 120)
    db["destinyAux"] = stages(("A14.", "D 스테이지"), STAGE, 120, 20)
    db["survival"] = stages(("A14.", "서바이벌"), STAGE_VER, 140, 50, "ver")
    db["darkWagon"] = stages(("A14.", "목마"), STAGE_HORSE, 190, 10, "horseAttack")
    special_rows = stages(("A14.", "던전"), STAGE_VER, 200, 41, "ver")
    db["dungeon"], db["jump"] = special_rows[:10], special_rows[10:20]
    db["darkReplaced"] = [dict(r, stage=s) for s, r in zip(DARK_REPLACED, special_rows[20:])]
    return db


def golden(db):
    """Spot values straight from the appendix; a parse drift must fail loudly."""
    checks = [
        (db["units"][4]["levels"]["hp"][0], 320, "unit5 monkey L1 HP (D-UNIT-56)"),
        (db["units"][5]["levels"]["hp"][0], 4000, "unit6 turtle L1 HP"),
        (db["units"][4]["levels"]["cost"][0], 70000, "monkey unlock cost"),
        (db["units"][6]["levels"]["ap"][7], 172, "rhino L8 AP anomaly kept (E05 B5)"),
        (db["units"][0]["attackDelay"], Decimal("3.3"), "mouse fAtDly"),
        (db["totems"][4]["levels"]["ap"][0], 600, "totem5 spike AP"),
        (db["enemies"][0]["hp"], 130, "enemy1 HP"),
        (db["enemies"][16]["attackFrame"], 72, "bomber sync frame"),
        (db["bosses"][9]["hp"], 1000000, "boss10 HP"),
        (db["shadowBoss"]["skillDist"], 40, "shadow boss transform %"),
        (db["specials"]["castle"]["hp"], 3000, "castle HP"),
        (db["specials"]["castle"]["hitDist"], 25, "castle hit radius"),
        (db["multipliers"]["bigStat"], Decimal("3.3"), "giant stat"),
        (db["regen"]["light"]["fSkDmg"], 60, "light hero HP regen per skill"),
        (db["shadowSkillValues"]["iMaxHP"], 1500, "shadow hero HP per level"),
        (db["maces"][6]["a1"], 250, "meteor damage A"),
        (db["maces"][10]["manaA"], 1000, "gold mace cost"),
        (db["swords"][9]["range"], 180, "thunder hammer range"),
        (db["horses"][1]["a"], Decimal("0.9"), "guard horse base"),
        (db["objects"]["r302"]["attackPower"], 2000, "kiss poison"),
        (db["campaign"][0]["castleHp"], 3000, "1-1 castle"),
        (db["campaign"][0]["u5"], 21, "1-1 special"),
        (db["campaign"][119]["castleHp"], 1600000, "5-24B castle"),
        (db["destinyAux"][0]["u1"], 6, "1-3D mace slot 1"),
        (db["survival"][0]["ver"], Decimal("0.1"), "survival scale mul"),
        (db["survival"][2]["ver"], Decimal("0.2"), "survival unit upgrade mul"),
        (db["darkWagon"][9]["horseAttack"], 7000, "5-18W horse attack"),
        (db["jump"][0]["s11"], 280, "1-3J boar speed"),
        (db["darkReplaced"][20]["stage"], 120, "darkdog 120 replacement"),
        (db["darkReplaced"][20]["castleHp"], 500000, "darkdog 5-24B castle"),
    ]
    errors = [f"{label}: {actual} != {expected}" for actual, expected, label in checks if actual != expected]
    counts = {"units": 9, "totems": 9, "enemies": 20, "bosses": 10, "maces": 11, "swords": 11, "rings": 10,
              "amulets": 10, "campaign": 120, "destinyAux": 20, "survival": 50, "darkWagon": 10, "dungeon": 10,
              "jump": 10, "darkReplaced": 21}
    errors += [f"{k}: {len(db[k])} rows != {n}" for k, n in counts.items() if len(db[k]) != n]
    for unit in db["units"] + db["totems"]:
        if any(len(unit["levels"][f]) != 20 or None in unit["levels"][f] for f in ("cost", "hp", "ap")):
            errors.append(f"row {unit['row']}: incomplete level table")
    if errors:
        raise DataError("golden: " + "; ".join(errors))


def strip(value):
    """Drop research names and None for the release tree. Records in one list share one key set (missing
    numeric cells become 0) so Luau infers a single element type for the array."""
    if isinstance(value, dict):
        return {k: strip(v) for k, v in value.items() if k != "research" and v is not None}
    if isinstance(value, list):
        items = [strip(v) for v in value]
        if items and all(isinstance(v, dict) for v in items):
            keys = set().union(*items)
            for item in items:
                for key in keys - set(item):
                    item[key] = 0
        return items
    return value


def spread(total, count, first):
    """count amounts rising linearly from `first`, rounded to 10, summing exactly to `total`."""
    span = count * (count - 1) // 2
    slope = (total - count * first) / span if span else 0
    amounts = [int(round((first + slope * i) / 10)) * 10 for i in range(count)]
    amounts[-1] += total - sum(amounts)
    return amounts


QUEST_MODES = {0: "Boss", 3: "Destiny", 6: "Wagon", 9: "Tower"}


def quests(db, design):
    """D-QUEST-01/02: three quests per light-hero stage. quest.xml is not in the research docs, so the
    shapes follow E05 B10 (17 types, totals, item stages) and the 1-1 example (main 300, sub1 5:20, sub2 400)."""
    rules = design["questRules"]
    totals = rules["rewardTotals"]
    item_stages = set(rules["itemStages"])
    main_gold = spread(totals["main"], 120, 300)
    sub1_gold = spread(totals["sub1"], 120, 200)
    gold_stages = [s for s in range(1, 121) if (s - 1) % 24 + 1 not in item_stages]
    sub2_gold = dict(zip(gold_stages, spread(totals["sub2"], len(gold_stages), 400)))
    cycle = rules["sub2Cycle"]
    out, item_index = [], 0
    for s in range(1, 121):
        row = db["campaign"][s - 1]
        chapter = (s - 1) // 24 + 1
        mode = QUEST_MODES.get(s % 12, "Normal")
        main = {"Normal": {"type": 1}, "Boss": {"type": 9, "a": s // 12}, "Destiny": {"type": 3},
                "Wagon": {"type": 5}, "Tower": {"type": 7}}[mode]
        limit = int((row["clearSec"] + 120) // 10 * 10)  # 1-1: 203 + 120 -> 5:20 (D-QUEST-02)
        sub1 = {"type": 10, "a": limit // 60, "b": limit % 60}
        if mode == "Tower":
            sub2 = {"type": 8, "a": 5}
        elif mode == "Wagon":
            sub2 = {"type": 6, "a": 50}
        elif mode == "Destiny":
            sub2 = {"type": 4, "a": 3}
        else:
            kind = cycle[(s - 1) % len(cycle)]
            sub2 = {"type": kind}
            if kind == 14:
                sub2.update(a=1 + (chapter - 1) * 2, b=10)
            elif kind == 2:
                sub2.update(a=50)
            elif kind == 11:
                sub2.update(a=100 * (1 + (s - 1) // 6))
            elif kind == 12:
                sub2.update(a=3 + (chapter - 1) * 2)
            elif kind == 15:
                sub2.update(a=5)
            elif kind == 17:
                sub2.update(a=1, b=3)
            elif kind in (13, 16):
                sub2.update(a=1)
            elif kind == 8:
                sub2.update(a=5)
        main["gold"], sub1["gold"] = main_gold[s - 1], sub1_gold[s - 1]
        if (s - 1) % 24 + 1 in item_stages:
            local = (s - 1) % 24 + 1
            sub2["gold"] = 0
            sub2["item"] = {"category": "mace" if item_index % 2 == 0 else "ring",
                            "num": (item_index // 2) % 10 + 1,
                            "grade": chapter * 2 - 1 + (1 if local >= 15 else 0)}
            item_index += 1
        else:
            sub2["gold"] = sub2_gold[s]
        for quest in (main, sub1, sub2):  # one key set so Luau infers a single quest type
            quest.setdefault("a", 0)
            quest.setdefault("b", 0)
            quest.setdefault("item", {"category": "", "num": 0, "grade": 0})
        out.append([main, sub1, sub2])
    if item_index != 30:
        raise DataError(f"quest items: {item_index} != 30")
    sums = [sum(q[i]["gold"] for q in out) for i in range(3)]
    if sums != [totals["main"], totals["sub1"], totals["sub2"]]:
        raise DataError(f"quest totals {sums}")
    return out


def catalog(db, design):
    names = design["names"]
    if len(names["units"]) != 9 or len(names["enemies"]) != 20 or len(names["bosses"]) != 10:
        raise DataError("design names incomplete")

    def stage_meta(index):
        s = index + 1
        mode = {0: "Boss", 3: "Destiny", 6: "Wagon", 9: "Tower"}.get(s % 12, "Normal")
        return {"stage": s, "chapter": (s - 1) // 24 + 1, "number": (s - 1) % 24 + 1, "mode": mode}

    return {
        "chapters": design["chapters"],
        "heroNames": names["hero"],
        "units": [{"name": names["units"][i], "cost": u["cost"], "cooldown": u["cooldown"],
                   "levels": u["levels"]} for i, u in enumerate(db["units"])],
        "totems": [{"name": names["totems"][i], "cost": t["cost"], "cooldown": t["cooldown"],
                    "levels": t["levels"]} for i, t in enumerate(db["totems"])],
        "enemies": names["enemies"],
        "enhancedPrefix": names["enhancedPrefix"],
        "bosses": names["bosses"],
        "maces": [{"name": names["maces"][i], "manaA": m["manaA"], "priceBase": m["priceBase"],
                   "priceMulti": m["priceMulti"]} for i, m in enumerate(db["maces"])],
        "swords": [{"name": names["swords"][i], "manaA": m["manaA"], "priceBase": m["priceBase"],
                    "priceMulti": m["priceMulti"]} for i, m in enumerate(db["swords"])],
        "gearNames": {k: names[k] for k in ("rings", "amulets", "helmets", "armors", "horses", "darkHelmets",
                                            "darkArmors", "darkFeet")},
        "skillNames": {"light": names["lightSkills"], "shadow": names["shadowSkills"]},
        "stages": [dict(stage_meta(i), quests=q) for i, q in enumerate(quests(db, design))],
    }


def luau(comment, value):
    source = f"--!strict\n-- GENERATED by tools/build_remake.py ({GENERATOR}). {comment} Do not edit.\n" \
             f"return {luau_value(value, 0)}\n"
    result = subprocess.run([str(STYLUA), "--config-path", str(ROOT / "stylua.toml"), "-"], input=source,
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise DataError("StyLua failed: " + result.stderr)
    return result.stdout


def outputs(sources, design):
    db = parse(sources)
    golden(db)
    return {
        OUT_JSON: json.dumps(to_json(db), ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        OUT_SERVER: luau("Remake game data (research appendix A1-A14, research names stripped).",
                         strip(dict(db, quests=quests(db, design)))),
        OUT_CATALOG: luau("Remake public catalog: original names, costs, prices, stage list.",
                          strip(catalog(db, design))),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if committed outputs differ from regeneration")
    args = parser.parse_args()
    try:
        design = json.loads((ROOT / "data/remake/design.json").read_text(encoding="utf-8"))
        files = outputs(load_sources(), design)
    except (DataError, OSError, KeyError, IndexError) as error:
        print("FAIL:", error, file=sys.stderr)
        return 1
    stale = write_or_check(files, args.check, MANAGED)
    for path in stale:
        print("STALE:", path, file=sys.stderr)
    print(("checked " if args.check else "wrote ") + str(len(files)) + " remake files")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
