"""P2 evidence gate (T-SEC basics + T-ISOLATION). Exit 0 PASS, 1 FAIL, 2 BLOCKED (no Studio evidence)."""
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

ROOT = Path(__file__).resolve().parents[1]
LUAU = ROOT / ".tools/luau-0.742/luau"


def audit_isolation(evidence, cli_cases, expected_lengths):
    """Validate MCP-captured two-client evidence; raises ValueError on any weak or failing field."""
    policy = (ROOT / "test-support/TestPolicy.luau").read_text(encoding="utf-8")
    allowed = {int(n) for n in re.findall(r"\d+", re.search(r"allowedUniverseIds\s*=\s*\{([^}]*)\}", policy).group(1))}
    limits = (ROOT / "src/shared/Protocol.luau").read_text(encoding="utf-8")
    burst = int(re.search(r"discreteBurst = (\d+)", limits).group(1))
    if evidence.get("schema") != "p2-isolation-evidence/1" or not evidence.get("studio_id"):
        raise ValueError("unknown evidence schema or missing studio_id")
    if evidence.get("sourceLengths") != expected_lengths:
        raise ValueError("Studio evidence was captured from a different build than the current sources")
    if evidence["gameId"] == 0 or evidence["gameId"] not in allowed:
        raise ValueError("gameId not in TestPolicy allowlist")
    suite = evidence["studioSuite"]
    if suite["status"] != "PASS" or suite["failures"] or suite["cases"] != cli_cases or suite["environment"] != "StudioServer":
        raise ValueError("Studio T-P2 suite must PASS with the same case count as the CLI suite")
    attacker, victim = evidence["clients"]["attacker"], evidence["clients"]["victim"]
    if attacker["userId"] == victim["userId"] or not attacker["matchId"] or attacker["matchId"] == victim["matchId"]:
        raise ValueError("isolation needs two players in two distinct matches")
    for client in (attacker, victim):
        if client["bootstrap"] != {"status": "Ready", "storage": "Mock/InMemory"}:
            raise ValueError("bootstrap must be Ready and show the Mock store")
        if client["foreignSnapshots"] != 0 or client["snapshots"] < 1:
            raise ValueError("each client must receive only its own snapshots")
    messages = attacker["messages"]
    if "client1-attack-001:Rejected:NotOwner" not in messages:
        raise ValueError("foreign match command was not rejected as NotOwner")
    if sum(m.endswith(":Rejected:InvalidPayload") for m in messages) < 3:
        raise ValueError("malformed payloads (field/Instance/NaN) were not all rejected")
    if any(not m.startswith("client2-") for m in victim["messages"]):
        raise ValueError("victim received another player's messages")
    after = evidence["serverAfterAttack"]
    if after["victim"]["pendingSeqs"] or after["victim"]["axis"] != 0 or after["victim"]["revision"] != 1:
        raise ValueError("attacker input changed the victim's state")
    flood = evidence["flood"]
    if flood["attackerAdmitted"] > burst or flood["attackerReplies"] > burst or flood["dropped"] != flood["sent"] - flood["attackerAdmitted"]:
        raise ValueError("flood exceeded the discrete token bucket")
    if flood["victimDuringFlood"] != "Pending":
        raise ValueError("another player's command was not served during the flood")
    if not all(evidence["teardown"].values()):
        raise ValueError("test rig/playtest not torn down")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--isolation-evidence", type=Path, help="MCP-captured Studio two-client evidence JSON")
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P2" / run_id
    out.mkdir(parents=True)
    checks = []
    result = subprocess.run([str(LUAU), "tests/cli_p2.luau"], cwd=ROOT, capture_output=True, text=True)
    (out / "protocol-tests.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    cli_cases = 0
    try:
        report = json.loads(result.stdout.splitlines()[0])
        cli_cases = len(report["cases"])
        (out / "protocol-tests.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        ok = result.returncode == 0 and report["status"] == "PASS" and cli_cases > 0
        checks.append({"id": "protocol-tests", "status": "PASS" if ok else "FAIL", "cases": cli_cases,
                       "failures": report["failures"]})
    except (ValueError, IndexError, KeyError) as error:
        checks.append({"id": "protocol-tests", "status": "FAIL", "reason": str(error)})
    if args.isolation_evidence is None:
        checks.append({"id": "studio-isolation", "status": "BLOCKED", "reason": "Requires --isolation-evidence"})
    else:
        try:
            evidence = json.loads(args.isolation_evidence.read_text(encoding="utf-8"))
            sourcemap = out / "test.sourcemap.json"
            subprocess.run(["rojo", "sourcemap", "test.project.json", "-o", str(sourcemap)], cwd=ROOT, check=True,
                           capture_output=True)
            audit_isolation(evidence, cli_cases, sourcemap_lengths(json.loads(sourcemap.read_text(encoding="utf-8"))))
            shutil.copyfile(args.isolation_evidence, out / "isolation.json")
            checks.append({"id": "studio-isolation", "status": "PASS", "evidencePath": str(out / "isolation.json")})
        except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
            checks.append({"id": "studio-isolation", "status": "FAIL", "reason": str(error)})
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    (out / "report.json").write_text(json.dumps({"runId": run_id, "suite": "T-SEC+T-ISOLATION", "status": status,
                                                 "cases": checks}, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
