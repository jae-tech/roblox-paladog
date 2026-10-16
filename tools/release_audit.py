"""Production release audit (remake): builds default.project.json and checks it carries no test harness,
foreign scripts, external fetches/asset ids or unmanifested assets. Exit 0 PASS, 1 FAIL."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from balance_lib import asset_audit, release_and_repo_files  # noqa: E402
from verify_p0 import audit_production  # noqa: E402
from toolchain import tool  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


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


def main():
    with tempfile.TemporaryDirectory() as directory:
        rbxlx = Path(directory) / "production.rbxlx"
        subprocess.run([tool("rojo"), "build", "default.project.json", "-o", str(rbxlx)], cwd=ROOT, check=True,
                       capture_output=True)
        try:
            report = audit_release(
                rbxlx, json.loads((ROOT / "data/assets/asset-manifest.json").read_text(encoding="utf-8")),
                json.loads((ROOT / "data/balance/mvp-proto-001.json").read_text(encoding="utf-8")),
                *release_and_repo_files())
        except (OSError, ValueError, KeyError) as error:
            print(json.dumps({"status": "FAIL", "reason": str(error)}, ensure_ascii=False))
            return 1
    print(json.dumps({"status": "PASS", **report}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
