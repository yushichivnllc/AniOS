"""Kiểm thử shortcut Linux: file .desktop, icon và script cài đặt."""
from __future__ import annotations

import configparser
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESKTOP = ROOT / "data" / "anios-manga.desktop"


def _entry():
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read(DESKTOP, encoding="utf-8")
    return parser["Desktop Entry"]


def test_desktop_entry_is_launchable():
    entry = _entry()
    assert entry["Type"] == "Application"
    assert entry["Exec"].split()[0] == "anios-manga"
    assert entry["TryExec"] == "anios-manga"
    assert entry["Icon"] == "anios-manga"
    assert entry["Name"]


def test_desktop_entry_matches_console_script_and_icon():
    assert (ROOT / "data" / "anios-manga.svg").is_file()
    pyproject = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    assert 'anios-manga = "anios_manga.__main__:main"' in pyproject


def test_install_script_installs_into_user_dirs(tmp_path):
    script = ROOT / "install-desktop.sh"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    exe = fake_bin / "anios-manga"
    exe.write_text("#!/bin/sh\nexit 0\n")
    exe.chmod(0o755)
    env = {
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "HOME": str(tmp_path / "home"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
    }
    result = subprocess.run(["sh", str(script)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    installed = tmp_path / "data" / "applications" / "anios-manga.desktop"
    text = installed.read_text(encoding="utf-8")
    assert f"Exec={exe}" in text
    assert (tmp_path / "data" / "icons" / "hicolor" / "scalable" / "apps" / "anios-manga.svg").is_file()

    result = subprocess.run(["sh", str(script), "--uninstall"], env=env, capture_output=True, text=True)
    assert result.returncode == 0
    assert not installed.exists()
