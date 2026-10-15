"""Install only pinned P0 binaries into ignored .tools; never modifies global tools."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    if (platform.system(), platform.machine()) != ("Darwin", "arm64"):
        raise SystemExit("BLOCKED: pinned local bootstrap supports Darwin arm64 only; record/pin other host first")
    cache = ROOT / ".tools"
    cache.mkdir(exist_ok=True)
    lock = json.loads((ROOT / "tools/toolchain-lock.json").read_text())
    for asset in lock["assets"]:
        destination = cache / (asset["name"] + (".d.luau" if asset["name"] == "roblox-types" else ".zip"))
        subprocess.run(["curl", "-fLsS", asset["url"], "-o", str(destination)], check=True)
        if hashlib.sha256(destination.read_bytes()).hexdigest() != asset["sha256"]:
            raise SystemExit("FAIL: checksum mismatch: " + asset["name"])
        if destination.suffix == ".zip":
            directory = cache / (asset["name"] + "-" + asset["version"])
            directory.mkdir(exist_ok=True)
            with zipfile.ZipFile(destination) as archive:
                for member in archive.infolist():
                    if Path(member.filename).is_absolute() or ".." in Path(member.filename).parts:
                        raise SystemExit("FAIL: unsafe archive path")
                archive.extractall(directory)
            for binary in directory.iterdir():
                if binary.is_file():
                    binary.chmod(binary.stat().st_mode | 0o111)
    subprocess.run(["rokit", "install"], cwd=ROOT, check=True)
    print("Pinned local tools ready; this is not a Studio runtime test.")


if __name__ == "__main__":
    main()
