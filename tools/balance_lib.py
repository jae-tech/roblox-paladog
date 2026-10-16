"""P1 reference import, normalization, balance build and validation. Python stdlib only.

Flow (docs/ASSET_PIPELINE.md §2): 7 research Markdown docs (SHA-pinned) -> located tables/facts ->
data/reference records -> data/normalized values -> overlay decisions -> data/balance + generated Luau.
"""
from decimal import Decimal, ROUND_CEILING
import hashlib
import json
from pathlib import Path
import re
import subprocess

from toolchain import tool

ROOT = Path(__file__).resolve().parents[1]
GENERATOR_VERSION = "p1-balance-1"
SCHEMA_VERSION = 1
BALANCE_VERSION = "mvp-proto-001"
PX_TO_STUD = Decimal("0.1")
TICK_SECONDS = Decimal("0.05")
STYLUA = tool("stylua")

DOCS = {
    "E00": "docs/paladog-00-index.md",
    "E01": "docs/paladog-01-engine-apk.md",
    "E02": "docs/paladog-02-combat-units.md",
    "E03": "docs/paladog-03-hero.md",
    "E04": "docs/paladog-04-resources-stages.md",
    "E05": "docs/paladog-05-growth.md",
    "EA": "docs/paladog-appendix-data.md",
}

# PRD §2 conflict register entries that touch imported values. "resolved" means a code-position rule
# from E02/E05 decides the mapping; unresolved conflicts quarantine every record that carries them.
CONFLICTS = {
    "U01": {"resolved": False, "summary": "E03 §3.1 food mace refills 4+0.3g vs E04 §1-5 fills to max; MVP has no food weapon"},
    "U04": {"resolved": True, "summary": "EA # is table-local: A2 local 1~9, A4 id____ 10~29, A13 N5/N6 purchase-order labels; join by E02 §1.2/§1.4 position rules"},
    "U05": {"resolved": True, "summary": "iCLine, #353, iTgDst, campaign iCrRwd/iCrSec differ from runtime meaning; raw kept, runtime use excluded"},
}


class DataError(ValueError):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def dumps(value):
    return json.dumps(to_json(value), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def to_json(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(str(value))
    if isinstance(value, dict):
        return {k: to_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_json(v) for v in value]
    return value


def dec(value):
    return value if isinstance(value, Decimal) else Decimal(str(value))


def deep_dec(value):
    """Overlay JSON numbers -> Decimal (bools and strings untouched)."""
    if isinstance(value, dict):
        return {k: deep_dec(v) for k, v in value.items()}
    if isinstance(value, list):
        return [deep_dec(v) for v in value]
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return dec(value)
    return value


# ---------------------------------------------------------------- sources & Markdown location

def load_sources(root=ROOT):
    expected = json.loads((root / "tools/reference-hashes.json").read_text(encoding="utf-8"))
    sources = {}
    for alias, path in DOCS.items():
        data = (root / path).read_bytes()
        digest = sha256(data)
        if expected.get(path) != digest:
            raise DataError(f"source changed or unpinned, review before import: {path}")
        sources[alias] = {"alias": alias, "path": path, "sha256": digest, "lines": data.decode("utf-8").splitlines()}
    return sources


HEADING = re.compile(r"^(#+)\s+(.*)$")


def headings(lines, start, end):
    fence = False
    for index in range(start, end):
        if lines[index].startswith("```"):
            fence = not fence
            continue
        match = None if fence else HEADING.match(lines[index])
        if match:
            yield index, len(match.group(1)), match.group(2)


def section(source, path):
    """Resolve a heading path like ("A13.", "유닛") to a unique [start, end) line range."""
    lines = source["lines"]
    start, end = 0, len(lines)
    for prefix in path:
        hits = [(i, level) for i, level, title in headings(lines, start, end) if title.startswith(prefix)]
        if len(hits) != 1:
            raise DataError(f"{source['path']}: section {prefix!r} matched {len(hits)} headings")
        index, level = hits[0]
        start, end = index, next((i for i, lvl, _ in headings(lines, index + 1, end) if lvl <= level), end)
    return start, end


def split_row(line):
    """Split a Markdown table row; `\\|` is a literal pipe inside a cell, empty cells stay empty."""
    body = line.rstrip()
    if not (body.startswith("|") and body.endswith("|")) or len(body) < 2:
        raise DataError("not a table row: " + line)
    cells, buffer, index = [], [], 1
    while index < len(body) - 1:
        char = body[index]
        if char == "\\" and body[index + 1] == "|" and index + 1 < len(body) - 1:
            buffer.append("|")
            index += 2
            continue
        if char == "|":
            cells.append("".join(buffer).strip())
            buffer = []
        else:
            buffer.append(char)
        index += 1
    cells.append("".join(buffer).strip())
    return cells


def table(source, path, header):
    """Rows of the unique table under `path` whose header equals `header` exactly; fails on drift."""
    start, end = section(source, path)
    lines = source["lines"]
    found = [i for i in range(start, end) if lines[i].startswith("|") and split_row(lines[i]) == header]
    if len(found) != 1:
        raise DataError(f"{source['path']} {path}: header signature matched {len(found)} tables")
    index = found[0]
    separator = split_row(lines[index + 1])
    if len(separator) != len(header) or not all(re.fullmatch(r":?-{3,}:?", c) for c in separator):
        raise DataError(f"{source['path']}:{index + 2}: malformed header separator")
    rows = []
    for row_index in range(index + 2, end):
        if not lines[row_index].startswith("|"):
            break
        cells = split_row(lines[row_index])
        if len(cells) != len(header):
            raise DataError(f"{source['path']}:{row_index + 1}: {len(cells)} cells, expected {len(header)}")
        rows.append({"line": row_index + 1, "cells": dict(zip(header, cells))})
    return rows


def fact(source, path, pattern):
    """Unique regex match inside a section; returns (line number, match)."""
    start, end = section(source, path)
    hits = [(i + 1, m) for i in range(start, end) if (m := re.search(pattern, source["lines"][i]))]
    if len(hits) != 1:
        raise DataError(f"{source['path']} {path}: pattern {pattern!r} matched {len(hits)} lines")
    return hits[0]


def number(text, where):
    """Decimal for a numeric cell; empty means missing (None), never zero."""
    if text == "":
        return None
    if not re.fullmatch(r"-?\d+(\.\d+)?", text):
        raise DataError(f"{where}: not a number: {text!r}")
    return Decimal(text)


# ---------------------------------------------------------------- reference records

def status_of(record):
    conflict = record["conflictId"]
    if conflict and not CONFLICTS[conflict]["resolved"]:
        return "conflicted"
    if record["usageStatus"] in ("unused", "contextual"):
        return "unused"
    if record["evidenceLevel"] != "DocumentConfirmed":
        return "inferred"
    return "confirmed"


class Records:
    def __init__(self):
        self.items = {}
        self.quarantine = []

    def add(self, source, section_label, line, namespace, raw_id, field, raw, unit, *, db_row=None,
            usage="used", conflict=None, note=None):
        record_id = f"{namespace}:{raw_id}:{field}"
        if record_id in self.items:
            raise DataError("duplicate reference id: " + record_id)
        record = {
            "id": record_id, "sourceDocument": source["path"], "section": section_label,
            "lineRange": [line, line], "sourceFileHash": source["sha256"], "tableNamespace": namespace,
            "rawIdentifier": raw_id, "dbRow": db_row, "field": field, "rawValue": raw, "rawUnit": unit,
            "evidenceLevel": "DocumentConfirmed", "usageStatus": usage, "conflictId": conflict,
        }
        if note:
            record["note"] = note
        record["status"] = status_of(record)
        self.items[record_id] = record
        return record


UNIT_HEADER = ["#", "이름", "마나(iMana_)", "쿨타임(iCltm_)", "HP", "이동속도", "전투거리(iAtDst)", "맞는범위(iHtDst)",
               "공격대상(iTgDst)", "공격력", "공격딜레이", "스킬거리", "스킬데미지", "스킬발동률", "넉다운확률", "생성라인",
               "공격싱크F", "스킬싱크F"]
UNIT_FIELDS = {"마나(iMana_)": ("iMana_", "count"), "쿨타임(iCltm_)": ("iCltm_", "s"), "HP": ("iMaxHP", "hp"),
               "이동속도": ("iMvSpd", "px/s"), "전투거리(iAtDst)": ("iAtDst", "px"), "맞는범위(iHtDst)": ("iHtDst", "px"),
               "공격대상(iTgDst)": ("iTgDst", "px"), "공격력": ("iAtPwr", "ap"), "공격딜레이": ("fAtDly", "s"),
               "스킬거리": ("iSkDst", "px"), "스킬데미지": ("fSkDmg", "multiplier"), "스킬발동률": ("fSkPct", "percent"),
               "넉다운확률": ("fSkKnd", "percent"), "생성라인": ("iCLine", "line"), "공격싱크F": ("iAt1Fr", "frame30"),
               "스킬싱크F": ("iAt2Fr", "frame30")}
ENEMY_HEADER = ["#", "이름", "HP", "이동속도", "전투거리", "타격범위", "공격대상", "공격력", "공격딜레이", "스킬거리*",
                "스킬데미지*", "스킬발동률", "넉다운확률", "보상골드", "보상EXP", "공격싱크F"]
ENEMY_FIELDS = {"HP": ("iMaxHP", "hp"), "이동속도": ("iMvSpd", "px/s"), "전투거리": ("iAtDst", "px"),
                "타격범위": ("iHtDst", "px"), "공격대상": ("iTgDst", "px"), "공격력": ("iAtPwr", "ap"),
                "공격딜레이": ("fAtDly", "s"), "스킬거리*": ("iSkDst", "px"), "스킬데미지*": ("fSkDmg", "multiplier"),
                "스킬발동률": ("fSkPct", "percent"), "넉다운확률": ("fSkKnd", "percent"), "보상골드": ("iRwGld", "gold"),
                "보상EXP": ("iRwExp", "xp"), "공격싱크F": ("iAt1Fr", "frame30")}
LEVEL_HEADER = ["N", "항목"] + [f"L{n}" for n in range(1, 21)]
LEVEL_ITEMS = {"비용": ("iCost_", "gold"), "HP": ("iNewHP", "hp"), "AP": ("iNewAP", "ap")}
# A13 N is the purchase-order label; code reads level blocks by position (E02 §1.4, E05 B2).
LEVEL_LABEL_TO_LOGICAL = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 5, 7: 7, 8: 8, 9: 9}
STAGE_HEADER = ["#", "스테이지", "전반min", "전반max", "분기점", "후반min", "후반max", "적본진HP", "U1", "P1", "U2", "P2",
                "U3", "P3", "U4", "P4", "U5", "P5", "클리어보상", "클리어시간", "시간2"]
STAGE_FIELDS = {"전반min": ("iCSp11", "s"), "전반max": ("iCSp12", "s"), "분기점": ("iUCnt_", "count"),
                "후반min": ("iCSp21", "s"), "후반max": ("iCSp22", "s"), "적본진HP": ("coreMaxHp", "hp"),
                **{f"U{n}": (f"iEU0{n}", "enemyId") for n in range(1, 6)},
                **{f"P{n}": (f"iEU0{n}P", "segmentOrPeriod") for n in range(1, 6)},
                "클리어보상": ("iCrRwd", "gold"), "클리어시간": ("iCrSec", "s"), "시간2": ("time2", "s")}
UNUSED_FIELDS = {"iTgDst": ("contextual", "U05"), "iCLine": ("contextual", "U05")}
STAGE_CONTEXTUAL = {"iCrRwd", "iCrSec", "time2"}
MACE_HEADER = ["#", "이름", "주효과 (A1+B1·g)", "부효과", "마나", "범위/동작", "근거"]

# MVP allowlist (ASSET_PIPELINE §2.1): importing the whole analysis is not importing the whole game.
ALLY_ROWS = (1, 2, 3)
ENEMY_IDS = (10, 11, 17)
LEVEL_LABELS = (1, 2, 3)
STAGE_ROWS = (0, 1, 2)


def import_unit_table(records, source, label, path, header, fields, select, namespace, db_row_of, usage_of):
    rows = table(source, path, header)
    counts = {}
    for row in rows:
        counts[row["cells"]["#"]] = counts.get(row["cells"]["#"], 0) + 1
    for row in rows:
        raw_id = row["cells"]["#"]
        if counts[raw_id] > 1:
            entry = {"table": namespace, "rawIdentifier": raw_id, "rows": counts[raw_id], "reason": "non-unique id____"}
            if entry not in records.quarantine:
                records.quarantine.append(entry)
            continue
        if int(raw_id) not in select:
            continue
        for column, (field, unit) in fields.items():
            where = f"{source['path']}:{row['line']} {column}"
            value = number(row["cells"][column], where)
            if value is None:
                raise DataError(where + ": required value missing")
            usage, conflict = usage_of(field)
            records.add(source, label, row["line"], namespace, "#" + raw_id, field, value, unit,
                        db_row=db_row_of(int(raw_id)), usage=usage, conflict=conflict)
    for wanted in select:
        if not any(r["rawIdentifier"] == f"#{wanted}" for r in records.items.values() if r["tableNamespace"] == namespace):
            raise DataError(f"{namespace}: selected #{wanted} missing or quarantined")


def ally_usage(field):
    if field in ("iMaxHP", "iAtPwr"):
        return "unused", None  # replaced by level iNewHP/iNewAP in campaign (E02 §1.4)
    return UNUSED_FIELDS.get(field, ("used", None))


def import_level_table(records, source, labels):
    for row in table(source, ("A13.", "유닛"), LEVEL_HEADER):
        label = int(row["cells"]["N"])
        if label not in labels:
            continue
        field, unit = LEVEL_ITEMS[row["cells"]["항목"]]
        logical = LEVEL_LABEL_TO_LOGICAL[label]
        for level in range(1, 21):
            where = f"{source['path']}:{row['line']} L{level}"
            value = number(row["cells"][f"L{level}"], where)
            if value is None:
                raise DataError(where + ": required value missing")
            records.add(source, "A13/유닛", row["line"], "db.unitLevel", f"N={label};L{level}", field, value, unit,
                        db_row=354 + (logical - 1) * 20 + (level - 1), conflict="U04" if label in (5, 6) else None,
                        note=f"logicalUnit={logical}")


def import_reference(sources):
    records = Records()
    ea, e03, e04 = sources["EA"], sources["E03"], sources["E04"]
    import_unit_table(records, ea, "A2", ("A2.",), UNIT_HEADER, UNIT_FIELDS, ALLY_ROWS, "db.allyBase",
                      lambda n: 206 + n, ally_usage)
    import_unit_table(records, ea, "A1", ("A1.",), UNIT_HEADER, UNIT_FIELDS, (0, 255), "db.hero",
                      lambda n: n, lambda f: UNUSED_FIELDS.get(f, ("used", None)))
    import_unit_table(records, ea, "A4", ("A4.",), ENEMY_HEADER, ENEMY_FIELDS, ENEMY_IDS, "db.enemyBase",
                      lambda n: 215 + n, lambda f: UNUSED_FIELDS.get(f, ("used", None)))
    import_level_table(records, ea, LEVEL_LABELS)
    for row in table(ea, ("A14.", "캠페인"), STAGE_HEADER):
        if int(row["cells"]["#"]) not in STAGE_ROWS:
            continue
        for column, (field, unit) in STAGE_FIELDS.items():
            value = number(row["cells"][column], f"{ea['path']}:{row['line']} {column}")
            if value is None:
                if field != "time2":
                    raise DataError(f"{ea['path']}:{row['line']} {column}: required value missing")
                continue  # 시간2 is optional and recorded as absent, not zero
            records.add(ea, "A14/캠페인", row["line"], "stage.campaign", "#" + row["cells"]["#"], field, value, unit,
                        db_row=int(row["cells"]["#"]), usage="contextual" if field in STAGE_CONTEXTUAL else "used",
                        conflict="U05" if field in STAGE_CONTEXTUAL else None)
    start, end = section(ea, ("A6.",))
    for index in range(start, end):
        match = re.match(r"^- \*\*#(\d+) ([^*]+)\*\*: (.*)$", ea["lines"][index])
        if not match or match.group(1) not in ("4", "353"):
            continue
        row = int(match.group(1))
        for field, value in re.findall(r"`(\w+)`=(-?[\d.]+)", match.group(3)):
            records.add(ea, "A6", index + 1, "db.common", "#" + match.group(1), field, Decimal(value), "raw",
                        db_row=row, usage="unused" if row == 353 else "used", conflict="U05" if row == 353 else None)
    for item, field in (("마나 최대", "manaBaseMax"), ("식량 최대", "foodBaseMax")):
        rows = [r for r in table(e04, ("1-3.",), ["항목", "팔라독", "다크독", "근거"]) if r["cells"]["항목"] == item]
        match = re.match(r"`(\d+) \+", rows[0]["cells"]["팔라독"]) if len(rows) == 1 else None
        if not match:
            raise DataError("E04 §1-3: cannot read " + item)
        records.add(e04, "1-3", rows[0]["line"], "code.resource", "paladog", field, Decimal(match.group(1)), "count")
    for field, pattern in (("mapWidth", r"iScrollMax = (\d+)`"), ("heroStartX", r"히어로 시작 x: 일반/W/B (\d+),"),
                           ("coreX", r"적 본진\(BOSS_11\) x = \d+-\d+ = (\d+),"),
                           ("enemySpawnX", r"적 스폰 x = (\d+) \(일반"),
                           ("advanceLimitX", r"아군 전진 한계: 본진 생존 시 x ≤ (\d+),")):
        line, match = fact(e04, ("6. 맵",), pattern)
        records.add(e04, "6", line, "code.map", "normal", field, Decimal(match.group(1)), "px")
    line, match = fact(e03, ("5. 오오라", "5.1"), r"팔라독 `(\d+) \+ (\d+)×오오라파워Lv`")
    records.add(e03, "5.1", line, "code.aura", "paladog", "radiusBase", Decimal(match.group(1)), "px")
    for row in table(e03, ("3.1 팔라독 메이스",), MACE_HEADER):
        name = row["cells"]["이름"]
        if name == "신의주먹":
            match = re.fullmatch(r"데미지 (\d+)\+(\d+)g", row["cells"]["주효과 (A1+B1·g)"])
            if not match:
                raise DataError("E03 §3.1: 신의주먹 damage formula changed")
            records.add(e03, "3.1", row["line"], "code.mace", "#1", "damageA", Decimal(match.group(1)), "damage")
            records.add(e03, "3.1", row["line"], "code.mace", "#1", "damageB", Decimal(match.group(2)), "damage/grade")
        elif name == "음식":
            records.add(e03, "3.1", row["line"], "code.mace", "#9", "effect", row["cells"]["주효과 (A1+B1·g)"], "text",
                        conflict="U01")
    return records


# ---------------------------------------------------------------- normalization

def px_to_stud(v):
    return dec(v) * PX_TO_STUD


def seconds_to_ticks(v):
    return int((dec(v) / TICK_SECONDS).to_integral_value(rounding=ROUND_CEILING))


def count_to_milli(v):
    return int(dec(v) * 1000)


def tenth_regen_to_milli_per_sec(v):
    return int(dec(v) * 10 * 1000)


def identity(v):
    return dec(v)


TRANSFORMS = {
    "px-to-stud-v1": px_to_stud,
    "seconds-to-ticks-ceil-v1": seconds_to_ticks,
    "count-to-milli-v1": count_to_milli,
    "regen-per-tenth-to-milli-per-sec-v1": tenth_regen_to_milli_per_sec,
    "identity-v1": identity,
    "campaign-level-replaces-base-v1": identity,  # value-identity; the transform is choosing the level row
    "frame30-to-ticks-ceil-v1": lambda v: seconds_to_ticks(dec(v) / 30),
}

UNIT_IDS = {"vanguard": 1, "slinger": 2, "bulwark": 3}
ENEMY_CANON = {"scrapper": 10, "spitter": 11, "brute": 17}
STAGE_IDS = ("s01", "s02", "s03")
MVP_LEVELS = 5


def normalization_plan():
    """(canonicalId, field, recordIds, transformId, unit). Stage reference semantics are separate (research only)."""
    plan = []
    for canon, n in UNIT_IDS.items():
        base = f"db.allyBase:#{n}:"
        plan += [(canon, "foodCostMilli", [base + "iMana_"], "count-to-milli-v1", "milli"),
                 (canon, "summonCooldownTicks", [base + "iCltm_"], "seconds-to-ticks-ceil-v1", "tick"),
                 (canon, "moveSpeed", [base + "iMvSpd"], "px-to-stud-v1", "stud/s"),
                 (canon, "attackRange", [base + "iAtDst"], "px-to-stud-v1", "stud"),
                 (canon, "hitRadius", [base + "iHtDst"], "px-to-stud-v1", "stud"),
                 (canon, "attack.cooldownTicks", [base + "fAtDly"], "seconds-to-ticks-ceil-v1", "tick")]
        for level in range(1, MVP_LEVELS + 1):
            level_id = f"db.unitLevel:N={n};L{level}:"
            plan += [(canon, f"levels[{level}].maxHp", [level_id + "iNewHP"], "campaign-level-replaces-base-v1", "hp"),
                     (canon, f"levels[{level}].attackPower", [level_id + "iNewAP"], "campaign-level-replaces-base-v1", "ap"),
                     (canon, f"levels[{level}].referenceCostGold", [level_id + "iCost_"], "identity-v1", "gold")]
    for canon, n in ENEMY_CANON.items():
        base = f"db.enemyBase:#{n}:"
        plan += [(canon, "stats.maxHp", [base + "iMaxHP"], "identity-v1", "hp"),
                 (canon, "stats.attackPower", [base + "iAtPwr"], "identity-v1", "ap"),
                 (canon, "stats.moveSpeed", [base + "iMvSpd"], "px-to-stud-v1", "stud/s"),
                 (canon, "stats.attackRange", [base + "iAtDst"], "px-to-stud-v1", "stud"),
                 (canon, "stats.hitRadius", [base + "iHtDst"], "px-to-stud-v1", "stud"),
                 (canon, "attack.cooldownTicks", [base + "fAtDly"], "seconds-to-ticks-ceil-v1", "tick"),
                 (canon, "killGold", [base + "iRwGld"], "identity-v1", "gold"),
                 (canon, "killXp", [base + "iRwExp"], "identity-v1", "xp")]
    plan += [("wayfinder", "baseMaxHp", ["db.hero:#0:iMaxHP"], "identity-v1", "hp"),
             ("wayfinder", "moveSpeed", ["db.hero:#0:iMvSpd"], "px-to-stud-v1", "stud/s"),
             ("wayfinder", "hitRadius", ["db.hero:#0:iHtDst"], "px-to-stud-v1", "stud"),
             ("wayfinder", "supportRadius", ["code.aura:paladog:radiusBase"], "px-to-stud-v1", "stud"),
             ("pulse", "damage", ["code.mace:#1:damageA", "code.mace:#1:damageB"], "mace-damage-at-grade-1-v1", "damage"),
             ("resources", "foodMaxMilli", ["code.resource:paladog:foodBaseMax"], "count-to-milli-v1", "milli"),
             ("resources", "manaMaxMilli", ["code.resource:paladog:manaBaseMax"], "count-to-milli-v1", "milli"),
             ("resources", "foodRegenMilliPerSec", ["db.common:#4:fBigSc"], "regen-per-tenth-to-milli-per-sec-v1", "milli/s"),
             ("resources", "manaRegenMilliPerSec", ["db.common:#4:fSkPct"], "regen-per-tenth-to-milli-per-sec-v1", "milli/s")]
    for stage in STAGE_IDS:
        plan += [(stage, "length", ["code.map:normal:mapWidth"], "px-to-stud-v1", "stud"),
                 (stage, "heroStartX", ["code.map:normal:heroStartX"], "px-to-stud-v1", "stud"),
                 (stage, "enemySpawnX", ["code.map:normal:enemySpawnX"], "px-to-stud-v1", "stud"),
                 (stage, "coreX", ["code.map:normal:coreX"], "px-to-stud-v1", "stud"),
                 (stage, "advanceLimitX", ["code.map:normal:advanceLimitX"], "px-to-stud-v1", "stud"),
                 (stage, "coreHitRadius", ["db.hero:#255:iHtDst"], "px-to-stud-v1", "stud")]
    return plan


def normalize(records):
    normalized = []
    for canon, field, record_ids, transform, unit in normalization_plan():
        sources = []
        for record_id in record_ids:
            record = records.get(record_id)
            if record is None:
                raise DataError(f"{canon}.{field}: missing reference {record_id}")
            if record["status"] != "confirmed":
                raise DataError(f"{canon}.{field}: {record_id} is {record['status']}; quarantined from production")
            sources.append(record)
        if transform == "mace-damage-at-grade-1-v1":
            value = sources[0]["rawValue"] + sources[1]["rawValue"] * 1
        else:
            value = TRANSFORMS[transform](sources[0]["rawValue"])
        normalized.append({"canonicalId": canon, "field": field, "value": value, "unit": unit,
                           "transformId": transform, "status": "confirmed", "sourceIds": record_ids})
    return normalized


# Research-only stage semantics (E04 §3); never mapped onto s01~s03 (ASSET_PIPELINE §2.3).
def segment_widths(widths):
    """iEU01P~04P are widths added to a running threshold over a 0..99 roll (E04 §3-3), not percents of a sum."""
    effective, threshold = [], 0
    for width in widths:
        upper = threshold + max(0, width)
        effective.append(max(0, min(upper, 100) - min(threshold, 100)))
        threshold = upper
    return effective


def stage_enemy_db_row(enemy_id):
    """Stage U* id -> enemy DB row (E04 §3-3); 0 = empty slot (None); 21~40 reuse row id-20 with a multiplier."""
    if enemy_id == 0:
        return None
    if 1 <= enemy_id <= 20:
        return 224 + enemy_id
    if 21 <= enemy_id <= 40:
        return 224 + enemy_id - 20
    if 101 <= enemy_id <= 110:
        return 244 + enemy_id - 100
    raise DataError(f"unknown stage enemy id {enemy_id}")


def special_every(period):
    return period + 1 if period > 0 else None


def interval_range(minimum, maximum):
    return dec(minimum), dec(maximum) + Decimal("0.9")


# ---------------------------------------------------------------- overlay & balance assembly

PATH_PART = re.compile(r"^(\w+)(?:\[(\d+)\])?$")


def set_path(root, path, value):
    node = root
    parts = path.split(".")
    for i, part in enumerate(parts):
        name, index = PATH_PART.match(part).groups()
        last = i == len(parts) - 1
        if index is None:
            if last:
                node[name] = value
            else:
                node = node.setdefault(name, {})
        else:
            items = node.setdefault(name, [])
            position = int(index) - 1
            while len(items) <= position:
                items.append({})
            if last:
                items[position] = value
            else:
                node = items[position]


def overlay_values(overlay):
    decisions = overlay["decisions"]
    for group in overlay["values"]:
        for field, value in group["fields"].items():
            yield group["canonicalId"], field, value, group["decisionId"], "value"
    for item in overlay["overrides"]:
        yield item["canonicalId"], item["field"], item["value"], item["decisionId"], "override"
    for item in overlay["scaled"]:
        yield item["canonicalId"], item["field"], item, item["decisionId"], "scaled"
    for decision_id, decision in decisions.items():
        if not decision.get("reason") or not (decision.get("approvedBy") is None or isinstance(decision["approvedBy"], str)):
            raise DataError(decision_id + ": needs a reason; approvedBy is null until a real approval exists")


def build_balance(normalized, overlay):
    if overlay.get("balanceVersion") != BALANCE_VERSION:
        raise DataError("overlay balanceVersion mismatch")
    values = {(n["canonicalId"], n["field"]): n for n in normalized}
    final, provenance, diff = {}, {}, []
    for (canon, field), item in values.items():
        final[(canon, field)] = item["value"]
        provenance[f"{canon}.{field}"] = {"kind": "reference", "sourceIds": item["sourceIds"],
                                          "transformId": item["transformId"]}
    adjusted = set()
    for canon, field, value, decision_id, mode in overlay_values(overlay):
        if decision_id not in overlay["decisions"]:
            raise DataError(f"{canon}.{field}: unknown decision {decision_id}")
        key = (canon, field)
        if key in adjusted:
            raise DataError(f"{canon}.{field}: targeted twice by the overlay")
        adjusted.add(key)
        if field.split(".")[-1].startswith("reference"):
            raise DataError(f"{canon}.{field}: reference* names are reserved for research-only normalized fields")
        if mode == "value":
            if key in values or key in final:
                raise DataError(f"{canon}.{field}: overlay value collides with an existing value; use overrides")
            final[key] = deep_dec(value)
            provenance[f"{canon}.{field}"] = {"kind": "decision", "decisionId": decision_id}
        elif mode == "override":
            if key not in values:
                raise DataError(f"{canon}.{field}: override has no reference value")
            final[key] = dec(value)
            provenance[f"{canon}.{field}"] = {"kind": "override", "decisionId": decision_id,
                                              "sourceIds": values[key]["sourceIds"],
                                              "referenceValue": values[key]["value"]}
            diff.append((canon, field, values[key]["value"], dec(value), decision_id))
        else:
            source_key = (canon, value["from"])
            if source_key not in values or key in final:
                raise DataError(f"{canon}.{field}: scaled rule needs reference {value['from']} and a free target")
            scaled = values[source_key]["value"] * Decimal(value["scale"])
            if scaled != scaled.to_integral_value():
                raise DataError(f"{canon}.{field}: scaled value {scaled} is not an integer")
            final[key] = int(scaled)
            provenance[f"{canon}.{field}"] = {"kind": "scaled", "decisionId": decision_id, "scale": value["scale"],
                                              "sourceIds": values[source_key]["sourceIds"]}
            diff.append((canon, field, values[source_key]["value"], final[key], decision_id))
    groups = {**{c: "units" for c in UNIT_IDS}, **{c: "enemies" for c in ENEMY_CANON},
              **{c: "stages" for c in STAGE_IDS}, "wayfinder": "hero", "pulse": "skills",
              "resources": "resources", "progression": "progression", "limits": "limits"}
    balance = {"balanceVersion": BALANCE_VERSION, "configSchemaVersion": SCHEMA_VERSION}
    for (canon, field), value in sorted(final.items()):
        if (canon, field) in values and field.split(".")[-1].startswith("reference"):
            provenance.pop(f"{canon}.{field}")
            continue  # research-only normalized field, not a runtime config
        group = groups.get(canon) or ("projectiles" if canon.endswith("_bolt") else None)
        if group is None:
            raise DataError("unknown canonical id " + canon)
        if group in ("hero", "resources", "progression", "limits"):
            set_path(balance.setdefault(group, {}), field, value)
        else:
            set_path(balance.setdefault(group, {}).setdefault(canon, {"id": canon}), field, value)
    for unit in balance.get("units", {}).values():
        for index, level in enumerate(unit.get("levels", []), 1):
            level["level"] = index
    balance.setdefault("hero", {})["id"] = "wayfinder"
    return balance, provenance, sorted(diff, key=lambda d: (d[0], d[1]))


# ---------------------------------------------------------------- validation

# Closed field sets from DATA_MODELS §2/§5 (+ advanceLimitX from §3.5). value: (required, optional, children)
ATTACK = ({"kind", "windupTicks", "recoveryTicks", "cooldownTicks"}, {"projectileId"}, {})
SCHEMA = {
    "root": ({"balanceVersion", "configSchemaVersion", "units", "enemies", "stages", "hero", "skills", "projectiles",
              "resources", "progression", "limits"}, set(), {}),
    "unit": ({"id", "presentationId", "foodCostMilli", "summonCooldownTicks", "moveSpeed", "attackRange", "hitRadius",
              "attack", "levels"}, set(), {"attack": "attack", "levels": "level"}),
    "attack": ATTACK,
    "level": ({"level", "maxHp", "attackPower", "purchaseCostGold"}, set(), {}),
    "enemy": ({"id", "presentationId", "stats", "attack", "killGold", "killXp"}, set(),
              {"stats": "stats", "attack": "attack"}),
    "stats": ({"maxHp", "attackPower", "moveSpeed", "attackRange", "hitRadius"}, set(), {}),
    "hero": ({"id", "presentationId", "baseMaxHp", "moveSpeed", "hitRadius", "supportRadius", "supportDamageNumerator",
              "weaponSkillId"}, set(), {}),
    "skill": ({"id", "manaCostMilli", "cooldownTicks", "windupTicks", "recoveryTicks", "damage", "projectileId"},
              set(), {}),
    "projectile": ({"id", "speed", "radius", "ttlTicks", "maxDistance", "pierce"}, set(), {}),
    "stage": ({"id", "length", "heroStartX", "allySpawnX", "enemySpawnX", "coreX", "coreMaxHp", "coreHitRadius",
               "advanceLimitX", "slowMinTicks", "slowMaxTicks", "fastMinTicks", "fastMaxTicks", "blockCount",
               "choices", "timeLimitTicks", "winGold", "winXp", "firstWinGold"}, {"prerequisiteId"},
              {"choices": "choice"}),
    "choice": ({"enemyId", "weight"}, set(), {}),
    "resources": ({"foodStartMilli", "manaStartMilli", "foodMaxMilli", "manaMaxMilli", "foodRegenMilliPerSec",
                   "manaRegenMilliPerSec"}, set(), {}),
    "progression": ({"heroLevelCap", "xpCurveBase", "unitMaxLevel", "startGold", "goldMax", "totalXpMax", "traits"},
                    set(), {}),
    "limits": ({"allyCap", "enemyCap", "projectileCap"}, set(), {}),
}
TRAIT_FIELDS = {"vitality": "heroMaxHpPerPoint", "provisions": "foodRegenMilliPerSecPerPoint",
                "focus": "manaRegenMilliPerSecPerPoint"}
POSITIVE = {"windupTicks", "recoveryTicks", "cooldownTicks", "summonCooldownTicks", "ttlTicks", "speed", "radius",
            "maxDistance", "pierce", "timeLimitTicks", "blockCount", "coreMaxHp", "baseMaxHp", "maxHp", "moveSpeed",
            "attackRange", "hitRadius", "coreHitRadius", "supportRadius", "supportDamageNumerator", "damage",
            "manaCostMilli", "foodCostMilli", "foodMaxMilli", "manaMaxMilli", "foodRegenMilliPerSec",
            "manaRegenMilliPerSec", "length", "heroLevelCap", "xpCurveBase", "unitMaxLevel", "goldMax", "totalXpMax",
            "maxPoints", "allyCap", "enemyCap", "projectileCap", "weight", "killGold", "killXp"}


def check_schema(node, kind, path, errors):
    required, optional, children = SCHEMA[kind]
    if not isinstance(node, dict):
        errors.append(f"{path}: expected {kind} object")
        return
    missing, unknown = required - set(node), set(node) - required - optional
    if missing:
        errors.append(f"{path}: missing {sorted(missing)}")
    if unknown:
        errors.append(f"{path}: unknown {sorted(unknown)}")
    for key, child in children.items():
        value = node.get(key)
        for index, item in enumerate(value if isinstance(value, list) else [value] if value is not None else [], 1):
            check_schema(item, child, f"{path}.{key}" + (f"[{index}]" if isinstance(value, list) else ""), errors)


def check_balance_schema(balance, errors):
    check_schema(balance, "root", "balance", errors)
    for group, kind in (("units", "unit"), ("enemies", "enemy"), ("stages", "stage"), ("skills", "skill"),
                        ("projectiles", "projectile")):
        for key, item in balance.get(group, {}).items():
            check_schema(item, kind, f"{group}.{key}", errors)
            if isinstance(item, dict) and item.get("id") != key:
                errors.append(f"{group}.{key}: id must equal its key")
    for group in ("hero", "resources", "progression", "limits"):
        check_schema(balance.get(group), group, group, errors)
    traits = balance.get("progression", {}).get("traits", {})
    if not isinstance(traits, dict) or set(traits) != set(TRAIT_FIELDS):
        errors.append("progression.traits must be exactly " + ", ".join(sorted(TRAIT_FIELDS)))
    else:
        for trait, field in TRAIT_FIELDS.items():
            if set(traits[trait]) != {"maxPoints", field}:
                errors.append(f"progression.traits.{trait}: fields must be maxPoints and {field}")


INTEGER_SUFFIXES = ("Ticks", "Milli", "MilliPerSec", "Gold", "Xp", "maxHp", "MaxHp", "attackPower", "damage",
                    "pierce", "weight", "blockCount", "level", "Numerator", "Cap", "Max", "Points", "PerPoint",
                    "Level", "xpCurveBase")


def walk(node, prefix=""):
    if isinstance(node, dict):
        for key, value in node.items():
            yield from walk(value, f"{prefix}.{key}" if prefix else key)
    elif isinstance(node, list):
        for index, value in enumerate(node, 1):
            yield from walk(value, f"{prefix}[{index}]")
    else:
        yield prefix, node


def validate(balance, provenance, records):
    errors = []

    def need(condition, message):
        if not condition:
            errors.append(message)

    check_balance_schema(balance, errors)
    need(set(balance.get("units", {})) == set(UNIT_IDS), "units must be exactly vanguard/slinger/bulwark")
    need(set(balance.get("enemies", {})) == set(ENEMY_CANON), "enemies must be exactly scrapper/spitter/brute")
    need(set(balance.get("stages", {})) == set(STAGE_IDS), "stages must be exactly s01/s02/s03")
    need(balance.get("hero", {}).get("id") == "wayfinder", "hero must be wayfinder")
    projectiles = balance.get("projectiles", {})
    for path, value in walk(balance):
        last = re.sub(r"\[\d+\]$", "", path.split(".")[-1])
        if isinstance(value, Decimal):
            need(value.is_finite(), path + ": non-finite")
            if last.endswith(INTEGER_SUFFIXES):
                need(value == value.to_integral_value(), f"{path}: must be an integer, got {value}")
            need(value >= 0, f"{path}: negative")
            if last in POSITIVE:
                need(value > 0, f"{path}: must be > 0")
    for unit_id, unit in balance.get("units", {}).items():
        levels = unit.get("levels", [])
        need(len(levels) == MVP_LEVELS, f"{unit_id}: needs {MVP_LEVELS} levels")
        need(levels and levels[0].get("purchaseCostGold") == 0, f"{unit_id}: L1 must be free")
        for a, b in zip(levels, levels[1:]):
            need(b.get("maxHp", 0) >= a.get("maxHp", 0) and b.get("attackPower", 0) >= a.get("attackPower", 0),
                 f"{unit_id}: level stats must not decrease")
            need(b.get("purchaseCostGold", 0) > 0, f"{unit_id}: L{b.get('level')} cost must be positive")
        need(unit.get("attack", {}).get("projectileId") in (None, *projectiles), f"{unit_id}: unknown projectile")
        need(len(levels) == balance.get("progression", {}).get("unitMaxLevel"), f"{unit_id}: levels != unitMaxLevel")
    for owner, attack in [(k, v.get("attack", {})) for k, v in {**balance.get("units", {}),
                                                                 **balance.get("enemies", {})}.items()]:
        need((attack.get("kind") == "Projectile") == ("projectileId" in attack), f"{owner}: kind/projectileId mismatch")
        need(attack.get("kind") in ("Melee", "Projectile"), f"{owner}: unknown attack kind")
    for enemy_id, enemy in balance.get("enemies", {}).items():
        need(enemy.get("attack", {}).get("projectileId") in (None, *projectiles), f"{enemy_id}: unknown projectile")
        need(enemy.get("stats", {}).get("maxHp", 0) >= 1, f"{enemy_id}: maxHp >= 1")
    for stage_id, stage in balance.get("stages", {}).items():
        choices = stage.get("choices", [])
        need(sum(c.get("weight", 0) for c in choices) == 100, f"{stage_id}: weights must sum to 100")
        need(all(c.get("enemyId") in balance.get("enemies", {}) for c in choices), f"{stage_id}: unknown enemy")
        need(stage.get("prerequisiteId") in (None, "", *STAGE_IDS), f"{stage_id}: unknown prerequisite")
        for kind in ("slow", "fast"):
            need(1 <= stage.get(kind + "MinTicks", 0) <= stage.get(kind + "MaxTicks", 0), f"{stage_id}: {kind} range")
        need(stage.get("heroStartX", 0) <= stage.get("advanceLimitX", 0) < stage.get("coreX", 0)
             < stage.get("enemySpawnX", 0) <= stage.get("length", 0), f"{stage_id}: geometry order")
    skill = balance.get("skills", {}).get("pulse", {})
    need(skill.get("projectileId") in projectiles, "pulse: unknown projectile")
    need(balance.get("hero", {}).get("weaponSkillId") in balance.get("skills", {}), "hero: unknown weapon skill")
    level_rows = sum(len(u.get("levels", [])) for u in balance.get("units", {}).values())
    need(level_rows == 15, f"runtime level rows must be 15, got {level_rows}")
    leaves = {path for path, _ in walk(balance)} - {"balanceVersion", "configSchemaVersion", "hero.id"}
    leaves = {p for p in leaves if not re.search(r"(^|\.)id$|levels\[\d+\]\.level$", p)}
    keyed = set()
    for path in leaves:
        group, *rest = path.split(".")
        if group in ("units", "enemies", "stages", "skills", "projectiles"):
            keyed.add(".".join(rest))
        else:
            keyed.add(("wayfinder." if group == "hero" else group + ".") + ".".join(rest))
    def covers(key, leaf):
        return leaf == key or leaf.startswith(key + ".") or leaf.startswith(key + "[")
    uncovered = sorted(leaf for leaf in keyed if not any(covers(key, leaf) for key in provenance))
    orphaned = sorted(key for key in provenance if not any(covers(key, leaf) for leaf in keyed))
    need(not uncovered and not orphaned, f"provenance mismatch: uncovered {uncovered[:5]}, orphaned {orphaned[:5]}")
    for path, entry in provenance.items():
        for source_id in entry.get("sourceIds", []):
            status = records.get(source_id, {}).get("status")
            need(status == "confirmed", f"{path}: source {source_id} status {status}")
    return errors


# ---------------------------------------------------------------- Luau / catalog emission

def luau_value(value, indent):
    pad = "\t" * (indent + 1)
    if isinstance(value, dict):
        body = "".join(f"{pad}{k} = {luau_value(v, indent + 1)},\n" for k, v in sorted(value.items()))
        return "table.freeze({\n" + body + "\t" * indent + "})"
    if isinstance(value, list):
        body = "".join(f"{pad}{luau_value(v, indent + 1)},\n" for v in value)
        return "table.freeze({\n" + body + "\t" * indent + "})"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, Decimal)):
        text = str(dec(value).normalize()) if dec(value) != dec(value).to_integral_value() else str(int(value))
        return text
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    raise DataError("cannot emit " + repr(value))


def luau_module(comment, value):
    source = f"--!strict\n-- GENERATED by tools/build_balance.py ({BALANCE_VERSION}). {comment} Do not edit.\n" \
             f"return {luau_value(value, 0)}\n"
    if not STYLUA.exists():
        raise DataError("pinned StyLua missing; run python3 tools/setup_tools.py")
    result = subprocess.run([str(STYLUA), "--config-path", str(ROOT / "stylua.toml"), "-"], input=source,
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise DataError("StyLua failed: " + result.stderr)
    return result.stdout


CATALOG_TEXT = {"displayName", "description"}


def catalog_text(entry, where, template=False):
    keys = {"displayName", "descriptionTemplate"} if template else CATALOG_TEXT
    if not isinstance(entry, dict) or set(entry) != keys or not all(isinstance(v, str) and v for v in entry.values()):
        raise DataError(f"catalog {where}: fields must be exactly {sorted(keys)} (non-empty strings)")
    return dict(entry)


def trait_amount(trait, value):
    return str(value) if trait == "vitality" else str(to_json(dec(value) / 1000))


def public_catalog(balance, overlay):
    """Client-safe catalog: overlay text (allowlisted keys) + display values derived from balance."""
    catalog = overlay["catalog"]
    if set(catalog) != {"units", "skills", "stages", "traits"}:
        raise DataError("catalog sections must be units/skills/stages/traits")
    units = {}
    for unit_id, unit in balance["units"].items():
        units[unit_id] = {**catalog_text(catalog["units"].get(unit_id), unit_id),
                          "presentationId": unit["presentationId"], "foodCost": int(unit["foodCostMilli"]) // 1000,
                          "summonCooldownTicks": unit["summonCooldownTicks"],
                          "upgradeCostGold": [level["purchaseCostGold"] for level in unit["levels"][1:]]}
    skill = balance["skills"]["pulse"]
    stages = {sid: {**catalog_text(catalog["stages"].get(sid), sid), "prerequisiteId": s.get("prerequisiteId") or ""}
              for sid, s in balance["stages"].items()}
    traits = {}
    for trait, data in balance["progression"]["traits"].items():
        text = catalog_text(catalog["traits"].get(trait), trait, template=True)
        if text["descriptionTemplate"].count("{amount}") != 1:
            raise DataError(f"catalog {trait}: descriptionTemplate needs exactly one {{amount}}")
        traits[trait] = {"displayName": text["displayName"], "maxPoints": data["maxPoints"],
                         "description": text["descriptionTemplate"].replace(
                             "{amount}", trait_amount(trait, data[TRAIT_FIELDS[trait]]))}
    if set(catalog["units"]) != set(units) or set(catalog["stages"]) != set(stages) \
            or set(catalog["traits"]) != set(traits) or set(catalog["skills"]) != {"pulse"}:
        raise DataError("catalog entries must match balance ids exactly")
    return {"units": units, "stages": stages, "traits": traits,
            "skills": {"pulse": {**catalog_text(catalog["skills"]["pulse"], "pulse"),
                                 "manaCost": int(skill["manaCostMilli"]) // 1000,
                                 "cooldownTicks": skill["cooldownTicks"]}}}


def balance_hash(balance):
    return sha256(json.dumps(to_json(balance), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


def reference_outputs(sources):
    """Reference stage only (no overlay, no StyLua): records, normalized values and their files."""
    records = import_reference(sources)
    by_id = records.items
    normalized = normalize(by_id)
    statuses = {}
    for record in by_id.values():
        statuses[record["status"]] = statuses.get(record["status"], 0) + 1
    conflicts = {cid: {**info, "recordIds": sorted(r["id"] for r in by_id.values() if r["conflictId"] == cid)}
                 for cid, info in CONFLICTS.items()}
    records_text = dumps(sorted(by_id.values(), key=lambda r: r["id"]))
    manifest = {
        "generatorVersion": GENERATOR_VERSION, "schemaVersion": SCHEMA_VERSION, "pxToStud": PX_TO_STUD,
        "sources": [{"path": s["path"], "sha256": s["sha256"]} for s in sources.values()],
        "allowlist": {"allyRows": ALLY_ROWS, "enemyIds": ENEMY_IDS, "levelLabels": LEVEL_LABELS, "stageRows": STAGE_ROWS},
        "counts": {"records": len(by_id), "byStatus": statuses, "normalizedValues": len(normalized),
                   "referenceLevelRows": len({r["rawIdentifier"] for r in by_id.values()
                                              if r["tableNamespace"] == "db.unitLevel"}),
                   "quarantined": len(records.quarantine)},
        "quarantine": records.quarantine, "recordsSha256": sha256(records_text.encode()),
    }
    return by_id, normalized, {
        "data/reference/manifest.json": dumps(manifest),
        "data/reference/records.json": records_text,
        "data/reference/conflicts.json": dumps(conflicts),
        "data/normalized/reference.json": dumps(normalized),
    }


def outputs(sources, overlay_bytes):
    """All generated files as {relative path: text}; pure function of the pinned docs and overlay file bytes."""
    by_id, normalized, files = reference_outputs(sources)
    overlay = json.loads(overlay_bytes.decode("utf-8"))
    balance, provenance, diff = build_balance(normalized, overlay)
    errors = validate(balance, provenance, by_id)
    if errors:
        raise DataError("balance validation failed:\n" + "\n".join(errors))
    digest = balance_hash(balance)
    diff_lines = [f"# {BALANCE_VERSION} — reference vs balance", "",
                  "Generated by tools/build_balance.py. Intentional differences from the research reference.", "",
                  "| field | reference | balance | decision |", "|---|---:|---:|---|"]
    diff_lines += [f"| {c}.{f} | {to_json(r)} | {to_json(v)} | {d} |" for c, f, r, v, d in diff]
    decided = sorted({p["decisionId"] for p in provenance.values() if p["kind"] == "decision"})
    diff_lines += ["", "New values without a reference counterpart (decisions): " + ", ".join(decided), ""]
    generated = {
        "Units": ("Allied unit definitions.", balance["units"]),
        "Enemies": ("Enemy definitions.", balance["enemies"]),
        "Hero": ("Hero, weapon skill, projectiles and resources.",
                 {"hero": balance["hero"], "skills": balance["skills"], "projectiles": balance["projectiles"],
                  "resources": balance["resources"]}),
        "Stages": ("Stage definitions.", balance["stages"]),
        "Progression": ("Growth, limits and version metadata.",
                        {"progression": balance["progression"], "limits": balance["limits"],
                         "balanceVersion": BALANCE_VERSION, "balanceHash": digest,
                         "configSchemaVersion": SCHEMA_VERSION}),
    }
    files.update({
        f"data/balance/{BALANCE_VERSION}.json": dumps({**balance, "balanceHash": digest,
                                                        "overlayFileSha256": sha256(overlay_bytes)}),
        f"data/balance/{BALANCE_VERSION}.provenance.json": dumps(provenance),
        f"data/balance/{BALANCE_VERSION}.diff.md": "\n".join(diff_lines),
        "src/shared/PublicCatalog.luau": luau_module("Client-safe catalog only.",
                                                     {**public_catalog(balance, overlay),
                                                      "balanceVersion": BALANCE_VERSION, "balanceHash": digest}),
    })
    for name, (comment, value) in generated.items():
        files[f"src/server/Config/Generated/{name}.luau"] = luau_module(comment, value)
    return files


def overlay_bytes(root=ROOT):
    return (root / f"data/overlay/{BALANCE_VERSION}.json").read_bytes()


def load_overlay(root=ROOT):
    return json.loads(overlay_bytes(root).decode("utf-8"))


REFERENCE_DIRS = ("data/reference", "data/normalized")
BALANCE_DIRS = ("data/balance", "src/server/Config/Generated")


def write_or_check(files, check, managed_dirs=(), root=ROOT):
    """Write files (UTF-8, LF), or with check=True return paths that differ or are orphaned in managed dirs."""
    stale = []
    for path, text in sorted(files.items()):
        target = root / path
        if check:
            if not target.exists() or target.read_bytes() != text.encode("utf-8"):
                stale.append(path)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text.encode("utf-8"))
    for directory in managed_dirs:
        for target in sorted((root / directory).rglob("*")) if (root / directory).exists() else []:
            relative = target.relative_to(root).as_posix()
            if target.is_file() and relative not in files:
                stale.append("orphan: " + relative)
    return stale


# ---------------------------------------------------------------- T-ASSET (ASSET_PIPELINE §3.1, §4)

FORBIDDEN_EXTENSIONS = {".apk", ".dex", ".so", ".ja", ".mae", ".mce", ".mje", ".png", ".jpg", ".jpeg", ".webp",
                        ".tga", ".bmp", ".ogg", ".mp3", ".wav", ".m4a", ".rbxm", ".rbxmx", ".fbx", ".obj"}
ASSET_STATUSES = {"placeholder", "reviewed", "uploaded", "blocked"}


def asset_audit(balance, manifest, release_files, repo_files):
    """Errors for T-ASSET: manifest coverage, no invented ids/approvals, no forbidden or non-Luau release files."""
    errors = []
    used = {item["presentationId"] for group in ("units", "enemies") for item in balance[group].values()}
    used.add(balance["hero"]["presentationId"])
    # P5 code-built core/projectile/ground views declare their IDs in the client definition table.
    view_defs = ROOT / "src/client/Presentation/ViewDefinitions.luau"
    if view_defs.exists():
        text = view_defs.read_text(encoding="utf-8")
        used.update(re.findall(r'presentationId\s*=\s*"([a-z0-9_]+)"', text))
        used.update(re.findall(r'"([a-z0-9_]+_placeholder)"', text))  # remake: literal id lists and view() calls
    entries = {e.get("presentationId"): e for e in manifest.get("entries", [])}
    if len(entries) != len(manifest.get("entries", [])):
        errors.append("asset manifest has duplicate presentationId")
    for missing in sorted(used - set(entries)):
        errors.append("presentation without manifest entry: " + missing)
    for unused in sorted(set(entries) - used):
        errors.append("manifest entry not used at runtime: " + unused)
    for pid, entry in entries.items():
        if entry.get("status") not in ASSET_STATUSES or entry.get("provenanceKind") not in ("Original", "ApprovedExternal"):
            errors.append(f"{pid}: invalid status/provenanceKind")
        if entry.get("status") != "uploaded" and entry.get("assetId") is not None:
            errors.append(f"{pid}: assetId set before upload")
        if entry.get("provenanceKind") == "ApprovedExternal" and not entry.get("approvedBy"):
            errors.append(f"{pid}: external asset without approval")
    for path in release_files:
        if not path.endswith(".luau"):
            errors.append("non-Luau file in release tree: " + path)
    for path in repo_files:
        if Path(path).suffix.lower() in FORBIDDEN_EXTENSIONS:
            errors.append("forbidden asset/binary file: " + path)
    return errors


def release_and_repo_files(root=ROOT):
    project = json.loads((root / "default.project.json").read_text(encoding="utf-8"))

    def paths(node):
        if isinstance(node, dict):
            for key, value in node.items():
                yield from [value] if key == "$path" else paths(value)
    release = sorted(p.relative_to(root).as_posix() for d in paths(project) for p in (root / d).rglob("*") if p.is_file())
    listed = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root,
                            capture_output=True, text=True, check=True, encoding="utf-8").stdout.split()
    return release, listed
