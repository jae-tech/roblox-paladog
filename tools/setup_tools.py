"""Install only pinned P0 binaries into ignored .tools; never modifies global tools."""
import hashlib
from pathlib import Path, PureWindowsPath
import subprocess
import sys
from urllib.request import urlopen
import zipfile

from toolchain import ROOT, archive_path, host_lock


def download(url, destination):
    with urlopen(url, timeout=120) as response:
        destination.write_bytes(response.read())


def install_asset(asset, cache, tools):
    destination = archive_path(asset, cache)
    if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != asset["sha256"]:
        download(asset["url"], destination)
    if hashlib.sha256(destination.read_bytes()).hexdigest() != asset["sha256"]:
        raise ValueError("FAIL: checksum mismatch: " + asset["name"])
    if destination.suffix != ".zip":
        # Keep the shared definitions at the path used by luau-lsp.
        (tools / "roblox-types.d.luau").write_bytes(destination.read_bytes())
        return
    directory = tools / (asset["name"] + "-" + asset["version"])
    with zipfile.ZipFile(destination) as archive:
        for member in archive.infolist():
            path, windows = Path(member.filename), PureWindowsPath(member.filename)
            if path.is_absolute() or windows.drive or windows.root or ".." in path.parts or ".." in windows.parts:
                raise ValueError("FAIL: unsafe archive path")
        directory.mkdir(exist_ok=True)
        archive.extractall(directory)
    for binary in directory.iterdir():
        if binary.is_file():
            binary.chmod(binary.stat().st_mode | 0o111)


def main():
    try:
        lock = host_lock()
    except ValueError as error:
        print(error)
        return 2
    tools = ROOT / ".tools"
    cache = tools / lock["platform"]
    cache.mkdir(parents=True, exist_ok=True)
    for asset in lock["assets"]:
        install_asset(asset, cache, tools)
    if lock["platform"] == "Darwin-arm64":
        subprocess.run(["rokit", "install"], cwd=ROOT, check=True)
    print("Pinned local tools ready; this is not a Studio runtime test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
