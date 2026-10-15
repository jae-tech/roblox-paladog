"""P0 evidence gate. Without --studio-evidence the Studio/MCP check stays BLOCKED (exit 2)."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def audit_production(path):
    tree = ET.parse(path)
    forbidden = {"TestSupport", "Tests", "ServerHarness", "ClientHarness", "fixtures"}
    for item in tree.iter("Item"):
        name = item.find("./Properties/string[@name='Name']")
        if name is not None and name.text in forbidden:
            raise ValueError("test node in production: " + name.text)
        if item.attrib.get("class") in {"RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent"}:
            raise ValueError("P0 production must have zero remote endpoints")
    for source in tree.iter("ProtectedString"):
        text = source.text or ""
        if any(marker in text for marker in ("TestSupport", "fixtures", "P0TestBuild", "GrantGold")):
            raise ValueError("test dependency in production source")
    return True


def audit_projects(production, test):
    def paths(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "$path":
                    yield value
                else:
                    yield from paths(value)
    if set(paths(production)) != {"src/shared", "src/server", "src/client"}:
        raise ValueError("P0 production paths must be exactly src/shared, src/server, src/client")
    for chain in [("ReplicatedStorage", "Shared"), ("ServerScriptService", "GameServer"),
                  ("StarterPlayer", "StarterPlayerScripts", "GameClient"), ("Workspace", "Environment"), ("Players",)]:
        left, right = production["tree"], test["tree"]
        for key in chain:
            left, right = left[key], right[key]
        if left != right:
            raise ValueError("production/test subtree diverges: " + "/".join(chain))
    return True


def sourcemap_lengths(sourcemap):
    """Map DataModel-relative full names to local source byte lengths."""
    lengths = {}

    def walk(node, prefix):
        for child in node.get("children", []):
            name = prefix + child["name"]
            paths = [p for p in child.get("filePaths", []) if p.endswith(".luau")]
            if paths:
                lengths[name] = len((ROOT / paths[0]).read_bytes())
            walk(child, name + ".")
    walk(sourcemap, "")
    return lengths


def audit_studio_evidence(evidence, expected_lengths):
    """Validate MCP-captured Studio runtime evidence; the gate itself cannot drive Studio."""
    policy = (ROOT / "test-support/TestPolicy.luau").read_text()
    allowed = {int(n) for n in re.findall(r"\d+", re.search(r"allowedUniverseIds\s*=\s*\{([^}]*)\}", policy).group(1))}
    marker = re.search(r'buildMarker\s*=\s*"([^"]+)"', (ROOT / "src/shared/BootstrapInfo.luau").read_text()).group(1)
    if evidence.get("schema") != "p0-studio-evidence/1" or not evidence.get("studio_id"):
        raise ValueError("unknown evidence schema or missing studio_id")
    if evidence["gameId"] == 0 or evidence["gameId"] not in allowed:
        raise ValueError("gameId not in TestPolicy allowlist: " + str(evidence["gameId"]))
    if evidence.get("testBuildMarker") is not True:
        raise ValueError("Studio place lacks P0TestBuild marker")
    if evidence["sourceLengths"] != expected_lengths:
        raise ValueError("Studio sources do not match local test build")
    for role in ("server", "client"):
        if evidence["boot"][role] != {"ready": True, "marker": marker}:
            raise ValueError(role + " boot not ready with marker " + marker)
    if not isinstance(evidence.get("studioVersion"), str) or not evidence["studioVersion"]:
        raise ValueError("missing studioVersion")
    characters = evidence["playerCharacters"]
    if evidence["characterAutoLoads"] is not False or not characters or any(c != "nil" for c in characters):
        raise ValueError("character auto-spawned or no player joined")
    if evidence["environmentChildren"] != 0:
        raise ValueError("P0 Environment must be empty")
    harness = evidence["harness"]
    if harness["authorizedUniverseAttr"] != evidence["gameId"]:
        raise ValueError("server harness did not authorize this universe")
    normal, intentional = harness["normal"], harness["intentional"]
    if (normal["environment"] != "StudioServer" or normal["status"] != "PASS" or normal["failures"]
            or not normal["cases"] or any(c["status"] != "PASS" for c in normal["cases"])):
        raise ValueError("Studio harness normal suite did not PASS")
    failed = [c["id"] for c in intentional["cases"] if c["status"] != "PASS"]
    if (intentional["environment"] != "StudioServer" or intentional["status"] != "FAIL"
            or intentional["failures"] != ["intentional-failure"] or failed != ["intentional-failure"]):
        raise ValueError("Studio intentional failure not reported as exactly one FAIL")
    if harness["unsupportedSuite"]["ok"] is not False:
        raise ValueError("harness accepted unsupported suite")
    client = evidence["clientHarness"]
    if (client["ok"] is not True or client["result"] != {"ready": True, "marker": marker}
            or client["gameId"] != evidence["gameId"] or client["character"] != "nil"):
        raise ValueError("client harness boot inspection failed")
    rejection = evidence["guardRejectionUnapproved"]
    if rejection["gameId"] != 0 or "approved universe" not in rejection["server"] or "not approved" not in rejection["client"]:
        raise ValueError("missing guard rejection control on an unapproved universe")
    production = evidence["productionRuntimeRequire"]
    if not (production["status"] == "PASS" and production.get("evidence")) and not (
            production["status"] == "WAIVED" and production.get("decidedBy") and production.get("basis")):
        raise ValueError("productionRuntimeRequire must be PASS with evidence or WAIVED with decidedBy/basis")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-only", action="store_true", help="excludes runtime gate; does NOT complete P0")
    parser.add_argument("--studio-evidence", type=Path, help="MCP-captured Studio runtime evidence JSON")
    args = parser.parse_args()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P0" / run_id
    out.mkdir(parents=True)
    checks = []

    def record(name, status, **details):
        checks.append({"id": name, "status": status, **details})

    def command(name, argv, expected=0):
        try:
            result = subprocess.run([str(a) for a in argv], cwd=ROOT, capture_output=True, text=True)
        except FileNotFoundError as error:
            record(name, "BLOCKED", reason=str(error), command=[str(a) for a in argv])
            return None
        (out / (name + ".log")).write_text(result.stdout + result.stderr)
        record(name, "PASS" if result.returncode == expected else "FAIL", exitCode=result.returncode,
               expectedExitCode=expected, command=[str(a) for a in argv], evidencePath=str(out / (name + ".log")))
        return result

    try:
        audit_projects(json.loads((ROOT / "default.project.json").read_text()),
                       json.loads((ROOT / "test.project.json").read_text()))
        record("project-mapping-contract", "PASS")
    except (ValueError, KeyError, TypeError) as error:
        record("project-mapping-contract", "FAIL", reason=str(error))
    references = json.loads((ROOT / "tools/reference-hashes.json").read_text())
    actual = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in references}
    record("reference-preservation", "PASS" if actual == references and len(actual) == 7 else "FAIL")
    (out / "reference-hashes.json").write_text(json.dumps(actual, indent=2))
    lock = json.loads((ROOT / "tools/toolchain-lock.json").read_text())
    for asset in lock["assets"]:
        file = ROOT / ".tools" / (asset["name"] + (".d.luau" if asset["name"] == "roblox-types" else ".zip"))
        record("checksum-" + asset["name"], "BLOCKED" if not file.exists() else (
            "PASS" if hashlib.sha256(file.read_bytes()).hexdigest() == asset["sha256"] else "FAIL"))
    versions = {"rojo": "7.7.1", "selene": "0.32.0", "luau-lsp": "1.70.1"}
    for name, version in versions.items():
        result = command("version-" + name, [name, "--version"])
        if result is not None and version not in result.stdout + result.stderr:
            record("pin-" + name, "FAIL", expected=version)
    luau = ROOT / ".tools/luau-0.742/luau"
    analyze = ROOT / ".tools/luau-0.742/luau-analyze"
    stylua = ROOT / ".tools/stylua-2.6.0/stylua"
    sources = ["src", "tests", "test-support", "test-support-client"]
    command("python-tests", [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests", "-v"])
    command("python-syntax", [sys.executable, "-m", "compileall", "-q", "tools"])
    result = command("pure-tests", [luau, "tests/cli.luau"])
    if result is not None and result.returncode == 0:
        try:
            report = json.loads(result.stdout)
            if report["status"] != "PASS" or len(report["cases"]) == 0:
                raise ValueError("empty or non-PASS report")
            (out / "pure-tests.json").write_text(json.dumps(report, indent=2))
        except (ValueError, KeyError) as error:
            record("pure-report-schema", "FAIL", reason=str(error))
    result = command("intentional-failure", [luau, "tests/intentional-failure.luau"], expected=1)
    if result is not None:
        try:
            report = json.loads(result.stdout)
            assert report["status"] == "FAIL" and len(report["failures"]) > 0
            (out / "intentional-failure.json").write_text(json.dumps(report, indent=2))
        except (ValueError, KeyError, AssertionError):
            record("intentional-failure-json", "FAIL")
    command("pure-analysis", [analyze, "tests"])
    negative = out / "intentional-type-error.luau"
    negative.write_text('--!strict\nlocal value: number = "not a number"\nprint(value)\n')
    command("analyzer-negative-control", [analyze, negative], expected=1)
    command("lsp-negative-control", ["luau-lsp", "analyze", negative], expected=1)
    command("lint", ["selene", *sources])
    command("format", [stylua, "--check", *sources])
    production_build = None
    for mode, project in [("production", "default.project.json"), ("test", "test.project.json")]:
        built = command("build-" + mode, ["rojo", "build", project, "-o", out / (mode + ".rbxlx")])
        if mode == "production":
            production_build = built
        mapped = command("sourcemap-" + mode, ["rojo", "sourcemap", project, "-o", out / (mode + ".sourcemap.json")])
        dirs = ["src"] if mode == "production" else sources[:1] + sources[2:]
        if mapped is None or mapped.returncode != 0:
            record("roblox-analysis-" + mode, "BLOCKED", reason="sourcemap prerequisite unavailable")
        else:
            command("roblox-analysis-" + mode, ["luau-lsp", "analyze", "--platform", "roblox", "--sourcemap",
                    out / (mode + ".sourcemap.json"), "--definitions", "@roblox=.tools/roblox-types.d.luau", *dirs])
    try:
        if production_build is None or production_build.returncode != 0:
            raise FileNotFoundError("production build prerequisite unavailable")
        audit_production(out / "production.rbxlx")
        record("production-isolation", "PASS", actual="zero test harness nodes and remote endpoints in built XML")
    except FileNotFoundError as error:
        record("production-isolation", "BLOCKED", reason=str(error))
    except (OSError, ValueError, ET.ParseError) as error:
        record("production-isolation", "FAIL", reason=str(error))
    boot = {"status": "NOT_RUN", "server": "NOT_RUN", "client": "NOT_RUN", "studio_id": None,
            "reason": "No real Studio server/client runtime execution recorded by this CLI gate"}
    studio = None
    if not args.local_only:
        if args.studio_evidence is None:
            record("studio-mcp-runtime", "BLOCKED", reason="Requires --studio-evidence captured via Studio MCP")
        else:
            try:
                studio = json.loads(args.studio_evidence.read_text())
                expected = sourcemap_lengths(json.loads((out / "test.sourcemap.json").read_text()))
                audit_studio_evidence(studio, expected)
                shutil.copyfile(args.studio_evidence, out / "studio-evidence.json")
                record("studio-mcp-runtime", "PASS", studio_id=studio["studio_id"], gameId=studio["gameId"],
                       evidencePath=str(out / "studio-evidence.json"))
                boot = {"status": "PASS", "server": "PASS", "client": "PASS", "studio_id": studio["studio_id"],
                        "reason": "validated MCP-captured Studio evidence"}
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
                studio = None
                record("studio-mcp-runtime", "FAIL", reason=str(error))
    (out / "boot.json").write_text(json.dumps(boot, indent=2))
    status = "FAIL" if any(c["status"] == "FAIL" for c in checks) else (
        "BLOCKED" if any(c["status"] == "BLOCKED" for c in checks) else "PASS")
    mcp_raw = ROOT / ".omx/ultragoal/mcp-preflight.jsonl"
    if mcp_raw.exists():
        shutil.copyfile(mcp_raw, out / "mcp-preflight.jsonl")
    mcp = {"status": "NOT_RUN", "tools": None, "studio_id": None, "selectedStudioVersion": None,
           "nativeRobloxTools": None, "installedStudioMCP": None,
           "rawEvidence": "mcp-preflight.jsonl" if mcp_raw.exists() else None,
           "reason": "This gate does not reconnect or guess capabilities"}
    if mcp_raw.exists():
        mcp.update({"status": "BLOCKED", "historicalObservation": True,
                    "transcriptFileModifiedAt": datetime.fromtimestamp(mcp_raw.stat().st_mtime, timezone.utc).isoformat(),
                    "transcriptSha256": hashlib.sha256(mcp_raw.read_bytes()).hexdigest(),
                    "reason": "Session preflight transcript copied; inspect raw tools/list result"})
        for line in mcp_raw.read_text().splitlines():
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            # Preserve actual transcript entries; never infer a live connection from installed binaries.
            mcp.setdefault("historicalTranscript", []).append(entry)
    studio_mcp_binary = Path("/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP")
    if studio_mcp_binary.exists():
        try:
            version = subprocess.run([str(studio_mcp_binary), "--version"], capture_output=True, text=True, timeout=5)
            if version.returncode == 0:
                mcp["installedStudioMCP"] = version.stdout.strip()
        except (OSError, subprocess.TimeoutExpired) as error:
            mcp["installedVersionStatus"] = "unknown: " + str(error)
    (out / "mcp-capabilities.json").write_text(json.dumps(mcp, indent=2))
    studio_plist = Path("/Applications/RobloxStudio.app/Contents/Info.plist")
    installed_studio = None
    if studio_plist.exists():
        with studio_plist.open("rb") as stream:
            installed_studio = plistlib.load(stream).get("CFBundleShortVersionString")
    build_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob("*.rbxlx")}
    environment = {"utc": run_id, "platform": platform.platform(), "python": sys.version,
                   "gitCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                   "workingTree": "dirty" if subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout.strip() else "clean", "buildHashes": build_hashes,
                   "balanceHash": None, "schemaVersion": None, "protocolVersion": None,
                   "seed": 12345, "clockPolicy": "fake integer ticks in CLI and Studio harness",
                   "studio_id": studio["studio_id"] if studio else None,
                   "studioVersion": studio["studioVersion"] if studio else None, "mcpSchemaHash": None,
                   "installedStudioVersion": installed_studio, "installedStudioMCP": mcp["installedStudioMCP"],
                   "cleanCheckoutReproduction": "NOT_RUN",
                   "tools": {n: shutil.which(n) for n in versions}, "lock": lock,
                   "localBinaryHashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in (luau, analyze, stylua) if p.exists()}}
    (out / "toolchain.json").write_text(json.dumps(environment, indent=2))
    (out / "environment.json").write_text(json.dumps(environment, indent=2))
    p0_complete = status == "PASS" and studio is not None
    studio_status = "PASS" if studio else "BLOCKED"
    task_titles = [
        ("P0.1", "BLOCKED", "Git history and proposed file policy", "team branch agreement not claimed"),
        ("P0.2", studio_status, "Pinned local toolchain", "Studio " + (studio["studioVersion"] if studio else "compatibility/runtime not verified")),
        ("P0.3", studio_status, "Production/test tree and bootstrap", "Studio server/client boot " + ("PASS" if studio else "NOT_RUN")),
        ("P0.4", studio_status, "Assert runner, fake clock/RNG/store", "CLI assertions in pure-tests.json; Studio runner " + ("PASS via ServerHarness" if studio else "NOT_RUN")),
        ("P0.5", status if status == "FAIL" else "PASS" if all(c["status"] == "PASS" for c in checks if c["id"] != "studio-mcp-runtime") else "BLOCKED", "Static/lint/format/build gates", "clean checkout reproduction NOT_RUN"),
        ("P0.6", studio_status, "MCP discovery and tree isolation", ("studio_id " + studio["studio_id"] + "; production runtime require " + studio["productionRuntimeRequire"]["status"]) if studio else "no selected studio_id; runtime require failure NOT_RUN"),
    ]
    cards = [{"taskId": task_id, "status": task_status, "title": title, "owner": "P0 foundation executor; leader reviews",
              "prerequisite": "six design docs + seven unchanged REA docs", "ownedFiles": ["src/", "tests/", "test-support/", "test-support-client/", "tools/", "*.project.json", "docs/DEVELOPMENT.md"],
              "requirements": ["R-10"], "tests": ["T-TOOL"],
              "successCriteria": "IMPLEMENTATION_PLAN section P0 and TEST_PLAN T-TOOL; local PASS does not imply P0 complete",
              "nonGoals": ["P1-P9", "real DataStore", "asset upload", "public publish"],
              "commands": ["python3 tools/setup_tools.py", "python3 tools/verify_p0.py --local-only", "python3 tools/verify_p0.py"],
              "rawEvidence": str(out), "buildId": build_hashes, "balanceHash": None, "seed": 12345,
              "StudioVersion": environment["studioVersion"], "installedStudioVersion": installed_studio,
              "MCPVersion": mcp["installedStudioMCP"], "verdict": task_status, "unresolvedRisks": risk}
             for task_id, task_status, title, risk in task_titles]
    (out / "task-cards.json").write_text(json.dumps(cards, indent=2))
    # P0Complete covers the gate checks; open task cards (e.g. P0.1 Git policy) are listed, not hidden.
    report = {"runId": run_id, "suite": "T-TOOL", "scope": "local-only" if args.local_only else "P0",
              "status": status, "cases": checks, "P0Complete": p0_complete, "boot": boot,
              "openTasks": [card["taskId"] for card in cards if card["status"] != "PASS"],
              "productionRuntimeRequire": studio["productionRuntimeRequire"] if studio else "NOT_RUN"}
    (out / "report.json").write_text(json.dumps(report, indent=2))
    (out / "build.log").write_text("\n".join((out / ("build-" + mode + ".log")).read_text() for mode in ("production", "test") if (out / ("build-" + mode + ".log")).exists()))
    print(json.dumps({"status": status, "P0Complete": p0_complete, "report": str(out / "report.json")}))
    return 1 if status == "FAIL" else 2 if status == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
