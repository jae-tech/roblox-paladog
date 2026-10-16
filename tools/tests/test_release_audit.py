import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_audit as gate  # noqa: E402

MANIFEST = json.loads((gate.ROOT / "data/assets/asset-manifest.json").read_text(encoding="utf-8"))
BALANCE = json.loads((gate.ROOT / "data/balance/mvp-proto-001.json").read_text(encoding="utf-8"))


class ReleaseAuditTests(unittest.TestCase):
    def audit(self, source, scripts=1, manifest=MANIFEST):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "production.rbxlx"
            path.write_text('<roblox><Item class="ModuleScript"><Properties><ProtectedString name="Source">'
                            + source + "</ProtectedString></Properties></Item></roblox>", encoding="utf-8")
            return gate.audit_release(path, manifest, BALANCE, ["src/a.luau"] * scripts, [])

    def test_clean_build(self):
        self.assertEqual(self.audit("local id = HttpService:GenerateGUID(false)")["scripts"], 1)

    def test_rejected(self):
        for source in ('local i = "rbxassetid://123"', "HttpService:GetAsync(u)", "require(4567)",
                       "loadstring(s)", "-- https://x"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                self.audit(source)

    def test_uploaded_asset_allowed(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["entries"][0].update(status="uploaded", assetId=123)
        self.audit('local i = "rbxassetid://123"', manifest=manifest)

    def test_foreign_script_rejected(self):
        with self.assertRaises(ValueError):
            self.audit("return 1", scripts=2)


if __name__ == "__main__":
    unittest.main()
