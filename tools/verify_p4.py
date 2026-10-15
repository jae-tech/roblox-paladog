"""P4 projectile/cast evidence gate. Exit 0 PASS, 1 FAIL, 2 BLOCKED without Studio."""
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


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def audit_report(report, environment):
    """Do not trust a PASS summary over the raw Runner assertions."""
    if (report.get("suite") != "T-P4" or report.get("environment") != environment
            or report.get("status") != "PASS" or report.get("failures") != []
            or not integer(report.get("seed"))):
        raise ValueError("T-P4 report must PASS in the expected environment")
    cases = report.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("T-P4 report requires nonempty raw cases")
    for case in cases:
        if (not isinstance(case, dict) or not isinstance(case.get("id"), str) or not case["id"]
                or case.get("status") != "PASS" or not isinstance(case.get("expected"), str)
                or not isinstance(case.get("actual"), str) or case["expected"] != case["actual"]
                or not integer(case.get("tick"))):
            raise ValueError("raw T-P4 assertion failed or malformed")
    return len(cases)


def audit_studio(evidence, cli_cases, expected_lengths, cli_report):
    """Validate raw MCP capture; never manufacture Studio runtime evidence."""
    if (evidence.get("schema") != "p4-studio-evidence/1"
            or not isinstance(evidence.get("studio_id"), str) or not evidence["studio_id"]):
        raise ValueError("unknown evidence schema or missing studio_id")
    lengths = evidence.get("sourceLengths")
    if (not expected_lengths or lengths != expected_lengths or not isinstance(lengths, dict)
            or any(not integer(v, 1) for v in lengths.values())):
        raise ValueError("Studio evidence does not match the current source build")
    if not integer(evidence.get("gameId"), 1) or evidence["gameId"] not in allowed_universes():
        raise ValueError("gameId not in TestPolicy allowlist")
    suite = evidence["studioSuite"]
    if (not integer(cli_cases, 1) or suite.get("suite") != "T-P4"
            or suite.get("environment") != "StudioServer" or suite.get("status") != "PASS"
            or suite.get("failures") != [] or not integer(suite.get("cases"), 1)
            or suite["cases"] != cli_cases):
        raise ValueError("Studio T-P4 suite must PASS with the positive CLI case count")
    if audit_report(evidence["rawStudioSuite"], "StudioServer") != cli_cases:
        raise ValueError("raw Studio results differ from the suite summary")
    if audit_report(cli_report, "PureLuau") != cli_cases:
        raise ValueError("fresh CLI report differs from the suite summary")
    raw = evidence["rawStudioSuite"]
    fields = ("id", "expected", "actual", "tick", "status")
    if (raw["seed"] != cli_report["seed"]
            or [[case[field] for field in fields] for case in raw["cases"]]
            != [[case[field] for field in fields] for case in cli_report["cases"]]):
        raise ValueError("Studio seed or ordered assertions differ from the fresh CLI report")
    live = evidence["liveMatch"]
    numeric_fields = ("manaBeforeCast", "manaAfterCast", "targetHpBefore", "targetHpAfter",
                      "heroXFirst", "heroXLater")
    if any(not number(live.get(key)) for key in numeric_fields):
        raise ValueError("live measurements must be finite numbers, not booleans")
    tick_fields = ("castAcceptedTick", "castReleaseTick", "projectileHitTick", "ticksFirst", "ticksLater")
    if any(not integer(live.get(key)) for key in tick_fields):
        raise ValueError("live ticks must be nonnegative integers")
    if live.get("cast") != "Accepted" or live["manaBeforeCast"] - live["manaAfterCast"] != 10000:
        raise ValueError("live cast was not accepted and charged exactly 10000 mana")
    if (live["castReleaseTick"] != live["castAcceptedTick"] + 4
            or live["projectileHitTick"] <= live["castReleaseTick"]
            or live["targetHpBefore"] - live["targetHpAfter"] != 100):
        raise ValueError("live pulse must release after 4 ticks and hit for 100 damage")
    if live["heroXLater"] <= live["heroXFirst"] or live["ticksLater"] <= live["ticksFirst"]:
        raise ValueError("live movement did not continue")
    for field in ("snapshotKeys", "snapshotProjectileKeys", "snapshotHeroActionKeys"):
        keys = live.get(field)
        if not isinstance(keys, list) or not keys or any(not isinstance(k, str) for k in keys):
            raise ValueError("live snapshots require captured entity/projectile/action keys")
        forbidden = ("attackpower", "damage", "hitentityids", "reservedprojectileslot")
        if any(any(secret in key.lower() for secret in forbidden) for key in keys):
            raise ValueError("snapshot leaked private combat state")
    if not integer(live.get("renderInstancesCreated")) or live["renderInstancesCreated"] != 0:
        raise ValueError("simulation created render Instances")
    teardown = evidence["teardown"]
    if teardown.get("rigStopped") is not True or teardown.get("playtestEnded") is not True:
        raise ValueError("test rig/playtest not torn down")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-evidence", type=Path, help="MCP-captured P4 Studio evidence JSON")
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P4" / run_id
    out.mkdir(parents=True)
    checks, cli_cases, seed, cli_report = [], 0, None, None

    def write(name, data):
        (out / name).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    try:
        result = subprocess.run([str(LUAU), "tests/cli_p4.luau"], cwd=ROOT, capture_output=True, text=True)
        (out / "unit.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        report = json.loads(result.stdout.splitlines()[0])
        write("unit.json", report)
        cli_cases = audit_report(report, "PureLuau")
        cli_report = report
        seed = report["seed"]
        if result.returncode != 0:
            raise ValueError("CLI exited nonzero")
        checks.append({"id": "unit", "status": "PASS", "cases": cli_cases})
        for name, prefixes in (("projectile", ("tprojectile",)), ("cast", ("thero", "tsec"))):
            cases = [case for case in report["cases"] if case["id"].startswith(prefixes)]
            write(name + ".json", {"suite": "T-P4", "seed": seed, "status": "PASS" if cases else "FAIL", "cases": cases})
            checks.append({"id": name, "status": "PASS" if cases else "FAIL", "cases": len(cases)})
    except (OSError, ValueError, IndexError, KeyError, TypeError, AttributeError) as error:
        checks.append({"id": "unit", "status": "FAIL", "reason": str(error)})
    try:
        build = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True)
        balance = json.loads((ROOT / "data/balance/mvp-proto-001.json").read_text(encoding="utf-8"))
        source_hash = hashlib.sha256()
        for folder in ("src", "tests", "test-support", "test-support-client"):
            for path in sorted((ROOT / folder).rglob("*.luau")):
                source_hash.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes())
        write("environment.json", {"runId": run_id, "buildId": build.stdout.strip(),
                                   "sourceHash": source_hash.hexdigest(), "balanceHash": balance["balanceHash"],
                                   "seed": seed, "environment": "PureLuau"})
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        checks.append({"id": "environment", "status": "FAIL", "reason": str(error)})
    if args.studio_evidence is None:
        checks.append({"id": "studio-projectile-cast", "status": "BLOCKED", "reason": "Requires --studio-evidence"})
    else:
        try:
            evidence = json.loads(args.studio_evidence.read_text(encoding="utf-8"))
            sourcemap = out / "test.sourcemap.json"
            result = subprocess.run(["rojo", "sourcemap", "test.project.json", "-o", str(sourcemap)],
                                    cwd=ROOT, check=True, capture_output=True, text=True)
            (out / "sourcemap.log").write_text(result.stdout + result.stderr, encoding="utf-8")
            audit_studio(evidence, cli_cases, sourcemap_lengths(json.loads(sourcemap.read_text(encoding="utf-8"))), cli_report)
            shutil.copyfile(args.studio_evidence, out / "studio.json")
            checks.append({"id": "studio-projectile-cast", "status": "PASS", "evidencePath": str(out / "studio.json")})
        except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
            checks.append({"id": "studio-projectile-cast", "status": "FAIL", "reason": str(error)})
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    write("report.json", {"runId": run_id, "suite": "T-P4", "status": status, "cases": checks})
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
