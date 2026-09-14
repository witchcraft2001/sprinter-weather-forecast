#!/usr/bin/env python3
"""Validate pinned submodules and the prebuilt UNET runtime DLLs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

SUBMODULES = {
    "extern/sprinter-libs": (
        ".gitmodules",
        "extern/sprinter-libs",
        "git@github.com:witchcraft2001/sprinter-libs.git",
        "a1604d7a4dc9258617e8c2b7b0e53d8eb04d1868",
    ),
    "extern/unet_libs_asm": (
        ".gitmodules",
        "extern/unet_libs_asm",
        "https://github.com/witchcraft2001/sprinter_unet_libs_asm.git",
        "c79186a445b5ce6e28901232aea793e81e72b73e",
    ),
    "extern/unet_libs_asm/extern/core": (
        "extern/unet_libs_asm/.gitmodules",
        "extern/core",
        "https://github.com/witchcraft2001/unet_libs_core.git",
        "9c10b7b3b3b1fe7de0ebe8d36b881d3e31732cc3",
    ),
    "extern/unet_libs_asm/extern/libman": (
        "extern/unet_libs_asm/.gitmodules",
        "extern/libman",
        "https://github.com/witchcraft2001/sprinter-libman.git",
        "f042e3359e516bd602a0e23c06945f6f5bfe13c2",
    ),
}

GRAPHICS_DLLS = {
    "extern/sprinter-libs/afnt320/AFNT320.DLL": (
        "AFNT320.DLL",
        ""),
    "extern/sprinter-libs/gfx320/GFX320.DLL": (
        "GFX320.DLL",
        "fc7c0271e20e93be520933f193d0e70a7883940a5b5b131de34fddad333b1f48",
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

    for rel_path, (modules_file, module_name, expected_url, expected_commit) in SUBMODULES.items():
        path = ROOT / rel_path
        actual_url = run(
            "git",
            "config",
            "-f",
            str(ROOT / modules_file),
            "--get",
            f"submodule.{module_name}.url",
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
    dll_dir = ROOT / "extern/unet_libs_asm/extern/core/dll"
    manifest = json.loads((dll_dir / "manifest.json").read_text(encoding="utf-8"))
    if not manifest:
        fail("UNET DLL manifest is empty")
    actual_names = {path.name for path in dll_dir.glob("UNET*.DLL")}
    if actual_names != set(manifest):
        fail(f"UNET DLL directory differs from manifest: {sorted(actual_names)}")
    for name, entry in manifest.items():
        if re.fullmatch(r"UNET[A-Z0-9]{3,4}\.DLL", name) is None:
            fail(f"manifest DLL is not a valid UNET 8.3 name: {name}")
        if entry.get("tag") != name[4:-4]:
            fail(f"{name}: manifest tag does not match the filename")
        path = dll_dir / name
        if not path.is_file():
            fail(f"prebuilt DLL is missing: {path.relative_to(ROOT)}")
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if len(data) != entry["size"]:
            fail(f"{name}: size {len(data)}, expected {entry['size']}")
        if digest != entry["sha256"]:
            fail(f"{name}: SHA-256 {digest}, expected {entry['sha256']}")

    for rel_path, (name, expected_sha256) in GRAPHICS_DLLS.items():
        path = ROOT / rel_path
        if not path.is_file():
            fail(f"prebuilt graphics DLL is missing: {rel_path}")
        if path.name != name:
            fail(f"unexpected graphics DLL name: {path.name}")
        if expected_sha256:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != expected_sha256:
                fail(f"{rel_path}: unexpected SHA-256 {digest}")


def verify_with_libman() -> None:
    unet_root = ROOT / "extern/unet_libs_asm"
    core_root = unet_root / "extern/core"
    libman_root = unet_root / "extern/libman"
    env = os.environ.copy()
    env["LIBMAN_ROOT"] = str(libman_root)
    subprocess.run(
        [sys.executable, str(core_root / "tools/check_dlls.py"), "--require-mkdll"],
        check=True,
        env=env,
    )
    subprocess.run(
        [sys.executable, str(core_root / "tools/gen_bindings.py"), "check"],
        check=True,
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
