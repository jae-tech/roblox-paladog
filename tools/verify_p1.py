"""P1 evidence gate (T-DATA + T-ASSET). Exit 0 PASS, 1 FAIL. Writes artifacts/P1/<UTC runId>/."""
from datetime import datetime, timezone
import json
import subprocess
import sys

from balance_lib import (BALANCE_VERSION, ROOT, DataError, asset_audit, load_sources, outputs, overlay_bytes,
                         release_and_repo_files)


def main():
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = ROOT / "artifacts/P1" / run_id
    out.mkdir(parents=True)
    checks = []

    def command(name, argv):
        result = subprocess.run([sys.executable, *argv], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
        (out / (name + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
        checks.append({"id": name, "status": "PASS" if result.returncode == 0 else "FAIL",
                       "exitCode": result.returncode, "command": argv, "evidencePath": str(out / (name + ".log"))})
        return result

    golden = command("golden-tests", ["-m", "unittest", "-v", "tools/tests/test_p1.py"])
    (out / "golden.json").write_text(json.dumps(
        {"status": "PASS" if golden.returncode == 0 else "FAIL",
         "cases": [line for line in golden.stderr.splitlines() if line.endswith((" ok", " FAIL", " ERROR"))]},
        indent=2, ensure_ascii=False), encoding="utf-8")
    command("import-check", ["tools/import_reference.py", "--check"])
    command("build-check", ["tools/build_balance.py", "--version", BALANCE_VERSION, "--check"])
    command("validate-strict", ["tools/validate_data.py", "--strict"])
    try:
        first, second = outputs(load_sources(), overlay_bytes()), outputs(load_sources(), overlay_bytes())
        differing = sorted(path for path in first if first[path] != second.get(path))
        (out / "regeneration.diff").write_text("\n".join(differing) + ("\n" if differing else ""), encoding="utf-8")
        checks.append({"id": "regeneration-diff0", "status": "PASS" if not differing else "FAIL",
                       "differingFiles": differing})
        manifest = json.loads(first["data/reference/manifest.json"])
        balance = json.loads(first[f"data/balance/{BALANCE_VERSION}.json"])
        (out / "provenance.json").write_text(first[f"data/balance/{BALANCE_VERSION}.provenance.json"], encoding="utf-8")
        (out / "conversion-report.json").write_text(json.dumps({
            "runId": run_id, "balanceVersion": BALANCE_VERSION, "balanceHash": balance["balanceHash"],
            "overlayFileSha256": balance["overlayFileSha256"], "recordsSha256": manifest["recordsSha256"],
            "sources": manifest["sources"], "counts": manifest["counts"], "quarantine": manifest["quarantine"],
            "runtime": {"hero": 1, "units": len(balance["units"]), "enemies": len(balance["enemies"]),
                        "stages": len(balance["stages"]),
                        "levelRows": sum(len(u["levels"]) for u in balance["units"].values())},
            "diff": f"data/balance/{BALANCE_VERSION}.diff.md"}, indent=2, ensure_ascii=False), encoding="utf-8")
        manifest_assets = json.loads((ROOT / "data/assets/asset-manifest.json").read_text(encoding="utf-8"))
        asset_errors = asset_audit(balance, manifest_assets, *release_and_repo_files())
        checks.append({"id": "t-asset", "status": "PASS" if not asset_errors else "FAIL", "errors": asset_errors,
                       "note": "manifest coverage + forbidden files only; visual/licence review is manual"})
    except (DataError, OSError, ValueError, KeyError) as error:
        checks.append({"id": "regeneration-diff0/t-asset", "status": "FAIL", "reason": str(error)})
    status = "PASS" if all(c["status"] == "PASS" for c in checks) else "FAIL"
    (out / "report.json").write_text(json.dumps({"runId": run_id, "suite": "T-DATA+T-ASSET", "status": status,
                                                 "cases": checks}, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "report": str(out / "report.json")}))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
