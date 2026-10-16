"""P9 acceptance gate: fresh CLI P6~P9 + Studio suite evidence. Exit 0 PASS, 1 FAIL, 2 BLOCKED."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_p0 import sourcemap_lengths  # noqa: E402
from verify_p2 import allowed_universes  # noqa: E402
from toolchain import tool  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SUITES = {"T-P6": "tests/cli_p6.luau", "T-P7": "tests/cli_p7.luau", "T-P8": "tests/cli_p8.luau",
          "T-P9": "tests/cli_p9.luau"}
STUDIO_SUITES = ("T-P6", "T-P8", "T-P9")  # test policy: Studio runs at P6/P8/P9 only
FIELDS = ("id", "expected", "actual", "status")


def audit_report(report, suite, environment):
    """Trust raw assertions, never a PASS summary."""
    cases = report.get("cases")
    if (report.get("suite") != suite or report.get("environment") != environment
            or report.get("status") != "PASS" or report.get("failures") != []
            or not isinstance(cases, list) or not cases):
        raise ValueError(f"{suite} must PASS with raw cases in {environment}")
    for case in cases:
        if case.get("status") != "PASS" or case.get("expected") != case.get("actual"):
            raise ValueError(f"{suite} raw assertion failed: {case.get('id')}")
    return report


def digest(cases):
    """Ordered assertion digest; ServerHarness capture computes the same two rolling hashes in Luau."""
    a = b = 0
    for case in cases:
        for byte in "\0".join(case[f] for f in FIELDS).encode("utf-8") + b"\n":
            a, b = (a * 31 + byte) % 1000000007, (b * 131 + byte) % 998244353
    return f"{a}:{b}"


def audit_studio(evidence, cli, expected_lengths):
    if evidence.get("schema") != "p9-studio-evidence/1" or not evidence.get("studio_id"):
        raise ValueError("unknown evidence schema or missing studio_id")
    if not expected_lengths or evidence.get("sourceLengths") != expected_lengths:
        raise ValueError("Studio evidence does not match the current source build")
    if evidence.get("gameId") not in allowed_universes():
        raise ValueError("gameId not in TestPolicy allowlist")
    for suite in STUDIO_SUITES:
        studio, fresh = evidence["suites"][suite], cli[suite]
        if (studio.get("suite") != suite or studio.get("environment") != "StudioServer"
                or studio.get("status") != "PASS" or studio.get("failures") != []
                or studio.get("seed") != fresh["seed"] or studio.get("cases") != len(fresh["cases"])
                or studio.get("digest") != digest(fresh["cases"])):
            raise ValueError(f"Studio {suite} differs from the fresh CLI run")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-evidence", type=Path)
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P9" / run_id
    out.mkdir(parents=True)
    checks, cli = [], {}
    for suite, path in SUITES.items():
        try:
            result = subprocess.run([tool("luau"), path], cwd=ROOT, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace")
            report = json.loads(result.stdout.splitlines()[0], strict=False)
            cli[suite] = audit_report(report, suite, "PureLuau")
            if result.returncode != 0:
                raise ValueError("CLI exited nonzero")
            checks.append({"id": "cli-" + suite, "status": "PASS", "cases": len(report["cases"])})
        except (OSError, ValueError, IndexError, KeyError, TypeError) as error:
            checks.append({"id": "cli-" + suite, "status": "FAIL", "reason": str(error)})
    if args.studio_evidence is None:
        checks.append({"id": "studio-suites", "status": "BLOCKED", "reason": "Requires --studio-evidence"})
        evidence = {}
    else:
        try:
            evidence = json.loads(args.studio_evidence.read_text(encoding="utf-8"))
            sourcemap = out / "test.sourcemap.json"
            subprocess.run([tool("rojo"), "sourcemap", "test.project.json", "-o", str(sourcemap)],
                           cwd=ROOT, check=True, capture_output=True)
            audit_studio(evidence, cli, sourcemap_lengths(json.loads(sourcemap.read_text(encoding="utf-8"))))
            checks.append({"id": "studio-suites", "status": "PASS"})
        except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
            evidence = {}
            checks.append({"id": "studio-suites", "status": "FAIL", "reason": str(error)})
    # Live items stay BLOCKED until recorded: never substitute mock or emulator results.
    live = {
        "datastore-live": lambda e: e["restoredEqual"] is True and e["staleOverwrites"] == 0
        and e["simultaneousOwners"] == 0,
        "perf-10min": lambda e: e["minutes"] >= 10 and e["matches"] >= 4 and e["tickP95Ms"] <= 10,
        "device-touch": lambda e: e["realDevice"] is True and e["multiTouch"] is True,
    }
    for name, passes in live.items():
        item = evidence.get(name)
        if item is None:
            checks.append({"id": name, "status": "BLOCKED", "reason": "no live evidence recorded"})
        else:
            try:
                checks.append({"id": name, "status": "PASS" if passes(item) else "FAIL", "evidence": item})
            except (KeyError, TypeError) as error:
                checks.append({"id": name, "status": "FAIL", "reason": f"malformed: {error}"})
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    (out / "report.json").write_text(json.dumps({"runId": run_id, "suite": "T-P9", "status": status,
                                                 "cases": checks}, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
