"""R7 integration gate (docs/REMAKE_PLAN.md R7). Exit 0 PASS, 1 FAIL, 2 BLOCKED.

Runs the full local regression (every CLI suite, P0 local, data regeneration, release audit, Python tests)
and audits MCP-captured Studio evidence: the same suites on the Studio server/client with identical ordered
assertions, a 10-minute 4-match load, real-input play scenarios and teardown. Real DataStore v2 and
Android device multitouch need a person (approval / a device); without their evidence they stay BLOCKED.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_p0 import sourcemap_lengths  # noqa: E402
from toolchain import tool  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
# suite id -> CLI runner; the Studio side of each must match it assertion for assertion
CLI_SUITES = {
    "T-R1": "tests/cli_r1.luau",
    "T-R2": "tests/cli_r2.luau",
    "T-R3": "tests/cli_r3.luau",
    "T-R4": "tests/cli_r4.luau",
    "T-R5": "tests/cli_r5.luau",
    "T-R6": "tests/cli_r6.luau",
    "T-R7": "tests/cli_r7.luau",
    "T-3D": "tests/cli_3d.luau",
    "T-P2": "tests/cli_p2.luau",
    "T-P8": "tests/cli_p8.luau",
}
CLIENT_SUITES = {"T-R4"}
LOAD_TICKS = 18000  # 10 minutes at 30 Hz
LOAD_P95_MS = 16.6  # half of the 33.3 ms frame
PLAY_SCENARIOS = ("campaign", "survival", "shadow")


def case_hash(cases):
    """Order-sensitive 32-bit FNV-1a over id/expected/actual/status lines (ticks may differ between hosts).

    Studio computes the same value in Luau (docs/HANDOFF.md R7), so evidence carries the hash, not the cases.
    """
    text = "".join(f"{c['id']}={c['expected']}={c['actual']}={c['status']}\n" for c in cases)
    value = 2166136261
    for byte in text.encode("utf-8"):
        value = ((value ^ byte) * 16777619) % 4294967296
    return f"{value:08x}"


def allowed_universes():
    policy = (ROOT / "test-support/TestPolicy.luau").read_text(encoding="utf-8")
    return {int(n) for n in re.findall(r"\d+", re.search(r"allowedUniverseIds\s*=\s*\{([^}]*)\}", policy).group(1))}


def audit_studio(evidence, cli_reports, expected_lengths):
    """Validate MCP-captured R7 Studio evidence; raises ValueError on any weak or failing field."""
    if evidence.get("schema") != "r7-studio-evidence/1" or not evidence.get("studio_id"):
        raise ValueError("unknown evidence schema or missing studio_id")
    if evidence.get("gameId") not in allowed_universes():
        raise ValueError("gameId not in TestPolicy allowlist")
    if evidence.get("sourceLengths") != expected_lengths:
        raise ValueError("Studio evidence was captured from a different build than the current sources")
    suites = evidence.get("suites", {})
    for suite_id, report in cli_reports.items():
        studio = suites.get(suite_id)
        if studio is None:
            raise ValueError(f"{suite_id} missing from Studio evidence")
        environment = "StudioClient" if suite_id in CLIENT_SUITES else "StudioServer"
        if studio.get("environment") != environment or studio.get("status") != "PASS" or studio.get("failures"):
            raise ValueError(f"{suite_id} must PASS on the {environment}")
        if studio.get("count") != len(report["cases"]) or studio.get("hash") != case_hash(report["cases"]):
            raise ValueError(f"{suite_id} Studio assertions differ from the CLI run")
    load = evidence.get("load", {})
    if load.get("ticks", 0) < LOAD_TICKS or not isinstance(load.get("p95"), (int, float)):
        raise ValueError("Studio load must measure 10 minutes of game time")
    if load["p95"] > LOAD_P95_MS:
        raise ValueError(f"Studio load p95 {load['p95']} ms is over {LOAD_P95_MS} ms")
    if load.get("status") != "PASS" or load.get("failures") or not load.get("count"):
        raise ValueError("Studio long-load T-R7 run must PASS every assertion")
    play = evidence.get("play", {})
    for name in PLAY_SCENARIOS:
        scenario = play.get(name, {})
        if scenario.get("status") != "PASS" or scenario.get("input") != "real" or not scenario.get("steps"):
            raise ValueError(f"real-input play scenario '{name}' is missing or not PASS")
        if scenario.get("runtimeErrors", 1) != 0:
            raise ValueError(f"play scenario '{name}' logged runtime errors")
    if not evidence.get("teardown") or not all(evidence["teardown"].values()):
        raise ValueError("playtest/test state not torn down")
    return True


def run_cli(out):
    reports, checks = {}, []
    for suite_id, path in CLI_SUITES.items():
        result = subprocess.run([str(tool("luau")), path], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
        name = suite_id.lower()
        (out / f"{name}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        try:
            report = json.loads(result.stdout.splitlines()[0])
            ok = result.returncode == 0 and report["status"] == "PASS" and len(report["cases"]) > 0
            reports[suite_id] = report
            checks.append({"id": f"cli-{name}", "status": "PASS" if ok else "FAIL", "cases": len(report["cases"]),
                           "hash": case_hash(report["cases"]), "failures": report["failures"]})
        except (ValueError, IndexError, KeyError) as error:
            checks.append({"id": f"cli-{name}", "status": "FAIL", "reason": str(error)})
    return reports, checks


def run_command(check_id, argv, out, ok_codes=(0,)):
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    (out / f"{check_id}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    return {"id": check_id, "status": "PASS" if result.returncode in ok_codes else "FAIL", "exitCode": result.returncode}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-evidence", type=Path, help="MCP-captured R7 Studio evidence JSON")
    parser.add_argument("--skip-local", action="store_true", help="only audit evidence (CLI suites still run)")
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/R7" / run_id
    out.mkdir(parents=True)
    reports, checks = run_cli(out)
    if not args.skip_local:
        python = sys.executable
        checks.append(run_command("p0-local", [python, "tools/verify_p0.py", "--local-only"], out))
        checks.append(run_command("remake-diff0", [python, "tools/build_remake.py", "--check"], out))
        checks.append(run_command("release-audit", [python, "tools/release_audit.py"], out))
        checks.append(run_command("python-tests", [python, "-m", "unittest", "discover", "-s", "tools/tests"], out))
    evidence = None
    if args.studio_evidence is None:
        checks.append({"id": "studio", "status": "BLOCKED", "reason": "Requires --studio-evidence"})
    else:
        try:
            evidence = json.loads(args.studio_evidence.read_text(encoding="utf-8"))
            sourcemap = out / "test.sourcemap.json"
            subprocess.run([tool("rojo"), "sourcemap", "test.project.json", "-o", str(sourcemap)], cwd=ROOT,
                           check=True, capture_output=True)
            audit_studio(evidence, reports, sourcemap_lengths(json.loads(sourcemap.read_text(encoding="utf-8"))))
            shutil.copyfile(args.studio_evidence, out / "studio.json")
            checks.append({"id": "studio", "status": "PASS", "load": {k: evidence["load"][k] for k in
                                                                     ("ticks", "p50", "p95", "p99", "max")}})
        except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
            checks.append({"id": "studio", "status": "FAIL", "reason": str(error)})
    # Needs a person: user-approved QA DataStore run and a real Android device.
    for check_id, key, reason in (
        ("datastore-v2", "datastore", "real QA DataStore with profile v2 needs user approval"),
        ("device-touch", "deviceTouch", "Android device multitouch needs a real device (known limitation)"),
    ):
        entry = (evidence or {}).get(key) or {}
        if entry.get("status") == "PASS" and entry.get("approvedBy") and entry.get("steps"):
            checks.append({"id": check_id, "status": "PASS", "approvedBy": entry["approvedBy"]})
        else:
            checks.append({"id": check_id, "status": "BLOCKED", "reason": reason})
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    (out / "report.json").write_text(json.dumps({"runId": run_id, "suite": "R7", "status": status, "cases": checks},
                                                indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
