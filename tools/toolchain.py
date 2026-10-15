"""Pinned host selection and executable locations; no installation side effects."""
import json
from pathlib import Path
import platform

ROOT = Path(__file__).resolve().parents[1]
VERSIONS = {"luau": "0.742", "stylua": "2.6.0", "rojo": "7.7.1",
            "selene": "0.32.0", "luau-lsp": "1.70.1"}


def host_lock(system=None, machine=None):
    host = (system or platform.system()) + "-" + (machine or platform.machine())
    locks = json.loads((ROOT / "tools/toolchain-lock.json").read_text(encoding="utf-8"))
    if host not in locks["platforms"]:
        raise ValueError("BLOCKED: no pinned toolchain for " + host)
    return {"platform": host, "assets": locks["platforms"][host]}


def tool(name, system=None):
    windows = (system or platform.system()) == "Windows"
    if not windows and name in ("rojo", "selene", "luau-lsp"):
        return name  # Existing macOS rokit installation.
    package = "luau" if name == "luau-analyze" else name
    return ROOT / ".tools" / (package + "-" + VERSIONS[package]) / (name + (".exe" if windows else ""))


def archive_path(asset, cache):
    return cache / (asset["name"] + (".d.luau" if asset["name"] == "roblox-types" else ".zip"))
