"""Host pins and Windows checkout regression coverage (no network required)."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).parents[1]))
import setup_tools
import toolchain


class ToolchainTests(unittest.TestCase):
    def test_both_hosts_keep_existing_versions(self):
        mac = toolchain.host_lock("Darwin", "arm64")
        win = toolchain.host_lock("Windows", "AMD64")
        versions = {a["name"]: a["version"] for a in win["assets"]}
        self.assertEqual(versions, {"luau": "0.742", "stylua": "2.6.0", "rojo": "7.7.1",
                                    "selene": "0.32.0", "luau-lsp": "1.70.1",
                                    "roblox-types": "luau-lsp-1.70.1"})
        self.assertEqual({a["name"]: a["version"] for a in mac["assets"]},
                         {k: versions[k] for k in ("luau", "stylua", "roblox-types")})
        for host in (mac, win):
            for asset in host["assets"]:
                self.assertRegex(asset["sha256"], r"^[0-9a-f]{64}$")
                self.assertTrue(asset["url"].startswith("https://"))

    def test_unsupported_host_is_blocked_not_other_platform(self):
        for system, machine in (("Linux", "x86_64"), ("Windows", "ARM64")):
            with self.subTest(system=system, machine=machine), self.assertRaisesRegex(ValueError, "BLOCKED"):
                toolchain.host_lock(system, machine)

    def test_windows_executables_are_explicit_local_exe(self):
        for name in ("luau", "luau-analyze", "stylua", "rojo", "selene", "luau-lsp"):
            path = toolchain.tool(name, system="Windows")
            self.assertEqual(path.suffix, ".exe")
            self.assertTrue(path.is_relative_to(toolchain.ROOT / ".tools"))

    def test_macos_keeps_rokit_commands_and_local_cli(self):
        self.assertEqual(toolchain.tool("rojo", system="Darwin"), "rojo")
        self.assertEqual(toolchain.tool("luau", system="Darwin"),
                         toolchain.ROOT / ".tools/luau-0.742/luau")

    def test_archive_checksum_checked_before_extract(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            archive = cache / "luau.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("luau.exe", b"untrusted")
            asset = {"name": "luau", "version": "0.742", "sha256": "0" * 64, "url": "https://invalid"}
            with patch.object(setup_tools, "download"), self.assertRaisesRegex(ValueError, "checksum"):
                setup_tools.install_asset(asset, cache, cache)
            self.assertFalse((cache / "luau-0.742").exists())

    def test_verified_cached_archive_extracts_without_download(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            archive = cache / "luau.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("luau.exe", b"fixture")
            asset = {"name": "luau", "version": "0.742", "url": "https://invalid",
                     "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
            with patch.object(setup_tools, "download") as download:
                setup_tools.install_asset(asset, cache, cache)
            download.assert_not_called()
            self.assertEqual((cache / "luau-0.742/luau.exe").read_bytes(), b"fixture")

    def test_shared_definitions_keep_lsp_location(self):
        with tempfile.TemporaryDirectory() as directory:
            tools = Path(directory)
            cache = tools / "host"
            cache.mkdir()
            data = b"-- pinned definitions\n"
            (cache / "roblox-types.d.luau").write_bytes(data)
            asset = {"name": "roblox-types", "url": "https://invalid",
                     "sha256": hashlib.sha256(data).hexdigest()}
            with patch.object(setup_tools, "download") as download:
                setup_tools.install_asset(asset, cache, tools)
            download.assert_not_called()
            self.assertEqual((tools / "roblox-types.d.luau").read_bytes(), data)

    def test_setup_unsupported_host_returns_blocked_before_install(self):
        with patch.object(setup_tools, "host_lock", side_effect=ValueError("BLOCKED: unsupported")), \
                patch.object(setup_tools, "install_asset") as install, patch("builtins.print"):
            self.assertEqual(setup_tools.main(), 2)
            install.assert_not_called()

    def test_archive_rejects_posix_and_windows_escape_paths(self):
        for name in ("../outside", "/outside", "C:/outside", "..\\outside", "C:outside"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                cache = Path(directory)
                archive = cache / "luau.zip"
                with zipfile.ZipFile(archive, "w") as stream:
                    stream.writestr(name, b"untrusted")
                asset = {"name": "luau", "version": "0.742", "url": "https://invalid",
                         "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
                with patch.object(setup_tools, "download"), self.assertRaisesRegex(ValueError, "unsafe archive"):
                    setup_tools.install_asset(asset, cache, cache)


class CheckoutTests(unittest.TestCase):
    def test_lf_policy_survives_windows_autocrlf_clone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, clone = root / "repo", root / "clone"
            repo.mkdir()
            def git(*args, cwd=repo):
                return subprocess.run(["git", *args], cwd=cwd, capture_output=True, check=True)
            git("init")
            git("config", "core.autocrlf", "true")
            (repo / ".gitattributes").write_bytes((toolchain.ROOT / ".gitattributes").read_bytes())
            sample = "원문 SHA와 생성물은 LF를 유지한다.\n".encode("utf-8")
            (repo / "reference.md").write_bytes(sample)
            git("add", ".")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture")
            git("clone", "--config", "core.autocrlf=true", str(repo), str(clone))
            self.assertEqual((clone / "reference.md").read_bytes(), sample)


if __name__ == "__main__":
    unittest.main()
