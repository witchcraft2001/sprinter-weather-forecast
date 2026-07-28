#!/usr/bin/env python3
"""Validate pinned submodules and the prebuilt UNET runtime DLLs."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent

SUBMODULES = {
    "extern/esp_net": (
        "git@github.com:witchcraft2001/sprinter_net.git",
        "019dbfeb8bbb38b6681d5a2634078057d24e4b0e",
    ),
    "extern/rtl_net": (
        "git@github.com:witchcraft2001/sprinter-rtl8019a.git",
        "68c6d45ab23899dfa3da4a9b594b3de9fb7f2c43",
    ),
    "extern/libman": (
        "git@github.com:witchcraft2001/sprinter-libman.git",
        "18bc17b75400ebea60fdd2f68b8bc4476ef8254f",
    ),
    "extern/sprinter-libs": (
        "git@github.com:witchcraft2001/sprinter-libs.git",
        "169f515f4d5a8142eab1b8783146f7388b7dba74",
    ),
}

DLLS = {
    "extern/esp_net/UNETESP.DLL": (
        10_720,
        "f03352df4f4af42683d1fde4a8260d0bd3a55f51b1366f10b5467b38566e9abc",
    ),
    "extern/rtl_net/UNETRTL.DLL": (
        13_651,
        "051e53b1a4c10f3a41ddad8ad3f26dd974786ebd821c17f8202fb2d91b702fb1",
    ),
}


def run(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def fail(message: str) -> None:
    raise SystemExit(f"Error: {message}")


def check_python() -> None:
    if sys.version_info < (3, 10):
        fail("Python 3.10 or newer is required")


def check_submodules(check_clean: bool) -> None:
    gitmodules = ROOT / ".gitmodules"
    if not gitmodules.is_file():
        fail(".gitmodules is missing; run git submodule update --init --recursive")

    for rel_path, (expected_url, expected_commit) in SUBMODULES.items():
        path = ROOT / rel_path
        name = rel_path
        actual_url = run(
            "git",
            "config",
            "-f",
            str(gitmodules),
            "--get",
            f"submodule.{name}.url",
        )
        if actual_url != expected_url:
            fail(f"{rel_path}: URL is {actual_url!r}, expected {expected_url!r}")
        if not (path / ".git").exists():
            fail(f"{rel_path} is not initialized; run git submodule update --init --recursive")
        actual_commit = run("git", "rev-parse", "HEAD", cwd=path)
        if actual_commit != expected_commit:
            fail(f"{rel_path}: commit {actual_commit}, expected {expected_commit}")
        if check_clean and run("git", "status", "--porcelain", cwd=path):
            fail(f"{rel_path} has local changes")


def check_dlls() -> None:
    for rel_path, (expected_size, expected_sha256) in DLLS.items():
        path = ROOT / rel_path
        if not path.is_file():
            fail(f"prebuilt DLL is missing: {rel_path}")
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if len(data) != expected_size:
            fail(f"{rel_path}: size {len(data)}, expected {expected_size}")
        if digest != expected_sha256:
            fail(f"{rel_path}: SHA-256 {digest}, expected {expected_sha256}")

    esp_inc = (ROOT / "extern/esp_net/src/include/unet.inc").read_bytes()
    rtl_inc = (ROOT / "extern/rtl_net/src/include/unet.inc").read_bytes()
    if esp_inc != rtl_inc:
        fail("UNET ABI include files in ESP and RTL submodules differ")


def verify_with_libman() -> None:
    libman_src = ROOT / "extern/libman/src"
    env = os.environ.copy()
    env["PYTHONPATH"] = str(libman_src)
    for rel_path in DLLS:
        subprocess.run(
            [
                sys.executable,
                "-m",
                "sprinter_mkdll.cli",
                "verify",
                str(ROOT / rel_path),
                "--target",
                "1.3",
            ],
            check=True,
            env=env,
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-clean",
        action="store_true",
        help="also reject local changes inside submodules",
    )
    args = parser.parse_args()

    check_python()
    check_submodules(args.check_clean)
    check_dlls()
    verify_with_libman()
    print("Dependencies: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
