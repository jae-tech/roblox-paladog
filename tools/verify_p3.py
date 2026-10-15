"""P3 evidence gate (T-RESOURCE/T-COMBAT/T-HERO-01). Exit 0 PASS, 1 FAIL, 2 BLOCKED (no Studio evidence)."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_p0 import sourcemap_lengths  # noqa: E402
from verify_p2 import allowed_universes  # noqa: E402
from toolchain import tool  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUAU = tool("luau")
PHASES = ["regen", "commands", "spawn", "move", "support", "target", "attack", "damage", "outcome", "cleanup"]


def audit_studio(evidence, cli_cases, expected_lengths):
    """Validate MCP-captured Studio evidence for the headless simulation; raises ValueError."""
    if evidence.get("schema") != "p3-studio-evidence/1" or not evidence.get("studio_id"):
        raise ValueError("unknown evidence schema or missing studio_id")
    if evidence.get("sourceLengths") != expected_lengths:
        raise ValueError("Studio evidence was captured from a different build than the current sources")
    if evidence["gameId"] == 0 or evidence["gameId"] not in allowed_universes():
        raise ValueError("gameId not in TestPolicy allowlist")
    suite = evidence["studioSuite"]
    if suite["status"] != "PASS" or suite["failures"] or suite["cases"] != cli_cases or suite["environment"] != "StudioServer":
        raise ValueError("Studio T-P3 suite must PASS with the same case count as the CLI suite")
    live = evidence["liveMatch"]
    if live["summon"] != "Accepted" or live["foodAfterSummon"] >= live["foodBeforeSummon"]:
        raise ValueError("live summon was not accepted and charged")
    if not live["allyXLater"] > live["allyXFirst"] or live["ticksLater"] <= live["ticksFirst"]:
        raise ValueError("live simulation did not advance")
    if live["snapshotKeys"].count("attackPower") or live["renderInstancesCreated"] != 0:
        raise ValueError("snapshot leaked attackPower or simulation created render instances")
    if not all(evidence["teardown"].values()):
        raise ValueError("test rig/playtest not torn down")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-evidence", type=Path, help="MCP-captured Studio evidence JSON")
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P3" / run_id
    out.mkdir(parents=True)
    checks = []
    cli_cases = 0
    unit = subprocess.run([str(LUAU), "tests/cli_p3.luau"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    (out / "unit.log").write_text(unit.stdout + unit.stderr, encoding="utf-8")
    try:
        report = json.loads(unit.stdout.splitlines()[0])
        cli_cases = len(report["cases"])
        (out / "unit.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        ok = unit.returncode == 0 and report["status"] == "PASS" and cli_cases > 0
        checks.append({"id": "unit", "status": "PASS" if ok else "FAIL", "cases": cli_cases, "failures": report["failures"]})
    except (ValueError, IndexError, KeyError) as error:
        checks.append({"id": "unit", "status": "FAIL", "reason": str(error)})
    extra = subprocess.run([str(LUAU), "tests/p3_evidence.luau"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    try:
        data = json.loads(extra.stdout.splitlines()[0])
        replay, order = data["seedReplay"], data["tickOrder"]
        (out / "seed-replay.json").write_text(json.dumps(replay, indent=2), encoding="utf-8")
        (out / "tick-order.json").write_text(json.dumps(order, indent=2), encoding="utf-8")
        replay_ok = extra.returncode == 0 and replay["identical"] and replay["checkpoints"] == replay["replayCheckpoints"]
        order_ok = order["declared"] == PHASES and order["observedTwoTicks"] == PHASES * 2
        checks.append({"id": "seed-replay", "status": "PASS" if replay_ok else "FAIL"})
        checks.append({"id": "tick-order", "status": "PASS" if order_ok else "FAIL"})
    except (ValueError, IndexError, KeyError) as error:
        checks.append({"id": "seed-replay/tick-order", "status": "FAIL", "reason": str(error)})
    if args.studio_evidence is None:
        checks.append({"id": "studio-headless", "status": "BLOCKED", "reason": "Requires --studio-evidence"})
    else:
        try:
            evidence = json.loads(args.studio_evidence.read_text(encoding="utf-8"))
            sourcemap = out / "test.sourcemap.json"
            subprocess.run([tool("rojo"), "sourcemap", "test.project.json", "-o", str(sourcemap)], cwd=ROOT, check=True,
                           capture_output=True)
            audit_studio(evidence, cli_cases, sourcemap_lengths(json.loads(sourcemap.read_text(encoding="utf-8"))))
            shutil.copyfile(args.studio_evidence, out / "studio.json")
            checks.append({"id": "studio-headless", "status": "PASS", "evidencePath": str(out / "studio.json")})
        except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
            checks.append({"id": "studio-headless", "status": "FAIL", "reason": str(error)})
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    (out / "report.json").write_text(json.dumps({"runId": run_id, "suite": "T-RESOURCE+T-COMBAT+T-HERO-01",
                                                 "status": status, "cases": checks}, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
