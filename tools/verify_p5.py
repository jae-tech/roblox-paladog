"""P5 input/network/view gate: 0 PASS, 1 FAIL, 2 missing runtime proof."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_p0 import sourcemap_lengths  # noqa: E402
from verify_p2 import allowed_universes  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUAU = ROOT / ".tools/luau-0.742/luau"
SIZES = {(1280, 720), (1920, 1080), (844, 390), (740, 360), (390, 844)}
BUTTONS = ("Left", "Right", "Summon1", "Summon2", "Summon3", "Cast")
GROUPS = {"input": ("tinput-",), "network": ("net-",),
          "view": ("tdevice-", "tview-", "tcamera-", "tasset-")}


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def audit_report(report, environment):
    if (not isinstance(report, dict) or report.get("suite") != "T-P5"
            or report.get("environment") != environment or report.get("status") != "PASS"
            or report.get("failures") != [] or not integer(report.get("seed"))):
        raise ValueError("T-P5 report must PASS in the expected environment")
    cases = report.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("T-P5 requires nonempty raw assertions")
    for case in cases:
        if (not isinstance(case, dict) or not isinstance(case.get("id"), str) or not case["id"]
                or case.get("status") != "PASS" or not isinstance(case.get("expected"), str)
                or not isinstance(case.get("actual"), str) or case["expected"] != case["actual"]
                or not integer(case.get("tick"))):
            raise ValueError("raw T-P5 assertion failed or malformed")
    return len(cases)


def compare_report(raw, environment, cli_report, count):
    if audit_report(raw, environment) != count:
        raise ValueError("raw Studio case count differs from fresh CLI")
    fields = ("id", "expected", "actual", "tick", "status")
    if (raw["seed"] != cli_report["seed"]
            or [[c[k] for k in fields] for c in raw["cases"]]
            != [[c[k] for k in fields] for c in cli_report["cases"]]):
        raise ValueError("Studio seed or ordered assertions differ from fresh CLI")


def audit_pc(group):
    fields = ("beforeX", "afterX", "releaseX", "stoppedX", "castManaBefore", "castManaAfter",
              "foodBefore", "foodAfter", "neutralWithinSeconds", "stationaryXAfterWait")
    if any(not number(group.get(k)) for k in fields):
        raise ValueError("PC measurements must be finite numbers, not booleans")
    if (group["afterX"] <= group["beforeX"] or abs(group["stoppedX"] - group["releaseX"]) > 3.0
            or abs(group["stationaryXAfterWait"] - group["stoppedX"]) > 1e-6
            or group.get("castAccepted") is not True or group.get("guiSummonAccepted") is not True
            or group["castManaBefore"] - group["castManaAfter"] != 10000
            or not 0 <= group["foodAfter"] < group["foodBefore"]
            or group["castManaAfter"] < 0 or group.get("focusNeutral") is not True
            or not 0 <= group["neutralWithinSeconds"] <= 0.5):
        raise ValueError("PC movement/release/cast/GUI/focus proof failed")


def audit_device(group):
    layouts = group.get("layouts")
    shots = group.get("screenshots")
    if (not isinstance(layouts, list) or not isinstance(shots, list) or not shots
            or any(not isinstance(p, str) or not p.strip() for p in shots)):
        raise ValueError("device requires layouts and captured screenshot paths")
    seen = set()
    for layout in layouts:
        if not isinstance(layout, dict):
            raise ValueError("malformed layout")
        width, height = layout.get("width"), layout.get("height")
        if not integer(width, 1) or not integer(height, 1) or (width, height) in seen:
            raise ValueError("invalid or duplicate viewport")
        seen.add((width, height))
        safe = layout.get("safeArea", {})
        if not isinstance(safe, dict):
            raise ValueError("invalid safe area")
        sx, sy, sw, sh = safe.get("x", 0), safe.get("y", 0), safe.get("width"), safe.get("height")
        if (any(not number(v) for v in (sx, sy, sw, sh)) or sx < 0 or sy < 0
                or sw <= 0 or sh <= 0 or sx + sw > width or sy + sh > height
                or layout.get("portraitHint") is not (height > width)):
            raise ValueError("invalid safe area or portrait hint")
        buttons = layout.get("buttons", {})
        if not isinstance(buttons, dict):
            raise ValueError("missing buttons")
        rects = []
        for name in BUTTONS:
            r = buttons.get(name, {})
            if not isinstance(r, dict) or any(not number(r.get(k)) for k in ("x", "y", "width", "height")):
                raise ValueError("invalid button rectangle")
            # UI offsets are relative to the safe content origin, not physical screen origin.
            if (r["width"] < 48 or r["height"] < 48 or r["x"] < 0 or r["y"] < 0
                    or r["x"] + r["width"] > sw or r["y"] + r["height"] > sh):
                raise ValueError("button outside safe content or below 48px")
            for other in rects:
                gap = max(r["x"] - other["x"] - other["width"], other["x"] - r["x"] - r["width"],
                          r["y"] - other["y"] - other["height"], other["y"] - r["y"] - r["height"])
                if gap < 8 - 1e-6:
                    raise ValueError("buttons require 8px separation")
            rects.append(r)
    if not SIZES.issubset(seen):
        raise ValueError("missing required PC/phone/portrait viewport")


def audit_render(group):
    if (not isinstance(group.get("digestBefore"), str) or not group["digestBefore"]
            or group.get("digestAfter") != group["digestBefore"]
            or any(group.get(k) is not True for k in ("missingAssetFallback", "cleanup", "cameraRestored"))):
        raise ValueError("render mutated simulation or lacks fallback/cleanup/camera restoration")


def audit_touch(group):
    if (group.get("source") not in ("PhysicalDevice", "EngineMultiTouchInput")
            or not integer(group.get("independentPointerIds"), 2)
            or group.get("simultaneousMoveAndCast") is not True or group.get("cancelNeutral") is not True):
        raise ValueError("touch PASS requires actual independent multitouch input proof")


def audit_studio(evidence, cli_cases, expected_lengths, cli_report):
    if (not isinstance(evidence, dict) or evidence.get("schema") != "p5-studio-evidence/1"
            or not isinstance(evidence.get("studio_id"), str) or not evidence["studio_id"]):
        raise ValueError("unknown schema or missing studio_id")
    lengths = evidence.get("sourceLengths")
    if (not expected_lengths or not isinstance(lengths, dict) or lengths != expected_lengths
            or any(not integer(v, 1) for v in lengths.values())):
        raise ValueError("Studio evidence does not match current source build")
    if not integer(evidence.get("gameId"), 1) or evidence["gameId"] not in allowed_universes():
        raise ValueError("gameId not in TestPolicy allowlist")
    if not integer(cli_cases, 1) or audit_report(cli_report, "PureLuau") != cli_cases:
        raise ValueError("invalid fresh CLI result")
    summary = evidence.get("studioSuite", {})
    if (not isinstance(summary, dict) or summary.get("suite") != "T-P5"
            or summary.get("environment") != "StudioServer" or summary.get("status") != "PASS"
            or summary.get("failures") != [] or not integer(summary.get("cases"), 1)
            or summary["cases"] != cli_cases):
        raise ValueError("invalid Studio suite summary")
    compare_report(evidence.get("rawStudioSuite"), "StudioServer", cli_report, cli_cases)
    client = evidence.get("rawClientSuite")
    if client is not None:
        compare_report(client, "StudioClient", cli_report, cli_cases)
    checks = [{"id": "studio-suite", "status": "PASS", "cases": cli_cases}]
    for name, audit in (("pcInput", audit_pc), ("device", audit_device), ("render", audit_render), ("touch", audit_touch)):
        group = evidence.get(name)
        if group is None:
            checks.append({"id": name, "status": "BLOCKED", "reason": "Missing runtime evidence"})
            continue
        if not isinstance(group, dict):
            raise ValueError(name + " evidence malformed")
        if group.get("status") == "BLOCKED" and isinstance(group.get("reason"), str) and group["reason"].strip():
            checks.append({"id": name, "status": "BLOCKED", "reason": group["reason"]})
            continue
        if group.get("status") != "PASS":
            raise ValueError(name + " evidence failed or has invalid status")
        audit(group)
        if name != "touch" and client is None:
            checks.append({"id": name, "status": "BLOCKED", "reason": "Requires rawClientSuite"})
        else:
            checks.append({"id": name, "status": "PASS"})
    teardown = evidence.get("teardown", {})
    if not isinstance(teardown, dict) or any(teardown.get(k) is not True for k in ("rigStopped", "playtestEnded")):
        raise ValueError("test rig/playtest not torn down")
    return checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-evidence", type=Path)
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P5" / run_id
    out.mkdir(parents=True)
    checks, report, seed, count = [], None, None, 0

    def write(name, data):
        (out / name).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    try:
        result = subprocess.run([str(LUAU), "tests/cli_p5.luau"], cwd=ROOT, capture_output=True, text=True)
        (out / "unit.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        report = json.loads(result.stdout.splitlines()[0])
        write("unit.json", report)
        count = audit_report(report, "PureLuau")
        seed = report["seed"]
        if result.returncode != 0:
            raise ValueError("CLI exited nonzero")
        checks.append({"id": "unit", "status": "PASS", "cases": count})
        for name, prefixes in GROUPS.items():
            cases = [c for c in report["cases"] if c["id"].startswith(prefixes)]
            status = "PASS" if cases else "FAIL"
            write(name + ".json", {"suite": "T-P5", "seed": seed, "status": status, "cases": cases})
            checks.append({"id": name, "status": status, "cases": len(cases)})
    except (OSError, ValueError, IndexError, KeyError, TypeError, AttributeError) as error:
        checks.append({"id": "unit", "status": "FAIL", "reason": str(error)})
        for name in ("unit", *GROUPS):
            if not (out / (name + ".json")).exists():
                write(name + ".json", {"suite": "T-P5", "status": "FAIL", "reason": str(error)})
    try:
        build = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True)
        balance = json.loads((ROOT / "data/balance/mvp-proto-001.json").read_text(encoding="utf-8"))
        source_hash = hashlib.sha256()
        for folder in ("src", "tests", "test-support", "test-support-client"):
            for path in sorted((ROOT / folder).rglob("*.luau")):
                source_hash.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes())
        write("environment.json", {"runId": run_id, "buildId": build.stdout.strip(), "sourceHash": source_hash.hexdigest(),
                                   "balanceHash": balance["balanceHash"], "seed": seed, "environment": "PureLuau"})
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        write("environment.json", {"status": "FAIL", "reason": str(error)})
        checks.append({"id": "environment", "status": "FAIL", "reason": str(error)})
    if args.studio_evidence is None:
        checks.append({"id": "studio", "status": "BLOCKED", "reason": "Requires --studio-evidence"})
    else:
        try:
            evidence = json.loads(args.studio_evidence.read_text(encoding="utf-8"))
            sourcemap = out / "test.sourcemap.json"
            result = subprocess.run(["rojo", "sourcemap", "test.project.json", "-o", str(sourcemap)],
                                    cwd=ROOT, capture_output=True, text=True, check=True)
            (out / "sourcemap.log").write_text(result.stdout + result.stderr, encoding="utf-8")
            checks.extend(audit_studio(evidence, count, sourcemap_lengths(json.loads(sourcemap.read_text())), report))
            shutil.copyfile(args.studio_evidence, out / "studio.json")
        except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
            checks.append({"id": "studio", "status": "FAIL", "reason": str(error)})
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    write("report.json", {"runId": run_id, "suite": "T-P5", "status": status, "cases": checks})
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
