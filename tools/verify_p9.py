"""P9 acceptance gate: fresh CLI P2~P9, Studio suite evidence, production release audit and the
artifacts/P9 evidence bundle (acceptance/security/performance/asset-audit/review). Exit 0 PASS, 1 FAIL, 2 BLOCKED."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from balance_lib import asset_audit, release_and_repo_files  # noqa: E402
from verify_p0 import audit_production, sourcemap_lengths  # noqa: E402
from verify_p2 import allowed_universes  # noqa: E402
from toolchain import tool  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SUITES = {f"T-P{n}": f"tests/cli_p{n}.luau" for n in range(2, 10)}
STUDIO_SUITES = tuple(SUITES)  # P9 is the full-regression stage (test policy)
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


# External fetches or asset references a code-built release must not contain (HttpService only for GUID/JSON).
EXTERNAL = re.compile(r"rbxassetid://|https?://|loadstring|require\(\s*\d|HttpService:(?!GenerateGUID|JSON)\w+")


def audit_release(rbxlx, manifest, balance, release_files, repo_files):
    """P9.5: production build has no test harness, foreign scripts, debug grants or unmanifested assets."""
    audit_production(rbxlx)  # test nodes, remote endpoints in XML, test/debug-grant markers
    text = rbxlx.read_text(encoding="utf-8")
    uploaded = {str(e["assetId"]) for e in manifest["entries"] if e.get("status") == "uploaded"}
    for match in EXTERNAL.finditer(text):
        tail = text[match.end():match.end() + 20]
        if not (match.group() == "rbxassetid://" and re.match(r"\d+", tail).group() in uploaded):
            raise ValueError("external reference in production build: " + match.group() + tail)
    scripts = len(re.findall(r'<Item class="(?:Script|LocalScript|ModuleScript)"', text))
    if scripts != len(release_files):
        raise ValueError(f"{scripts} scripts in build vs {len(release_files)} release sources (foreign script?)")
    errors = asset_audit(balance, manifest, release_files, repo_files)
    if errors:
        raise ValueError("; ".join(errors))
    return {"scripts": scripts, "productionSha256": hashlib.sha256(rbxlx.read_bytes()).hexdigest(),
            "manifestSha256": hashlib.sha256((ROOT / "data/assets/asset-manifest.json").read_bytes()).hexdigest(),
            "balanceHash": balance["balanceHash"],
            "assets": {e["presentationId"]: e["status"] for e in manifest["entries"]}}


def bundle(dest, checks, cli, evidence, release):
    """Write artifacts/P9/{acceptance,security,performance,asset-audit}.json and review.md from this run."""
    by_id = {c["id"]: c for c in checks}
    p9 = cli.get("T-P9", {}).get("cases", [])

    def picked(*prefixes):
        return [c for c in p9 if c["id"].startswith(prefixes)]
    files = {
        "acceptance.json": {"suites": {k: {"status": by_id["cli-" + k]["status"], "cases": by_id["cli-" + k].get("cases")}
                                       for k in SUITES},
                            "studio": by_id["studio-suites"]["status"], "e2e": picked("e2e-", "s0", "rejoin-"),
                            "lifecycle": picked("cycles-"), "extraStudio": evidence.get("extraStudio")},
        "security.json": {"attackMatrix": picked("attack-"), "datastoreLive": by_id["datastore-live"],
                          "note": "server authority / duplicate reward / stale write cases also run in T-P2/T-P7/T-P8"},
        "performance.json": {"cli": picked("perf-"), "studio10min": by_id["perf-10min"],
                             "networkPoor": by_id["network-poor"]},
        "asset-audit.json": {"productionRelease": by_id["production-release"], **(release or {})},
    }
    for name, data in files.items():
        (dest / name).write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    rows = "\n".join(f"| {c['id']} | {c['status']} | {c.get('reason', '')} |" for c in checks)
    (dest / "review.md").write_text(
        "# P9 review checklist\n\nGenerated by tools/verify_p9.py; reviewer sign-off is NOT recorded here.\n\n"
        "| check | status | reason |\n|---|---|---|\n" + rows + "\n\n## Release preconditions (manual)\n\n"
        "- PersistencePolicy.enabled is false and pinned to the QA universe: enable for the release universe only\n"
        "  with explicit approval, or progress is not saved.\n"
        "- Android real-device multi-touch (device-touch) must be checked before release.\n"
        "- Visual/licence review of assets is manual (all entries are code-built placeholders).\n", encoding="utf-8")


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
    release = None
    try:
        rbxlx = out / "production.rbxlx"
        subprocess.run([tool("rojo"), "build", "default.project.json", "-o", str(rbxlx)],
                       cwd=ROOT, check=True, capture_output=True)
        release = audit_release(
            rbxlx, json.loads((ROOT / "data/assets/asset-manifest.json").read_text(encoding="utf-8")),
            json.loads((ROOT / "data/balance/mvp-proto-001.json").read_text(encoding="utf-8")),
            *release_and_repo_files())
        checks.append({"id": "production-release", "status": "PASS", "scripts": release["scripts"]})
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        checks.append({"id": "production-release", "status": "FAIL", "reason": str(error)})
    # Live items stay BLOCKED until recorded: never substitute mock or emulator results.
    live = {
        "datastore-live": lambda e: e["restoredEqual"] is True and e["staleOverwrites"] == 0
        and e["simultaneousOwners"] == 0,
        "perf-10min": lambda e: e["minutes"] >= 10 and e["matches"] >= 4 and e["tickP95Ms"] <= 10,
        "device-touch": lambda e: e["realDevice"] is True and e["multiTouch"] is True,
        "network-poor": lambda e: e["summonAccepted"] is True and e["castAccepted"] is True
        and e["connectedRatio"] >= 0.95,
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
    bundle(out, checks, cli, evidence, release)
    for name in ("acceptance.json", "security.json", "performance.json", "asset-audit.json", "review.md"):
        (ROOT / "artifacts/P9" / name).write_bytes((out / name).read_bytes())  # latest run at the plan's path
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
